from __future__ import annotations

import uuid as _uuid_mod
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token, es_superadmin
from ..core.tz import fmt_lima
from ..db.database import get_db
from ..models.auditoria import Auditoria
from ..models.usuario import Usuario
from ..models.usuario_rol import UsuarioRol
from ..models.rol_permiso import RolPermiso
from ..models.permiso import Permiso


def _to_uuid(val: str | None) -> _uuid_mod.UUID | None:
    """Convierte string a uuid.UUID para filtros — evita 'uuid = varchar' en PostgreSQL."""
    if not val:
        return None
    try:
        return _uuid_mod.UUID(str(val))
    except (ValueError, AttributeError):
        return None

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
    if es_superadmin(payload):
        return

    usuario_id = payload.get("id")
    tiene = (
        db.query(Permiso)
        .join(RolPermiso, RolPermiso.permiso_id == Permiso.id)
        .join(UsuarioRol, UsuarioRol.rol_id == RolPermiso.rol_id)
        .filter(
            UsuarioRol.usuario_id == usuario_id,
            Permiso.modulo == "AUDITORIA",
        Permiso.accion == "VER",
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
    empresa_id = payload.get("empresa_id")

    # Castear a uuid.UUID para que psycopg2 use el adaptador correcto
    # (las columnas en BD son tipo uuid nativo, no varchar)
    emp_uuid = _to_uuid(empresa_id)
    if emp_uuid is None:
        return []

    query = db.query(Auditoria).filter(Auditoria.empresa_id == emp_uuid)

    if modulo:
        query = query.filter(Auditoria.modulo.ilike(f"%{modulo}%"))
    if accion:
        query = query.filter(Auditoria.accion.ilike(f"%{accion}%"))
    if usuario_id:
        uid = _to_uuid(usuario_id)
        if uid:
            query = query.filter(Auditoria.usuario_id == uid)
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

    # usuario_id devuelto por psycopg2 puede ser uuid.UUID — normalizar a str
    uid_set = {str(a.usuario_id) for a in auditorias if a.usuario_id}
    usuarios_map: dict[str, str] = {}
    if uid_set:
        uid_uuids = [_to_uuid(u) for u in uid_set if _to_uuid(u)]
        rows = db.query(Usuario).filter(Usuario.id.in_(uid_uuids)).all()
        usuarios_map = {str(u.id): f"{u.nombre} {u.apellido}".strip() for u in rows}

    return [
        AuditoriaOut(
            id=str(a.id),
            usuario_id=str(a.usuario_id) if a.usuario_id else None,
            usuario_nombre=usuarios_map.get(str(a.usuario_id) if a.usuario_id else "", None),
            tabla_afectada=str(a.tabla_afectada),
            registro_id=str(a.registro_id) if a.registro_id else None,
            accion=str(a.accion),
            modulo=str(a.modulo) if a.modulo else None,
            descripcion=str(a.descripcion) if a.descripcion else None,
            ip=str(a.ip) if a.ip else None,
            fecha=fmt_lima(a.fecha, "%d/%m/%Y %H:%M:%S"),
        )
        for a in auditorias
    ]
