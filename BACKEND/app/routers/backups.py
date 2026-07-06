"""
Router: /backups (módulo Backups · Gestión de TIC)

Restringido a rol Soporte (y TI / admin total). El backend es el gate real:
el frontend además oculta la pantalla con rolesGuard, pero un 403 aquí es lo
que protege los datos.

Diseño de descarga: el artefacto se STREAMEA desde BACKUP_DIR directo a la
máquina del usuario (FileResponse). No hay storage en la nube: la copia
durable de largo plazo es la que Soporte guarda en su disco externo. Si el
artefacto de un backup de BD ya no existe en disco (redeploy con BACKUP_DIR
efímero), se regenera al vuelo — un dump tarda segundos.
"""
from __future__ import annotations

import threading
import unicodedata
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pathlib import Path
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.rate_limit import verificar_limite
from app.core.security import verificar_token
from app.db.database import get_db
from app.models.backup_job import BackupJob
from app.models.usuario import Usuario
from app.services import backup_service
from app.services.audit_service import contexto_desde_payload, registrar_evento

router = APIRouter(prefix="/backups", tags=["backups"])


# ── Autorización: solo Soporte / TI / admin total ────────────────────────────

def _autorizar_soporte(payload: dict) -> None:
    if payload.get("admin_total"):
        return
    rol = (payload.get("rol") or "").strip().lower()
    rol = unicodedata.normalize("NFC", rol).replace("\xa0", " ")
    if rol in ("soporte", "ti", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Solo Soporte puede gestionar backups")


# ── Schemas ──────────────────────────────────────────────────────────────────

class CrearBackupBody(BaseModel):
    # "bd" → solo dump de BD (rápido, ~MB) | "completo" → BD + archivos Cloudinary
    alcance: str = "bd"


class ConfigBackupBody(BaseModel):
    """Programación editable de los backups automáticos (fila única backup_config)."""
    bdAuto:       bool = True
    bdFrecuencia: str  = "diario"     # cada_hora | diario | semanal
    bdHora:       str  = "23:30"      # HH:MM (hora local America/Lima)
    bdDiaSemana:  int  = 6            # 0=lunes … 6=domingo (solo semanal)
    bdCorreo:     bool = True
    archivosAuto: bool = True


class BackupJobOut(BaseModel):
    id:            str
    tipo:          str
    nivel:         str
    disparadoPorNombre: Optional[str] = None
    fechaInicio:   str
    fechaFin:      Optional[str] = None
    estado:        str
    contenido:     str
    tamanoBytes:   Optional[int] = None
    hashSha256:    Optional[str] = None
    errorDetalle:  Optional[str] = None
    retencion:     Optional[str] = None
    expiraEn:      Optional[str] = None
    descargable:   bool = False   # hay artefacto en disco O es regenerable (bd)
    duracionSegundos: Optional[float] = None
    nombreArchivo: Optional[str] = None  # nombre real del artefacto (extensión correcta)


class BackupsListOut(BaseModel):
    items: list[BackupJobOut]
    total: int
    page: int
    pageSize: int


def _out(db: Session, j: BackupJob) -> BackupJobOut:
    nombre = None
    if j.disparado_por:
        u = db.query(Usuario.nombre).filter(Usuario.id == j.disparado_por).first()
        nombre = u.nombre if u else None
    tiene_archivo = bool(j.ubicacion) and Path(j.ubicacion).exists()
    # Regenerable = las fuentes siguen existiendo: la BD siempre (dump nuevo) y
    # los paquetes de archivos si la corrida original empaquetó algo (se
    # reconstruyen desde Cloudinary con la misma ventana). Lo único NO
    # descargable es el incremental "sin novedades" (nunca hubo artefacto).
    regenerable = j.estado == "completado" and ("bd" in j.contenido or bool(j.tamano_bytes))
    dur = None
    if j.fecha_fin and j.fecha_inicio:
        dur = round((j.fecha_fin - j.fecha_inicio).total_seconds(), 1)
    return BackupJobOut(
        id=str(j.id), tipo=j.tipo, nivel=j.nivel,
        disparadoPorNombre=nombre or ("Sistema" if not j.disparado_por else None),
        fechaInicio=j.fecha_inicio.isoformat(),
        fechaFin=j.fecha_fin.isoformat() if j.fecha_fin else None,
        estado=j.estado, contenido=j.contenido,
        tamanoBytes=j.tamano_bytes, hashSha256=j.hash_sha256,
        errorDetalle=j.error_detalle, retencion=j.retencion,
        expiraEn=j.expira_en.isoformat() if j.expira_en else None,
        descargable=(j.estado == "completado" and (tiene_archivo or regenerable)),
        duracionSegundos=dur,
        nombreArchivo=Path(j.ubicacion).name if j.ubicacion else None,
    )


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("", response_model=BackupJobOut, status_code=202)
def disparar_backup_manual(
    body:    CrearBackupBody,
    request: Request,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Dispara un backup manual en un hilo de fondo y responde al instante
    con el job (estado pendiente/en_proceso). El frontend hace polling."""
    _autorizar_soporte(payload)

    if body.alcance not in ("bd", "completo"):
        raise HTTPException(status_code=422, detail="alcance debe ser 'bd' o 'completo'")

    # No apilar backups manuales simultáneos
    activo = db.query(BackupJob.id).filter(
        BackupJob.tipo == "manual",
        BackupJob.estado.in_(("pendiente", "en_proceso")),
    ).first()
    if activo:
        raise HTTPException(status_code=409, detail="Ya hay un backup manual en proceso")

    contenido = "bd" if body.alcance == "bd" else "bd,pdfs,cloudinary"
    job = backup_service.crear_job(
        db, tipo="manual",
        nivel="bd_diario" if body.alcance == "bd" else "archivos_full",
        contenido=contenido, disparado_por=payload.get("id"), retencion="diario",
    )
    threading.Thread(
        target=backup_service.ejecutar_backup,
        args=(job.id,), kwargs={"notificar": True},
        daemon=True, name=f"backup-manual-{job.id[:8]}",
    ).start()

    registrar_evento(
        accion="BACKUP", entidad="backup_job", entidad_id=str(job.id),
        detalle={"alcance": body.alcance, "contenido": contenido},
        **contexto_desde_payload(payload, request),
    )
    return _out(db, job)


@router.get("", response_model=BackupsListOut)
def listar_backups(
    estado:   str = Query("todos"),
    page:     int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    _autorizar_soporte(payload)
    base = db.query(BackupJob)
    if estado and estado != "todos":
        base = base.filter(BackupJob.estado == estado)
    total = base.count()
    rows = (base.order_by(BackupJob.fecha_inicio.desc())
            .offset((page - 1) * page_size).limit(page_size).all())
    return BackupsListOut(items=[_out(db, j) for j in rows],
                          total=total, page=page, pageSize=page_size)


def _config_out(cfg) -> dict:
    return {
        "bdAuto": cfg.bd_auto, "bdFrecuencia": cfg.bd_frecuencia,
        "bdHora": cfg.bd_hora, "bdDiaSemana": cfg.bd_dia_semana,
        "bdCorreo": cfg.bd_correo, "archivosAuto": cfg.archivos_auto,
        "resumen": backup_service.resumen_config(cfg),
        "backupDir": str(backup_service.BACKUP_DIR),
        "retencionDias": backup_service.RETENCION_DIAS,
    }


@router.get("/config")
def config_backups(payload: dict = Depends(verificar_token),
                   db: Session = Depends(get_db)):
    """Programación vigente + valores editables (pantalla de configuración)."""
    _autorizar_soporte(payload)
    return _config_out(backup_service.obtener_config(db))


@router.put("/config")
def actualizar_config_backups(
    body:    ConfigBackupBody,
    request: Request,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Guarda la programación. El scheduler la relee en cada tick, así que el
    cambio aplica al minuto sin reiniciar el servidor."""
    _autorizar_soporte(payload)
    if body.bdFrecuencia not in ("cada_hora", "diario", "semanal"):
        raise HTTPException(status_code=422, detail="bdFrecuencia debe ser cada_hora, diario o semanal")
    try:
        hh, mm = body.bdHora.split(":")
        assert 0 <= int(hh) <= 23 and 0 <= int(mm) <= 59
    except (ValueError, AssertionError):
        raise HTTPException(status_code=422, detail="bdHora debe tener formato HH:MM")
    if not 0 <= body.bdDiaSemana <= 6:
        raise HTTPException(status_code=422, detail="bdDiaSemana debe estar entre 0 (lunes) y 6 (domingo)")

    cfg = backup_service.obtener_config(db)
    cfg.bd_auto        = body.bdAuto
    cfg.bd_frecuencia  = body.bdFrecuencia
    cfg.bd_hora        = f"{int(hh):02d}:{int(mm):02d}"
    cfg.bd_dia_semana  = body.bdDiaSemana
    cfg.bd_correo      = body.bdCorreo
    cfg.archivos_auto  = body.archivosAuto
    cfg.actualizado_por = payload.get("id")
    cfg.actualizado_en  = datetime.utcnow()
    db.commit()
    db.refresh(cfg)

    registrar_evento(
        accion="SECURITY", entidad="backup_config", entidad_id="1",
        detalle={"configNueva": body.dict()},
        **contexto_desde_payload(payload, request),
    )
    return _config_out(cfg)


@router.post("/{job_id}/cancelar", response_model=BackupJobOut)
def cancelar_backup(
    job_id:  str,
    request: Request,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Cancela un backup pendiente o en proceso. Cancelación cooperativa: el
    worker chequea la bandera entre fases/archivos y, si hay un pg_dump
    corriendo, se le hace terminate. El job queda en estado 'cancelado'."""
    _autorizar_soporte(payload)
    j = db.query(BackupJob).filter(BackupJob.id == job_id).first()
    if not j:
        raise HTTPException(status_code=404, detail="Backup no encontrado")
    if j.estado not in ("pendiente", "en_proceso"):
        raise HTTPException(status_code=409, detail=f"El backup ya está {j.estado}, no se puede cancelar")

    backup_service.solicitar_cancelacion(job_id)
    if j.estado == "pendiente":
        # aún no arrancó: se marca directo (el worker lo respeta al despertar)
        j.estado = "cancelado"
        j.fecha_fin = datetime.utcnow()
        db.commit()

    registrar_evento(
        accion="BACKUP", entidad="backup_job", entidad_id=str(j.id),
        detalle={"cancelado": True, "estadoPrevio": j.estado},
        **contexto_desde_payload(payload, request),
    )
    return _out(db, j)


@router.get("/{job_id}", response_model=BackupJobOut)
def estado_backup(
    job_id:  str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Polling de estado de un job."""
    _autorizar_soporte(payload)
    j = db.query(BackupJob).filter(BackupJob.id == job_id).first()
    if not j:
        raise HTTPException(status_code=404, detail="Backup no encontrado")
    return _out(db, j)


@router.get("/{job_id}/descargar")
def descargar_backup(
    job_id:  str,
    request: Request,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Streamea el artefacto a la máquina del usuario. Si era solo-BD y el
    archivo ya no está (disco efímero tras redeploy), se regenera al vuelo."""
    _autorizar_soporte(payload)

    # Rate limit por usuario: 10 descargas/min (en memoria)
    if not verificar_limite(f"backup_dl:{payload.get('id')}", 10, 60):
        registrar_evento(
            accion="RATE_LIMITED", resultado="denegado",
            entidad="backup_job", entidad_id=job_id,
            **contexto_desde_payload(payload, request),
        )
        raise HTTPException(status_code=429,
                            detail="Demasiadas descargas de backups. Espera un minuto.")

    j = db.query(BackupJob).filter(BackupJob.id == job_id).first()
    if not j:
        raise HTTPException(status_code=404, detail="Backup no encontrado")
    if j.estado != "completado":
        raise HTTPException(status_code=409, detail=f"El backup está {j.estado}")

    ruta = Path(j.ubicacion) if j.ubicacion else None
    if not ruta or not ruta.exists():
        # Regeneración al vuelo para CUALQUIER tipo (bd, archivos, completo):
        # la BD con un dump nuevo y los archivos reempaquetando desde Cloudinary
        # la misma ventana del job original. Solo el incremental "sin novedades"
        # es irrecuperable (nunca produjo artefacto) → 410.
        try:
            destino = backup_service.regenerar_artefacto(db, j)
        except RuntimeError as e:
            raise HTTPException(status_code=410, detail=f"No hay nada que descargar: {e}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"No se pudo regenerar el backup: {e}")
        j.ubicacion    = str(destino)
        j.tamano_bytes = destino.stat().st_size
        j.hash_sha256  = backup_service._sha256(destino)
        db.commit()
        ruta = destino

    registrar_evento(
        accion="DOWNLOAD", entidad="backup_job", entidad_id=str(job_id),
        detalle={"archivo": ruta.name, "tamanoBytes": j.tamano_bytes},
        **contexto_desde_payload(payload, request),
    )
    return FileResponse(
        path=str(ruta),
        filename=ruta.name,
        media_type="application/octet-stream",
        headers={"X-Backup-Sha256": j.hash_sha256 or ""},
    )
