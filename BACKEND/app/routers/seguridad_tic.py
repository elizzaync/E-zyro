"""
Router: /seguridad-tic (módulo Seguridad · Gestión de TIC)

Panel de monitoreo de seguridad para el rol Soporte: métricas 24h, eventos
de audit_log filtrables y alertas del monitoreo (revisar/cerrar).

Restringido a Soporte / TI / admin total — mismo gate que backups.py: el
backend es la protección real, el frontend solo oculta la pantalla.
"""
from __future__ import annotations

import unicodedata
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.security import verificar_token
from app.db.database import get_db
from app.models.alerta_seguridad import AlertaSeguridad
from app.models.audit_log import AuditLog
from app.models.sesion_usuario import SesionUsuario
from app.models.usuario import Usuario
from app.services.audit_service import consultar_eventos, evento_a_dto

router = APIRouter(prefix="/seguridad-tic", tags=["seguridad-tic"])


# ── Autorización: solo Soporte / TI / admin total (clon de backups.py) ────────

def _autorizar_soporte(payload: dict) -> None:
    if payload.get("admin_total"):
        return
    rol = (payload.get("rol") or "").strip().lower()
    rol = unicodedata.normalize("NFC", rol).replace("\xa0", " ")
    if rol in ("soporte", "ti", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Solo Soporte puede ver el panel de seguridad")


def _nombre_usuario(db: Session, usuario_id: str | None) -> str | None:
    if not usuario_id:
        return None
    u = db.query(Usuario.nombre, Usuario.apellido).filter(
        Usuario.id == usuario_id).first()
    return f"{u.nombre} {u.apellido}".strip() if u else None


def _alerta_dto(db: Session, a: AlertaSeguridad) -> dict:
    return {
        "id": str(a.id),
        "tipo": a.tipo,
        "severidad": a.severidad,
        "titulo": a.titulo,
        "detalle": a.detalle,
        "ip": a.ip,
        "usuarioNombre": _nombre_usuario(db, a.usuario_id),
        "fecha": a.fecha.isoformat() if a.fecha else None,
        "estado": a.estado,
        "revisadaPorNombre": _nombre_usuario(db, a.revisada_por),
        "fechaRevision": a.fecha_revision.isoformat() if a.fecha_revision else None,
    }


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/metricas")
def metricas(payload: dict = Depends(verificar_token),
             db: Session = Depends(get_db)):
    _autorizar_soporte(payload)
    hace24 = datetime.utcnow() - timedelta(hours=24)

    def _contar(*acciones: str) -> int:
        return (db.query(func.count(AuditLog.id))
                .filter(AuditLog.accion.in_(acciones), AuditLog.fecha >= hace24)
                .scalar() or 0)

    # sesion_usuario guarda fechas en hora local Lima (naive) — comparar igual
    ahora_lima = datetime.now(ZoneInfo("America/Lima")).replace(tzinfo=None)
    sesiones = (db.query(func.count(SesionUsuario.id))
                .filter(SesionUsuario.activa.is_(True),
                        SesionUsuario.fecha_expiracion > ahora_lima)
                .scalar() or 0)
    alertas = (db.query(func.count(AlertaSeguridad.id))
               .filter(AlertaSeguridad.estado == "abierta").scalar() or 0)

    return {
        "loginsFallidos24h":    _contar("LOGIN_FALLIDO"),
        "permisosDenegados24h": _contar("PERMISSION_DENIED"),
        "sesionesActivas":      sesiones,
        "alertasAbiertas":      alertas,
        "descargas24h":         _contar("DOWNLOAD", "EXPORT"),
        "loginsExitosos24h":    _contar("LOGIN"),
    }


@router.get("/eventos")
def eventos(
    accion:        str = Query("todas"),
    usuarioNombre: str = Query(""),
    ip:            str = Query(""),
    desde:         str = Query(""),   # YYYY-MM-DD
    hasta:         str = Query(""),   # YYYY-MM-DD
    resultado:     str = Query(""),
    page:          int = Query(1, ge=1),
    page_size:     int = Query(25, ge=1, le=200),
    payload:       dict = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    _autorizar_soporte(payload)
    filas, total = consultar_eventos(
        db, accion=accion or None, usuario_nombre=usuarioNombre or None,
        ip=ip or None, desde=desde or None, hasta=hasta or None,
        resultado=resultado or None, page=page, page_size=page_size,
    )
    return {"items": [evento_a_dto(e) for e in filas], "total": total,
            "page": page, "pageSize": page_size}


@router.get("/alertas")
def alertas(
    estado:  str = Query("abierta"),   # abierta | revisada | todas
    payload: dict = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    _autorizar_soporte(payload)
    q = db.query(AlertaSeguridad)
    if estado and estado != "todas":
        q = q.filter(AlertaSeguridad.estado == estado)
    filas = q.order_by(AlertaSeguridad.fecha.desc()).limit(500).all()
    return {"items": [_alerta_dto(db, a) for a in filas], "total": len(filas)}


@router.post("/alertas/{alerta_id}/revisar")
def revisar_alerta(
    alerta_id: str,
    payload:   dict = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _autorizar_soporte(payload)
    a = db.query(AlertaSeguridad).filter(AlertaSeguridad.id == alerta_id).first()
    if not a:
        raise HTTPException(status_code=404, detail="Alerta no encontrada")
    if a.estado != "revisada":
        a.estado = "revisada"
        a.revisada_por = payload.get("id")
        a.fecha_revision = datetime.utcnow()
        db.commit()
        db.refresh(a)
    return _alerta_dto(db, a)
