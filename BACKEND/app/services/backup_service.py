"""
Servicio de Backups (módulo Gestión de TIC).

Fuentes reales del sistema (verificado en el código):
  - BD PostgreSQL (DATABASE_URL) → pg_dump -Fc (custom format, comprimido).
  - Archivos: TODO lo persistente vive en Cloudinary (los PDFs se suben como
    resource_type="raw"; las imágenes como "image"). No existen archivos en
    el disco del servidor. Por eso "backup de PDFs" y "backup de Cloudinary"
    son el mismo paquete .tar.gz con manifest.json.

Destino: BACKUP_DIR (env). En Railway apuntar a un volumen persistente
(p. ej. /data/backups); en cualquier otro servidor, a un directorio durable.
Si no está seteada, cae a un directorio local (efímero en Railway: los
artefactos se pierden en cada redeploy, pero el dump de BD es regenerable
al vuelo desde la pantalla de descarga).

Portabilidad: no hay NADA específico de Railway aquí — solo variables de
entorno estándar (DATABASE_URL, BACKUP_DIR, MAIL_*, credenciales Cloudinary).

Correo: el dump diario de BD se envía como adjunto vía SMTP usando las
variables MAIL_* ya existentes en el .env. Si el servidor bloquea SMTP
(Railway lo hace en algunos planes — por eso el proyecto ya usa un webhook
de Google Script para los OTP), se degrada a un aviso HTML sin adjunto por
ese mismo webhook.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import shutil
import smtplib
import subprocess
import tarfile
import tempfile
import threading
import uuid as _uuid
import zipfile
from datetime import datetime, date, timedelta
from email.message import EmailMessage
from pathlib import Path

import requests
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.models.backup_job import BackupJob, BackupConfig

logger = logging.getLogger("backups")

# ── Configuración ────────────────────────────────────────────────────────────

BACKUP_DIR = Path(os.getenv("BACKUP_DIR", os.path.join(tempfile.gettempdir(), "e-zyro-backups")))

# Prefijos de carpetas Cloudinary a respaldar (taxonomía actual + legacy)
PREFIJOS_CLOUDINARY = ("e-zyro", "e_zyro", "evidencias")
RESOURCE_TYPES = ("image", "raw", "video")

# Retención GFS (días de vida por nivel)
RETENCION_DIAS = {"horario": 2, "diario": 7, "semanal": 28, "mensual": 365}

DIAS_SEMANA = ("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")


# ── Programación editable (tabla backup_config, fila única id=1) ─────────────

def obtener_config(db: Session) -> BackupConfig:
    """Devuelve la fila única de configuración; la crea con defaults si no existe."""
    cfg = db.query(BackupConfig).filter(BackupConfig.id == 1).first()
    if not cfg:
        cfg = BackupConfig(id=1)
        db.add(cfg)
        db.commit()
        db.refresh(cfg)
    return cfg


def resumen_config(cfg: BackupConfig) -> dict:
    """Texto legible de la programación vigente (sección config del frontend)."""
    if not cfg.bd_auto:
        bd = "Desactivados (solo backups manuales)"
    elif cfg.bd_frecuencia == "cada_hora":
        bd = (f"Cada hora en punto (silencioso, retención 48 h) + consolidado diario "
              f"{cfg.bd_hora} con notificación y correo (GFS: dom→semanal, día 1→mensual)")
    elif cfg.bd_frecuencia == "semanal":
        bd = (f"Semanal: {DIAS_SEMANA[cfg.bd_dia_semana]} {cfg.bd_hora} "
              f"(notifica{' + correo' if cfg.bd_correo else ''}, retención 28 días)")
    else:
        bd = (f"Diario {cfg.bd_hora} (notifica{' + correo' if cfg.bd_correo else ''}, "
              f"retención 7 días; domingo → semanal 28 días; día 1 → mensual 365 días)")
    archivos = ("Incremental cada hora (min 20, silencioso) + paquete completo domingo 22:00"
                if cfg.archivos_auto else "Desactivados (solo backups manuales)")
    return {
        "base_de_datos": bd,
        "archivos_cloudinary": archivos,
        "rotacion": "Limpieza de expirados: diaria 03:00 (GFS 48h / 7d / 4sem / 12m)",
        "formato_bd": "SQL plano (.sql) — se abre con cualquier editor y se restaura con psql",
    }


# ── Cancelación cooperativa de jobs ──────────────────────────────────────────
# El worker (hilo o job del scheduler) chequea la bandera entre fases y entre
# archivos; si hay un pg_dump corriendo se le hace terminate directamente.

class BackupCancelado(Exception):
    pass


_CANCEL_LOCK = threading.Lock()
_CANCELADOS: set[str] = set()
_PROCESOS: dict[str, subprocess.Popen] = {}


def solicitar_cancelacion(job_id: str) -> None:
    with _CANCEL_LOCK:
        _CANCELADOS.add(job_id)
        proc = _PROCESOS.get(job_id)
    if proc and proc.poll() is None:
        try:
            proc.terminate()
        except Exception:
            pass


def _chequear_cancelacion(job_id: str | None) -> None:
    if job_id:
        with _CANCEL_LOCK:
            if job_id in _CANCELADOS:
                raise BackupCancelado()


def _limpiar_cancelacion(job_id: str) -> None:
    with _CANCEL_LOCK:
        _CANCELADOS.discard(job_id)
        _PROCESOS.pop(job_id, None)


def _ensure_dir() -> Path:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    return BACKUP_DIR


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _database_url() -> str:
    url = os.getenv("DATABASE_URL", "")
    if not url:
        # mismo fallback que usa app/db/database.py si aplica (.env ya cargado por la app)
        raise RuntimeError("DATABASE_URL no configurada")
    return url


# ── Fuente 1: dump de PostgreSQL ─────────────────────────────────────────────

def _dump_bd(destino: Path, job_id: str | None = None) -> None:
    """pg_dump en SQL PLANO (.sql): legible en cualquier editor y restaurable
    con `psql -f archivo.sql`. Requiere postgresql-client >= versión del
    servidor (18) en la imagen. Si `job_id` viene, el proceso queda registrado
    para poder cancelarlo (terminate) desde el endpoint de cancelación."""
    _chequear_cancelacion(job_id)
    cmd = ["pg_dump", "--format=plain", "--no-owner", "--no-privileges",
           f"--file={destino}", _database_url()]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if job_id:
        with _CANCEL_LOCK:
            _PROCESOS[job_id] = proc
    try:
        _, stderr = proc.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        proc.kill()
        destino.unlink(missing_ok=True)
        raise RuntimeError("pg_dump excedió los 10 minutos")
    finally:
        if job_id:
            with _CANCEL_LOCK:
                _PROCESOS.pop(job_id, None)
    if proc.returncode != 0:
        destino.unlink(missing_ok=True)  # dump parcial inservible
        _chequear_cancelacion(job_id)    # terminate por cancelación → cancelado, no error
        raise RuntimeError(f"pg_dump falló (rc={proc.returncode}): {(stderr or '')[-800:]}")


# ── Fuente 2: archivos en Cloudinary (PDFs raw + imágenes + video) ──────────

def _listar_cloudinary(desde: datetime | None, hasta: datetime | None = None,
                       job_id: str | None = None) -> list[dict]:
    """Lista recursos de Cloudinary por prefijo/resource_type, paginando.
    Si `desde` viene, filtra client-side por created_at (incremental).
    Si `hasta` viene, excluye lo subido después (regeneración de un job viejo:
    reproduce la ventana original en vez de empaquetar cosas nuevas)."""
    import cloudinary.api  # config ya inicializada por app.core.config_cloudinary
    recursos: list[dict] = []
    for rt in RESOURCE_TYPES:
        for prefijo in PREFIJOS_CLOUDINARY:
            cursor = None
            while True:
                _chequear_cancelacion(job_id)
                kwargs = {"type": "upload", "resource_type": rt, "prefix": prefijo,
                          "max_results": 500}
                if cursor:
                    kwargs["next_cursor"] = cursor
                try:
                    resp = cloudinary.api.resources(**kwargs)
                except Exception as e:
                    logger.warning("Listado Cloudinary %s/%s falló: %s", rt, prefijo, e)
                    break
                for r in resp.get("resources", []):
                    creado = r.get("created_at")  # ISO "2026-07-05T10:00:00Z"
                    if (desde or hasta) and creado:
                        try:
                            dt = datetime.fromisoformat(creado.replace("Z", "+00:00")).replace(tzinfo=None)
                            if desde and dt <= desde:
                                continue
                            if hasta and dt > hasta:
                                continue
                        except ValueError:
                            pass
                    recursos.append({
                        "public_id":     r.get("public_id"),
                        "resource_type": rt,
                        "format":        r.get("format"),
                        "bytes":         r.get("bytes"),
                        "created_at":    creado,
                        "secure_url":    r.get("secure_url"),
                    })
                cursor = resp.get("next_cursor")
                if not cursor:
                    break
    return recursos


def _empaquetar_archivos(recursos: list[dict], destino_tar: Path, job_id: str | None = None) -> int:
    """Descarga cada recurso y lo empaqueta en un .tar.gz junto a manifest.json.
    Devuelve cuántos archivos entraron. Los que fallan quedan anotados en el
    manifiesto con error (el backup no se cae por un asset corrupto)."""
    empaquetados = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        for r in recursos:
            _chequear_cancelacion(job_id)
            url = r.get("secure_url")
            if not url:
                r["error"] = "sin secure_url"
                continue
            # nombre plano y único dentro del tar (el public_id trae carpetas)
            ext = f".{r['format']}" if r.get("format") else ""
            nombre = r["public_id"].replace("/", "__") + ext
            try:
                with requests.get(url, stream=True, timeout=120) as resp:
                    resp.raise_for_status()
                    with open(tmp_path / nombre, "wb") as f:
                        for chunk in resp.iter_content(1024 * 256):
                            f.write(chunk)
                r["archivo_en_tar"] = nombre
                empaquetados += 1
            except Exception as e:
                r["error"] = str(e)[:300]
                logger.warning("No se pudo descargar %s: %s", r["public_id"], e)

        manifest = {
            "generado_en": datetime.utcnow().isoformat() + "Z",
            "total_listados": len(recursos),
            "total_empaquetados": empaquetados,
            "recursos": recursos,
        }
        with open(tmp_path / "manifest.json", "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)

        with tarfile.open(destino_tar, "w:gz") as tar:
            for archivo in sorted(tmp_path.iterdir()):
                tar.add(archivo, arcname=archivo.name)
    return empaquetados


# ── Correo (SMTP con adjunto; fallback webhook sin adjunto) ──────────────────

def _correos_soporte(db: Session) -> list[str]:
    from app.models.usuario import Usuario
    from app.models.usuario_rol import UsuarioRol
    from app.models.rol import Rol
    rows = (
        db.query(Usuario.email)
        .join(UsuarioRol, UsuarioRol.usuario_id == Usuario.id)
        .join(Rol, Rol.id == UsuarioRol.rol_id)
        .filter(Usuario.activo.is_(True), Rol.nombre == "Soporte")
        .distinct().all()
    )
    return [r.email for r in rows if r.email]


def _enviar_dump_por_correo(path: Path, destinatarios: list[str], asunto: str, cuerpo: str) -> bool:
    """Intenta SMTP (MAIL_* del .env) con el dump adjunto. Si el servidor
    bloquea SMTP, degrada a aviso sin adjunto por el webhook de Google Script
    ya usado por el proyecto para los OTP."""
    if not destinatarios:
        return False
    servidor = os.getenv("MAIL_SERVER")
    try:
        if not servidor:
            raise RuntimeError("MAIL_SERVER no configurado")
        msg = EmailMessage()
        msg["Subject"] = asunto
        msg["From"]    = os.getenv("MAIL_FROM", os.getenv("MAIL_USERNAME", ""))
        msg["To"]      = ", ".join(destinatarios)
        msg.set_content(cuerpo)
        # El dump ahora es .sql plano (grande): se adjunta comprimido en .zip
        # (formato nativo de Windows, se abre con doble clic).
        if path.suffix == ".sql":
            import io
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
                z.write(path, arcname=path.name)
            msg.add_attachment(buf.getvalue(), maintype="application",
                               subtype="zip", filename=path.name + ".zip")
        else:
            msg.add_attachment(path.read_bytes(), maintype="application",
                               subtype="octet-stream", filename=path.name)
        puerto = int(os.getenv("MAIL_PORT", "587"))
        with smtplib.SMTP(servidor, puerto, timeout=60) as s:
            s.starttls()
            s.login(os.getenv("MAIL_USERNAME", ""), os.getenv("MAIL_PASSWORD", ""))
            s.send_message(msg)
        logger.info("Dump enviado por SMTP a %d destinatarios", len(destinatarios))
        return True
    except Exception as e:
        logger.warning("SMTP no disponible (%s); aviso sin adjunto por webhook", e)
        try:
            from app.core.email import URL_GOOGLE_SCRIPT
            html = f"<html><body style='font-family:sans-serif'><h3>{asunto}</h3><p>{cuerpo}</p><p>El adjunto no pudo enviarse por SMTP desde este servidor — descarga el backup desde <b>Gestión TIC → Backups</b>.</p></body></html>"
            for dest in destinatarios:
                requests.post(URL_GOOGLE_SCRIPT, json={"to": dest, "subject": asunto, "html": html}, timeout=30)
            return True
        except Exception as e2:
            logger.error("Fallback de correo también falló: %s", e2)
            return False


# ── Notificaciones (reusa helpers del scheduler: in-app + push FCM) ─────────

def _notificar_soporte(db: Session, titulo: str, mensaje: str, ref_key: str, tipo: str = "info") -> None:
    from app.services.scheduler_service import _usuarios_por_rol, _emitir
    from app.models.empresa import Empresa
    for (empresa_id,) in db.query(Empresa.id).all():
        usuarios = _usuarios_por_rol(db, empresa_id, ["Soporte"])
        _emitir(db, empresa_id=empresa_id, usuarios=usuarios, tipo=tipo,
                categoria="backups", titulo=titulo, mensaje=mensaje,
                ref_key=f"{ref_key}:{empresa_id}")
    db.commit()


def _fmt_bytes(n: int | None) -> str:
    if not n:
        return "—"
    for unidad in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unidad}" if unidad != "B" else f"{n} B"
        n /= 1024
    return f"{n:.1f} TB"


# ── Núcleo: ejecutar un backup (corre en hilo de fondo o en job del scheduler)

def _retencion_de_hoy() -> tuple[str, int]:
    """Nivel GFS que corresponde al backup diario según la fecha (promoción)."""
    hoy = date.today()
    if hoy.day == 1:
        return "mensual", RETENCION_DIAS["mensual"]
    if hoy.weekday() == 6:  # domingo
        return "semanal", RETENCION_DIAS["semanal"]
    return "diario", RETENCION_DIAS["diario"]


def crear_job(db: Session, *, tipo: str, nivel: str, contenido: str,
              disparado_por: str | None, retencion: str) -> BackupJob:
    job = BackupJob(
        id=str(_uuid.uuid4()), tipo=tipo, nivel=nivel, contenido=contenido,
        disparado_por=disparado_por, estado="pendiente", retencion=retencion,
        expira_en=date.today() + timedelta(days=RETENCION_DIAS.get(retencion, 7)),
        fecha_inicio=datetime.utcnow(),
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


def ejecutar_backup(job_id: str, *, notificar: bool, enviar_correo: bool = False,
                    incremental_desde: datetime | None = None) -> None:
    """Ejecuta el backup de la fila `job_id`. Diseñada para correr en un hilo
    (threading.Thread) o dentro de un job de APScheduler — nunca bloquea el
    request. Sesión de BD propia."""
    db: Session = SessionLocal()
    try:
        job = db.query(BackupJob).filter(BackupJob.id == job_id).first()
        if not job:
            return
        # Cancelado antes de arrancar (estaba pendiente en cola)
        if job.estado == "cancelado":
            _limpiar_cancelacion(job_id)
            return
        job.estado = "en_proceso"
        db.commit()

        destino_dir = _ensure_dir()
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        partes: list[Path] = []
        detalle_archivos = ""

        try:
            _chequear_cancelacion(job_id)
            if "bd" in job.contenido:
                dump = destino_dir / f"bd_{stamp}_{job.id[:8]}.sql"
                _dump_bd(dump, job_id=job_id)
                partes.append(dump)

            if "cloudinary" in job.contenido:
                recursos = _listar_cloudinary(incremental_desde, job_id=job_id)
                if recursos or incremental_desde is None:
                    tar = destino_dir / f"archivos_{stamp}_{job.id[:8]}.tar.gz"
                    n = _empaquetar_archivos(recursos, tar, job_id=job_id)
                    partes.append(tar)
                    detalle_archivos = f" · {n} archivos"
                else:
                    detalle_archivos = " · sin archivos nuevos"

            # Si hay más de una parte, empaquetar juntas para 1 sola descarga
            if len(partes) > 1:
                paquete = destino_dir / f"backup_completo_{stamp}_{job.id[:8]}.tar.gz"
                with tarfile.open(paquete, "w:gz") as tar:
                    for p in partes:
                        tar.add(p, arcname=p.name)
                for p in partes:
                    p.unlink(missing_ok=True)
                artefacto = paquete
            elif partes:
                artefacto = partes[0]
            else:
                # incremental sin novedades: job completado sin artefacto
                job.estado = "completado"
                job.fecha_fin = datetime.utcnow()
                job.error_detalle = None
                job.ubicacion = None
                db.commit()
                logger.info("Backup %s sin novedades (incremental vacío)", job.id)
                return

            job.ubicacion    = str(artefacto)
            job.tamano_bytes = artefacto.stat().st_size
            job.hash_sha256  = _sha256(artefacto)
            job.estado       = "completado"
            job.fecha_fin    = datetime.utcnow()
            db.commit()

            dur = (job.fecha_fin - job.fecha_inicio).total_seconds()
            logger.info("Backup %s completado en %.1fs — %s (%s)",
                        job.id, dur, artefacto.name, _fmt_bytes(job.tamano_bytes))

            if enviar_correo and "bd" in job.contenido:
                _enviar_dump_por_correo(
                    Path(job.ubicacion), _correos_soporte(db),
                    asunto=f"[E-zyro] Backup {job.nivel} completado — {date.today():%d/%m/%Y}",
                    cuerpo=(f"Backup {job.tipo} ({job.nivel}) completado.\n"
                            f"Tamaño: {_fmt_bytes(job.tamano_bytes)}\n"
                            f"SHA-256: {job.hash_sha256}\n"
                            f"Guárdalo en el disco de respaldos."),
                )

            if notificar:
                _notificar_soporte(
                    db,
                    titulo="Backup completado",
                    mensaje=(f"Backup {job.tipo} ({job.nivel}) listo — "
                             f"{datetime.now():%d/%m %H:%M}, {_fmt_bytes(job.tamano_bytes)}{detalle_archivos}. "
                             f"Descárgalo desde Gestión TIC → Backups."),
                    ref_key=f"backup:{job.id}:ok",
                )

        except BackupCancelado:
            job.estado = "cancelado"
            job.fecha_fin = datetime.utcnow()
            job.error_detalle = None
            db.commit()
            # limpiar artefactos parciales (dump a medias, etc.)
            for p in partes:
                p.unlink(missing_ok=True)
            logger.info("Backup %s CANCELADO por el usuario", job.id)
        except Exception as e:
            job.estado = "fallido"
            job.fecha_fin = datetime.utcnow()
            job.error_detalle = str(e)[:2000]
            db.commit()
            for p in partes:
                p.unlink(missing_ok=True)
            logger.error("Backup %s FALLÓ: %s", job.id, e)
            # Los fallos SIEMPRE se notifican a Soporte (aunque el job fuera silencioso)
            _notificar_soporte(
                db, titulo="Backup FALLIDO", tipo="warning",
                mensaje=f"El backup {job.tipo} ({job.nivel}) falló: {str(e)[:180]}",
                ref_key=f"backup:{job.id}:err",
            )
    finally:
        _limpiar_cancelacion(job_id)
        db.close()


# ── Regeneración al vuelo (descarga de jobs cuyo artefacto ya no está) ──────

def _ventana_incremental(db: Session, job: BackupJob) -> datetime:
    """`desde` que usó (o habría usado) el incremental original: la fecha del
    backup de archivos completado inmediatamente anterior a este job."""
    prev = (db.query(BackupJob.fecha_inicio)
              .filter(BackupJob.contenido.contains("cloudinary"),
                      BackupJob.estado == "completado",
                      BackupJob.id != job.id,
                      BackupJob.fecha_inicio < job.fecha_inicio)
              .order_by(BackupJob.fecha_inicio.desc())
              .first())
    return prev.fecha_inicio if prev else job.fecha_inicio - timedelta(days=7)


def regenerar_artefacto(db: Session, job: BackupJob) -> Path:
    """Reconstruye el artefacto de un job completado cuyo archivo ya no está
    en disco (efímero tras redeploy / borrado por retención). Las fuentes
    reales siguen existiendo, así que TODO backup con contenido es
    regenerable: la BD con un dump nuevo y los archivos reempaquetando desde
    Cloudinary la MISMA ventana temporal del job original (assets borrados de
    Cloudinary después de esa corrida ya no pueden incluirse; queda anotado
    en el manifest). Lanza RuntimeError si el job no produjo artefacto
    (incremental sin novedades)."""
    destino_dir = _ensure_dir()
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    partes: list[Path] = []
    try:
        if "bd" in job.contenido:
            dump = destino_dir / f"bd_regen_{stamp}_{job.id[:8]}.sql"
            _dump_bd(dump)
            partes.append(dump)

        # Solo si la corrida original SÍ empaquetó algo (tamano_bytes seteado);
        # un incremental "sin novedades" no tiene nada que regenerar.
        if "cloudinary" in job.contenido and job.tamano_bytes:
            desde = _ventana_incremental(db, job) if job.nivel == "archivos_incremental" else None
            recursos = _listar_cloudinary(desde, hasta=job.fecha_inicio)
            tar_path = destino_dir / f"archivos_regen_{stamp}_{job.id[:8]}.tar.gz"
            _empaquetar_archivos(recursos, tar_path)
            partes.append(tar_path)

        if not partes:
            raise RuntimeError("este backup no generó artefacto (corrida sin novedades)")

        if len(partes) > 1:
            paquete = destino_dir / f"backup_completo_regen_{stamp}_{job.id[:8]}.tar.gz"
            with tarfile.open(paquete, "w:gz") as tar:
                for p in partes:
                    tar.add(p, arcname=p.name)
            for p in partes:
                p.unlink(missing_ok=True)
            return paquete
        return partes[0]
    except Exception:
        for p in partes:
            p.unlink(missing_ok=True)
        raise


# ── Rotación GFS ─────────────────────────────────────────────────────────────

def aplicar_retencion() -> int:
    """Borra artefactos expirados del BACKUP_DIR y limpia huérfanos. La fila
    de auditoría NUNCA se borra (rastro permanente); solo pierde su archivo."""
    db: Session = SessionLocal()
    eliminados = 0
    try:
        hoy = date.today()
        vencidos = db.query(BackupJob).filter(
            BackupJob.expira_en.isnot(None),
            BackupJob.expira_en < hoy,
            BackupJob.ubicacion.isnot(None),
        ).all()
        rutas_validas = set()
        for j in vencidos:
            try:
                Path(j.ubicacion).unlink(missing_ok=True)
                j.ubicacion = None
                eliminados += 1
            except Exception as e:
                logger.warning("No se pudo borrar %s: %s", j.ubicacion, e)
        # huérfanos: archivos en BACKUP_DIR sin fila viva que los referencie
        for j in db.query(BackupJob.ubicacion).filter(BackupJob.ubicacion.isnot(None)).all():
            rutas_validas.add(j.ubicacion)
        if BACKUP_DIR.exists():
            for f in BACKUP_DIR.iterdir():
                if f.is_file() and str(f) not in rutas_validas:
                    f.unlink(missing_ok=True)
        db.commit()
        logger.info("Rotación de backups: %d artefactos expirados eliminados", eliminados)
        return eliminados
    finally:
        db.close()


def ultimo_backup_archivos_ok(db: Session) -> datetime | None:
    """Fecha del último backup de archivos completado (para el incremental)."""
    row = (db.query(BackupJob.fecha_inicio)
           .filter(BackupJob.contenido.contains("cloudinary"),
                   BackupJob.estado == "completado")
           .order_by(BackupJob.fecha_inicio.desc()).first())
    return row.fecha_inicio if row else None
