from __future__ import annotations

import uuid as _uuid_mod
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token, es_superadmin
from ..core.tz import fmt_lima
from ..db.database import get_db
from ..models.auditoria import Auditoria
from ..models.empresa import Empresa
from ..models.log_sistema import LogSistema
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
    user_agent: Optional[str] = None
    fecha: str
    datos_anteriores: Optional[Dict[str, Any]] = None
    datos_nuevos: Optional[Dict[str, Any]] = None


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
    modulo: Optional[str]          = Query(None),
    accion: Optional[str]          = Query(None),
    tabla_afectada: Optional[str]  = Query(None, description="Filtrar por tabla afectada (ej: proyecto_servicio)"),
    q: Optional[str]               = Query(None, description="Búsqueda en descripción"),
    fecha_desde: Optional[str]     = Query(None),
    fecha_hasta: Optional[str]     = Query(None),
    usuario_id: Optional[str]      = Query(None),
    buscar_usuario: Optional[str]  = Query(None, description="Buscar por nombre/apellido del actor"),
    page: int                      = Query(1, ge=1),
    page_size: int                 = Query(50, ge=1, le=100),
    payload: dict                  = Depends(verificar_token),
    db: Session                    = Depends(get_db),
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
    if tabla_afectada:
        query = query.filter(Auditoria.tabla_afectada.ilike(f"%{tabla_afectada}%"))
    if q:
        query = query.filter(Auditoria.descripcion.ilike(f"%{q}%"))
    if usuario_id:
        uid = _to_uuid(usuario_id)
        if uid:
            query = query.filter(Auditoria.usuario_id == uid)
    if buscar_usuario and buscar_usuario.strip():
        term = f"%{buscar_usuario.strip()}%"
        ids = [
            row[0]
            for row in db.query(Usuario.id)
            .filter(
                Usuario.empresa_id == emp_uuid,
                (Usuario.nombre.ilike(term)) | (Usuario.apellido.ilike(term)),
            )
            .all()
        ]
        if not ids:
            return []
        query = query.filter(Auditoria.usuario_id.in_(ids))
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
            user_agent=str(a.user_agent) if a.user_agent else None,
            fecha=fmt_lima(a.fecha, "%d/%m/%Y %H:%M:%S"),
            datos_anteriores=a.datos_anteriores,
            datos_nuevos=a.datos_nuevos,
        )
        for a in auditorias
    ]


# ── POST /auditoria/{id}/revertir ─────────────────────────────────────────────

from sqlalchemy import text as _sql_text

