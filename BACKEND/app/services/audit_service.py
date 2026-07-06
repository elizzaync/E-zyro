"""
Servicio de eventos de auditoría HTTP/seguridad (tabla audit_log).

Best-effort SIEMPRE: `registrar_evento` nunca lanza — un fallo de auditoría
jamás rompe la operación de negocio (misma filosofía que audit_listener.py).

Los CRUD de datos ya los captura el listener ORM sobre `auditoria`; aquí van
los eventos que el ORM no ve: LOGIN, LOGIN_FALLIDO, LOGOUT, DOWNLOAD, EXPORT,
PERMISSION_DENIED, RATE_LIMITED, BACKUP, SECURITY, VIEW_SENSITIVE.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta
from typing import Any, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.models.audit_log import AuditLog

logger = logging.getLogger("audit_eventos")

# Claves que JAMÁS se persisten en `detalle` (subcadenas, case-insensitive):
# password, token, otp, firma_base64 y cualquier *base64* quedan filtradas.
_CLAVES_SENSIBLES = ("password", "token", "otp", "base64", "secret", "contrasena", "contraseña")

# Largos de columna para truncado defensivo (mismos que la migración).
_LARGOS = {
    "usuario_id": 36, "usuario_nombre": 150, "rol": 50, "empresa_id": 36,
    "accion": 30, "entidad": 60, "entidad_id": 64, "metodo_http": 8,
    "ruta": 300, "ip": 45, "user_agent": 255, "resultado": 10,
}


def _trunc(valor: Any, campo: str) -> Optional[str]:
    if valor is None:
        return None
    return str(valor)[: _LARGOS[campo]]


def filtrar_sensibles(valor: Any, _prof: int = 0) -> Any:
    """Elimina recursivamente claves sensibles y acota tamaños del detalle."""
    if _prof > 6:
        return None
    if isinstance(valor, dict):
        return {
            k: filtrar_sensibles(v, _prof + 1)
            for k, v in valor.items()
            if not any(s in str(k).lower() for s in _CLAVES_SENSIBLES)
        }
    if isinstance(valor, (list, tuple)):
        return [filtrar_sensibles(v, _prof + 1) for v in list(valor)[:50]]
    if isinstance(valor, str):
        return valor[:2000]
    if isinstance(valor, (int, float, bool)) or valor is None:
        return valor
    return str(valor)[:500]


def registrar_evento(*, accion: str, resultado: str = "exito",
                     usuario_id=None, usuario_nombre=None, rol=None,
                     empresa_id=None, entidad=None, entidad_id=None,
                     metodo_http=None, ruta=None, ip=None, user_agent=None,
                     detalle: dict | None = None, db: Session | None = None) -> None:
    """Inserta un evento en audit_log. Nunca lanza; si `db` es None usa una
    sesión propia (SessionLocal) con commit propio. Si `db` viene, hace commit
    sobre esa sesión (los llamadores lo invocan al final de su operación)."""
    try:
        fila = AuditLog(
            id=str(uuid.uuid4()),
            fecha=datetime.utcnow(),
            usuario_id=_trunc(usuario_id, "usuario_id"),
            usuario_nombre=_trunc(usuario_nombre, "usuario_nombre"),
            rol=_trunc(rol, "rol"),
            empresa_id=_trunc(empresa_id, "empresa_id"),
            accion=_trunc(accion, "accion"),
            entidad=_trunc(entidad, "entidad"),
            entidad_id=_trunc(entidad_id, "entidad_id"),
            metodo_http=_trunc(metodo_http, "metodo_http"),
            ruta=_trunc(ruta, "ruta"),
            ip=_trunc(ip, "ip"),
            user_agent=_trunc(user_agent, "user_agent"),
            resultado=_trunc(resultado, "resultado") or "exito",
            detalle=filtrar_sensibles(detalle) if detalle else None,
        )
        if db is not None:
            db.add(fila)
            db.commit()
        else:
            sesion = SessionLocal()
            try:
                sesion.add(fila)
                sesion.commit()
            finally:
                sesion.close()
    except Exception as e:  # noqa: BLE001 — auditoría silenciosa
        try:
            if db is not None:
                db.rollback()
        except Exception:
            pass
        logger.warning("registrar_evento(%s) falló: %s", accion, e)


def contexto_desde_payload(payload: dict | None, request) -> dict:
    """Arma los kwargs de contexto (usuario/rol/ip/user_agent/ruta/método)
    desde el payload JWT y el Request. IP real = primer salto de
    X-Forwarded-For (mismo criterio que audit_context.py)."""
    payload = payload or {}
    ip = None
    user_agent = None
    metodo = None
    ruta = None
    if request is not None:
        try:
            fwd = request.headers.get("X-Forwarded-For", "")
            ip = (fwd.split(",")[0].strip() if fwd
                  else (request.client.host if request.client else None))
            user_agent = request.headers.get("User-Agent")
            metodo = request.method
            ruta = str(request.url.path)
        except Exception:
            pass
    return {
        "usuario_id": payload.get("id"),
        "usuario_nombre": payload.get("sub"),
        "rol": payload.get("rol"),
        "empresa_id": payload.get("empresa_id"),
        "ip": ip,
        "user_agent": user_agent,
        "metodo_http": metodo,
        "ruta": ruta,
    }


# ── Consulta compartida (routers /seguridad-tic/eventos y /audit-log) ─────────

def consultar_eventos(db: Session, *, accion: str | None = None,
                      usuario_nombre: str | None = None, ip: str | None = None,
                      desde: str | None = None, hasta: str | None = None,
                      resultado: str | None = None,
                      page: int = 1, page_size: int = 25,
                      paginar: bool = True):
    """Aplica los filtros del contrato y devuelve (filas, total)."""
    q = db.query(AuditLog)
    if accion and accion != "todas":
        q = q.filter(AuditLog.accion == accion)
    if usuario_nombre:
        q = q.filter(AuditLog.usuario_nombre.ilike(f"%{usuario_nombre}%"))
    if ip:
        q = q.filter(AuditLog.ip.ilike(f"%{ip}%"))
    if resultado and resultado != "todos":
        q = q.filter(AuditLog.resultado == resultado)
    if desde:
        try:
            q = q.filter(AuditLog.fecha >= datetime.strptime(desde, "%Y-%m-%d"))
        except ValueError:
            pass
    if hasta:
        try:
            q = q.filter(AuditLog.fecha < datetime.strptime(hasta, "%Y-%m-%d") + timedelta(days=1))
        except ValueError:
            pass
    total = q.with_entities(func.count(AuditLog.id)).scalar() or 0
    q = q.order_by(AuditLog.fecha.desc())
    if paginar:
        q = q.offset((page - 1) * page_size).limit(page_size)
    else:
        q = q.limit(50000)  # tope duro del export CSV
    return q.all(), total


def evento_a_dto(e: AuditLog) -> dict:
    """EventoDto camelCase (contrato exacto del frontend)."""
    return {
        "id": str(e.id),
        "fecha": e.fecha.isoformat() if e.fecha else None,
        "accion": e.accion,
        "usuarioNombre": e.usuario_nombre,
        "rol": e.rol,
        "ip": e.ip,
        "ruta": e.ruta,
        "metodoHttp": e.metodo_http,
        "resultado": e.resultado,
        "entidad": e.entidad,
        "entidadId": e.entidad_id,
        "detalle": e.detalle,
        "userAgent": e.user_agent,
    }
