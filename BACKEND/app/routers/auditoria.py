from __future__ import annotations

from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..models.auditoria import Auditoria
from ..models.usuario import Usuario
from ..models.usuario_rol import UsuarioRol
from ..models.rol_permiso import RolPermiso
from ..models.permiso import Permiso

router = APIRouter(prefix="/auditoria", tags=["auditoria"])


# ── Schema ─────────────────────────────────────────────────────────────────────

class AuditoriaOut(BaseModel):
    id: str
    usuario_id: Optional[str]
    usuario_nombre: Optional[str]
    tabla_afectada: str
    registro_id: Optional[str]
    accion: str
    modulo: Optional[str]
    descripcion: Optional[str]
    ip: Optional[str]
    fecha: str


# ── Helper: verificar permiso ver-auditorias ───────────────────────────────────

def _verificar_permiso_auditoria(payload: dict, db: Session) -> None:
    rol = (payload.get("rol") or "").lower()
    if rol in ("admin", "administrador", "superadmin"):
        return

    usuario_id = payload.get("id")
    tiene = (
        db.query(Permiso)
        .join(RolPermiso, RolPermiso.permiso_id == Permiso.id)
        .join(UsuarioRol, UsuarioRol.rol_id == RolPermiso.rol_id)
        .filter(
            UsuarioRol.usuario_id == usuario_id,
            Permiso.accion == "ver-auditorias",
        )
        .first()
    )
    if not tiene:
        raise HTTPException(status_code=403, detail="Sin permiso para ver el registro de auditoría")


# ── GET /auditoria ─────────────────────────────────────────────────────────────

@router.get("", response_model=List[AuditoriaOut])
def listar_auditoria(
    modulo: Optional[str]      = Query(None),
    accion: Optional[str]      = Query(None),
    fecha_desde: Optional[str] = Query(None),
    fecha_hasta: Optional[str] = Query(None),
    usuario_id: Optional[str]  = Query(None),
    page: int                  = Query(1, ge=1),
    page_size: int             = Query(50, ge=1, le=100),
    payload: dict              = Depends(verificar_token),
    db: Session                = Depends(get_db),
):
    _verificar_permiso_auditoria(payload, db)
    empresa_id = payload["empresa_id"]

    query = db.query(Auditoria).filter(Auditoria.empresa_id == empresa_id)

    if modulo:
        query = query.filter(Auditoria.modulo.ilike(f"%{modulo}%"))
    if accion:
        query = query.filter(Auditoria.accion.ilike(f"%{accion}%"))
    if usuario_id:
        query = query.filter(Auditoria.usuario_id == usuario_id)
    if fecha_desde:
        try:
            query = query.filter(Auditoria.fecha >= datetime.strptime(fecha_desde, "%Y-%m-%d"))
        except ValueError:
            pass
    if fecha_hasta:
        try:
            query = query.filter(
                Auditoria.fecha < datetime.strptime(fecha_hasta, "%Y-%m-%d") + timedelta(days=1)
            )
        except ValueError:
            pass

    total_offset = (page - 1) * page_size
    auditorias = (
        query.order_by(Auditoria.fecha.desc())
        .offset(total_offset)
        .limit(page_size)
        .all()
    )

    uid_set = {a.usuario_id for a in auditorias if a.usuario_id}
    usuarios_map: dict[str, str] = {}
    if uid_set:
        rows = db.query(Usuario).filter(Usuario.id.in_(uid_set)).all()
        usuarios_map = {str(u.id): f"{u.nombre} {u.apellido}".strip() for u in rows}

    return [
        AuditoriaOut(
            id=str(a.id),
            usuario_id=a.usuario_id,
            usuario_nombre=usuarios_map.get(a.usuario_id or "", None),
            tabla_afectada=a.tabla_afectada,
            registro_id=a.registro_id,
            accion=a.accion,
            modulo=a.modulo,
            descripcion=a.descripcion,
            ip=a.ip,
            fecha=a.fecha.strftime("%d/%m/%Y %H:%M:%S") if a.fecha else "",
        )
        for a in auditorias
    ]