@router.post("/{auditoria_id}/revertir")
def revertir_registro(
    auditoria_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """
    Revierte un registro a su estado anterior (datos_anteriores) usando un UPDATE raw
    sobre la tabla afectada. Solo disponible si el registro tiene datos_anteriores y registro_id.
    Requiere permiso AUDITORIA:VER + rol admin/superadmin.
    """
    _verificar_permiso_auditoria(payload, db)

    rol = (payload.get("rol") or "").lower()
    if rol not in ("administrador", "admin", "superadmin"):
        raise HTTPException(status_code=403, detail="Solo administradores pueden revertir cambios")

    emp_uuid = _to_uuid(payload.get("empresa_id"))
    aud_uuid = _to_uuid(auditoria_id)
    if not aud_uuid or not emp_uuid:
        raise HTTPException(status_code=400, detail="ID inválido")

    registro = db.query(Auditoria).filter(
        Auditoria.id == aud_uuid,
        Auditoria.empresa_id == emp_uuid,
    ).first()
    if not registro:
        raise HTTPException(status_code=404, detail="Registro de auditoría no encontrado")
    if not registro.datos_anteriores:
        raise HTTPException(status_code=422, detail="Este registro no tiene datos anteriores para revertir")
    if not registro.registro_id:
        raise HTTPException(status_code=422, detail="No se puede revertir: no hay registro_id")
    if registro.accion.upper() in ("ELIMINAR", "DELETE"):
        raise HTTPException(status_code=422, detail="No se puede revertir una eliminación automáticamente")

    tabla = str(registro.tabla_afectada)
    datos = registro.datos_anteriores
    reg_id = str(registro.registro_id)

    # Construir SET clause solo con campos presentes en datos_anteriores
    # Excluir campos que nunca deben sobreescribirse
    CAMPOS_EXCLUIDOS = {"id", "empresa_id", "created_at", "updated_at"}
    campos = {k: v for k, v in datos.items() if k not in CAMPOS_EXCLUIDOS}
    if not campos:
        raise HTTPException(status_code=422, detail="No hay campos válidos para revertir")

    set_parts = ", ".join([f'"{k}" = :{k}' for k in campos.keys()])
    params = {**campos, "_reg_id": reg_id}

    try:
        db.execute(
            _sql_text(f'UPDATE "{tabla}" SET {set_parts} WHERE id = :_reg_id'),
            params,
        )
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error al revertir: {str(e)}")

    return {"detail": f"Registro revertido correctamente en tabla '{tabla}'."}


# ══════════════════════════════════════════════════════════════════════════════
# Auditoría General — SOLO SuperAdmin (cross-empresa + logs de sistema + stats)
# ══════════════════════════════════════════════════════════════════════════════

def _exigir_superadmin(payload: dict) -> None:
    """Solo el rol SuperAdmin (no Admin/Administrador) accede a la vista global."""
    rol = (payload.get("rol") or "").lower().strip().replace(" ", "")
    if rol != "superadmin":
        raise HTTPException(status_code=403, detail="Solo SuperAdmin puede ver la Auditoría General")


class AuditoriaGeneralOut(BaseModel):
    id: str
    empresa_id: Optional[str]
    empresa_nombre: Optional[str]
    usuario_id: Optional[str]
    usuario_nombre: Optional[str]
    tabla_afectada: str
    registro_id: Optional[str]
    accion: str
    modulo: Optional[str]
    descripcion: Optional[str]
    ip: Optional[str]
    fecha: str
    datos_anteriores: Optional[Dict[str, Any]] = None
    datos_nuevos: Optional[Dict[str, Any]] = None


class LogSistemaOut(BaseModel):
    id: str
    empresa_id: Optional[str]
    usuario_id: Optional[str]
    nivel: str
    origen: Optional[str]
    mensaje: str
    detalle: Optional[str]
    metodo: Optional[str]
    status_code: Optional[int]
    fecha: str


def _parse_fecha(valor: Optional[str]) -> Optional[datetime]:
    if not valor:
        return None
    try:
        return datetime.strptime(valor, "%Y-%m-%d")
    except ValueError:
        return None


# ── GET /auditoria/general ─────────────────────────────────────────────────────

@router.get("/general", response_model=List[AuditoriaGeneralOut])
def listar_auditoria_general(
    empresa_id: Optional[str] = Query(None),
    usuario_id: Optional[str] = Query(None),
    modulo: Optional[str]     = Query(None),
    accion: Optional[str]     = Query(None),
    desde: Optional[str]      = Query(None, description="YYYY-MM-DD"),
    hasta: Optional[str]      = Query(None, description="YYYY-MM-DD"),
    q: Optional[str]          = Query(None, description="Búsqueda en descripción"),
    limit: int                = Query(50, ge=1, le=200),
    offset: int               = Query(0, ge=0),
    payload: dict             = Depends(verificar_token),
    db: Session               = Depends(get_db),
):
    _exigir_superadmin(payload)

    query = db.query(Auditoria)  # cross-empresa: SIN filtro empresa_id por defecto

    if empresa_id:
        emp = _to_uuid(empresa_id)
        if emp:
            query = query.filter(Auditoria.empresa_id == emp)
    if usuario_id:
        uid = _to_uuid(usuario_id)
        if uid:
            query = query.filter(Auditoria.usuario_id == uid)
    if modulo:
        query = query.filter(Auditoria.modulo.ilike(f"%{modulo}%"))
    if accion:
        query = query.filter(Auditoria.accion.ilike(f"%{accion}%"))
    if q:
        query = query.filter(Auditoria.descripcion.ilike(f"%{q}%"))
    f_desde = _parse_fecha(desde)
    if f_desde:
        query = query.filter(Auditoria.fecha >= f_desde)
    f_hasta = _parse_fecha(hasta)
    if f_hasta:
        query = query.filter(Auditoria.fecha < f_hasta + timedelta(days=1))

    auditorias = (
        query.order_by(Auditoria.fecha.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    # Joins manuales (mapas) — usuario y empresa pueden venir como uuid.UUID
    uid_set = {str(a.usuario_id) for a in auditorias if a.usuario_id}
    usuarios_map: dict[str, str] = {}
    if uid_set:
        uid_uuids = [_to_uuid(u) for u in uid_set if _to_uuid(u)]
        rows = db.query(Usuario).filter(Usuario.id.in_(uid_uuids)).all()
        usuarios_map = {str(u.id): f"{u.nombre} {u.apellido}".strip() for u in rows}

    emp_set = {str(a.empresa_id) for a in auditorias if a.empresa_id}
    empresas_map: dict[str, str] = {}
    if emp_set:
        emp_uuids = [_to_uuid(e) for e in emp_set if _to_uuid(e)]
        rows_e = db.query(Empresa).filter(Empresa.id.in_(emp_uuids)).all()
        empresas_map = {str(e.id): str(e.razon_social or "") for e in rows_e}

    return [
        AuditoriaGeneralOut(
            id=str(a.id),
            empresa_id=str(a.empresa_id) if a.empresa_id else None,
            empresa_nombre=empresas_map.get(str(a.empresa_id) if a.empresa_id else "", None),
            usuario_id=str(a.usuario_id) if a.usuario_id else None,
            usuario_nombre=usuarios_map.get(str(a.usuario_id) if a.usuario_id else "", None),
            tabla_afectada=str(a.tabla_afectada),
            registro_id=str(a.registro_id) if a.registro_id else None,
            accion=str(a.accion),
            modulo=str(a.modulo) if a.modulo else None,
            descripcion=str(a.descripcion) if a.descripcion else None,
            ip=str(a.ip) if a.ip else None,
            fecha=fmt_lima(a.fecha, "%d/%m/%Y %H:%M:%S"),
            datos_anteriores=a.datos_anteriores,
            datos_nuevos=a.datos_nuevos,
        )
        for a in auditorias
    ]


# ── GET /auditoria/logs ────────────────────────────────────────────────────────

@router.get("/logs", response_model=List[LogSistemaOut])
def listar_logs_sistema(
    nivel: Optional[str] = Query(None, description="info | warning | error"),
    desde: Optional[str] = Query(None, description="YYYY-MM-DD"),
    hasta: Optional[str] = Query(None, description="YYYY-MM-DD"),
    limit: int           = Query(50, ge=1, le=200),
    offset: int          = Query(0, ge=0),
    payload: dict        = Depends(verificar_token),
    db: Session          = Depends(get_db),
):
    _exigir_superadmin(payload)

    query = db.query(LogSistema)
    if nivel:
        query = query.filter(LogSistema.nivel == nivel.lower().strip())
    f_desde = _parse_fecha(desde)
    if f_desde:
        query = query.filter(LogSistema.fecha >= f_desde)
    f_hasta = _parse_fecha(hasta)
    if f_hasta:
        query = query.filter(LogSistema.fecha < f_hasta + timedelta(days=1))

    logs = (
        query.order_by(LogSistema.fecha.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    return [
        LogSistemaOut(
            id=str(lg.id),
            empresa_id=str(lg.empresa_id) if lg.empresa_id else None,
            usuario_id=str(lg.usuario_id) if lg.usuario_id else None,
            nivel=str(lg.nivel),
            origen=str(lg.origen) if lg.origen else None,
            mensaje=str(lg.mensaje),
            detalle=str(lg.detalle) if lg.detalle else None,
            metodo=str(lg.metodo) if lg.metodo else None,
            status_code=lg.status_code,
            fecha=fmt_lima(lg.fecha, "%d/%m/%Y %H:%M:%S"),
        )
        for lg in logs
    ]


# ── GET /auditoria/stats ───────────────────────────────────────────────────────

@router.get("/stats")
def estadisticas_auditoria(
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    """Conteos de los últimos 30 días: por módulo (top 10), por acción,
    serie por día y errores del sistema por nivel."""
    _exigir_superadmin(payload)

    corte = datetime.utcnow() - timedelta(days=30)

    total_acciones = (
        db.query(func.count(Auditoria.id))
        .filter(Auditoria.fecha >= corte)
        .scalar()
        or 0
    )

    por_modulo = (
        db.query(Auditoria.modulo, func.count(Auditoria.id))
        .filter(Auditoria.fecha >= corte)
        .group_by(Auditoria.modulo)
        .order_by(func.count(Auditoria.id).desc())
        .limit(10)
        .all()
    )

    por_accion = (
        db.query(Auditoria.accion, func.count(Auditoria.id))
        .filter(Auditoria.fecha >= corte)
        .group_by(Auditoria.accion)
        .order_by(func.count(Auditoria.id).desc())
        .all()
    )

    por_dia = (
        db.query(func.date(Auditoria.fecha), func.count(Auditoria.id))
        .filter(Auditoria.fecha >= corte)
        .group_by(func.date(Auditoria.fecha))
        .order_by(func.date(Auditoria.fecha))
        .all()
    )

    errores_por_nivel = (
        db.query(LogSistema.nivel, func.count(LogSistema.id))
        .filter(LogSistema.fecha >= corte)
        .group_by(LogSistema.nivel)
        .all()
    )
    total_errores = sum(int(c or 0) for _, c in errores_por_nivel)

    return {
        "rango_dias": 30,
        "total_acciones": int(total_acciones),
        "por_modulo": [
            {"nombre": str(m) if m else "(sin módulo)", "cantidad": int(c)}
            for m, c in por_modulo
        ],
        "por_accion": [
            {"nombre": str(a) if a else "(sin acción)", "cantidad": int(c)}
            for a, c in por_accion
        ],
        "por_dia": [
            {"fecha": str(d), "cantidad": int(c)}
            for d, c in por_dia
        ],
        "total_errores": total_errores,
        "errores_por_nivel": [
            {"nivel": str(n) if n else "error", "cantidad": int(c)}
            for n, c in errores_por_nivel
        ],
    }
