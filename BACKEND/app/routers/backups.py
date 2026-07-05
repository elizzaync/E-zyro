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

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from pathlib import Path
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.security import verificar_token
from app.db.database import get_db
from app.models.backup_job import BackupJob
from app.models.usuario import Usuario
from app.services import backup_service

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
    regenerable = j.estado == "completado" and j.contenido == "bd"
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
    )


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("", response_model=BackupJobOut, status_code=202)
def disparar_backup_manual(
    body:    CrearBackupBody,
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


@router.get("/config")
def config_backups(payload: dict = Depends(verificar_token)):
    """Frecuencia y retención vigentes (para la sección de configuración)."""
    _autorizar_soporte(payload)
    return {"config": backup_service.CONFIG_VIGENTE,
            "backupDir": str(backup_service.BACKUP_DIR),
            "retencionDias": backup_service.RETENCION_DIAS}


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
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Streamea el artefacto a la máquina del usuario. Si era solo-BD y el
    archivo ya no está (disco efímero tras redeploy), se regenera al vuelo."""
    _autorizar_soporte(payload)
    j = db.query(BackupJob).filter(BackupJob.id == job_id).first()
    if not j:
        raise HTTPException(status_code=404, detail="Backup no encontrado")
    if j.estado != "completado":
        raise HTTPException(status_code=409, detail=f"El backup está {j.estado}")

    ruta = Path(j.ubicacion) if j.ubicacion else None
    if not ruta or not ruta.exists():
        if j.contenido != "bd":
            raise HTTPException(
                status_code=410,
                detail="El artefacto ya no está en el servidor (redeploy). Genera un backup nuevo.",
            )
        # Regeneración al vuelo: un dump tarda segundos
        destino = backup_service._ensure_dir() / f"bd_regen_{datetime.now():%Y%m%d_%H%M%S}_{j.id[:8]}.dump"
        try:
            backup_service._dump_bd(destino)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"No se pudo regenerar el dump: {e}")
        j.ubicacion    = str(destino)
        j.tamano_bytes = destino.stat().st_size
        j.hash_sha256  = backup_service._sha256(destino)
        db.commit()
        ruta = destino

    return FileResponse(
        path=str(ruta),
        filename=ruta.name,
        media_type="application/octet-stream",
        headers={"X-Backup-Sha256": j.hash_sha256 or ""},
    )
