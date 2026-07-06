"""
Monitoreo de seguridad (módulo Gestión de TIC).

`evaluar_reglas()` corre cada 5 min desde el scheduler y evalúa umbrales sobre
audit_log. Es idempotente: no crea una alerta si ya existe una ABIERTA del
mismo tipo + misma IP/usuario en las últimas 2 horas (ventana de dedup).

Al crear una alerta:
  - notifica SOLO al rol Soporte (mismos helpers que backups: _usuarios_por_rol
    y _emitir del scheduler, import perezoso anti-ciclos),
  - deja rastro en audit_log con accion=SECURITY.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.models.alerta_seguridad import AlertaSeguridad
from app.models.audit_log import AuditLog
from app.services.audit_service import registrar_evento

logger = logging.getLogger("seguridad_monitor")

VENTANA_DEDUP_HORAS = 2


def _hay_alerta_abierta(db: Session, tipo: str, *, ip: str | None = None,
                        usuario_id: str | None = None,
                        username: str | None = None) -> bool:
    """Dedup: ¿ya existe una alerta abierta del mismo tipo + clave en 2 h?"""
    desde = datetime.utcnow() - timedelta(hours=VENTANA_DEDUP_HORAS)
    q = db.query(AlertaSeguridad).filter(
        AlertaSeguridad.tipo == tipo,
        AlertaSeguridad.estado == "abierta",
        AlertaSeguridad.fecha >= desde,
    )
    if ip is not None:
        return q.filter(AlertaSeguridad.ip == ip).first() is not None
    if usuario_id is not None:
        return q.filter(AlertaSeguridad.usuario_id == usuario_id).first() is not None
    if username is not None:
        # username vive en detalle (no hay columna); pocas filas en 2h → Python
        for a in q.all():
            if isinstance(a.detalle, dict) and a.detalle.get("username") == username:
                return True
        return False
    return q.first() is not None


def _notificar_soporte(db: Session, alerta: AlertaSeguridad) -> None:
    """Notifica la alerta SOLO al rol Soporte, igual que backups (in-app + push).
    Import perezoso para evitar ciclos con scheduler_service."""
    from app.services.scheduler_service import _usuarios_por_rol, _emitir
    from app.models.empresa import Empresa

    mensaje = (f"{alerta.titulo}. Revísala en Gestión TIC → Seguridad.")
    for (empresa_id,) in db.query(Empresa.id).all():
        usuarios = _usuarios_por_rol(db, empresa_id, ["Soporte"])
        _emitir(db, empresa_id=empresa_id, usuarios=usuarios, tipo="warning",
                categoria="seguridad", titulo="Alerta de seguridad",
                mensaje=mensaje,
                ref_key=f"seguridad:{alerta.id}:{empresa_id}")
    db.commit()


def _crear_alerta(db: Session, *, tipo: str, severidad: str, titulo: str,
                  detalle: dict, ip: str | None = None,
                  usuario_id: str | None = None) -> AlertaSeguridad:
    alerta = AlertaSeguridad(
        id=str(uuid.uuid4()), tipo=tipo, severidad=severidad,
        titulo=titulo[:200], detalle=detalle, ip=ip, usuario_id=usuario_id,
        fecha=datetime.utcnow(), estado="abierta",
    )
    db.add(alerta)
    db.commit()

    # Rastro en audit_log (accion=SECURITY) — best-effort, sesión propia
    registrar_evento(
        accion="SECURITY", resultado="exito", usuario_id=usuario_id, ip=ip,
        entidad="alerta_seguridad", entidad_id=str(alerta.id),
        detalle={"tipo": tipo, "severidad": severidad, "titulo": titulo},
    )
    try:
        _notificar_soporte(db, alerta)
    except Exception as e:  # noqa: BLE001 — la alerta ya quedó persistida
        logger.warning("No se pudo notificar alerta %s a Soporte: %s", alerta.id, e)
        try:
            db.rollback()
        except Exception:
            pass
    return alerta


def evaluar_reglas() -> int:
    """Evalúa las 4 reglas y devuelve cuántas alertas nuevas creó.
    Sesión propia; pensada para el job del scheduler (también invocable a mano)."""
    db: Session = SessionLocal()
    creadas = 0
    try:
        ahora = datetime.utcnow()

        # 1) fuerza_bruta: >=5 LOGIN_FALLIDO desde la misma IP en 10 min → alta
        rows = (db.query(AuditLog.ip, func.count(AuditLog.id))
                .filter(AuditLog.accion == "LOGIN_FALLIDO",
                        AuditLog.fecha >= ahora - timedelta(minutes=10),
                        AuditLog.ip.isnot(None))
                .group_by(AuditLog.ip)
                .having(func.count(AuditLog.id) >= 5).all())
        for ip, n in rows:
            if _hay_alerta_abierta(db, "fuerza_bruta", ip=ip):
                continue
            _crear_alerta(
                db, tipo="fuerza_bruta", severidad="alta",
                titulo=f"Posible fuerza bruta: {n} logins fallidos desde la IP {ip} en 10 min",
                detalle={"ip": ip, "intentos": int(n), "ventanaMin": 10}, ip=ip,
            )
            creadas += 1

        # 2) logins_fallidos_usuario: >=4 del mismo username en 15 min → media
        username_expr = AuditLog.detalle["username"].astext
        rows = (db.query(username_expr, func.count(AuditLog.id))
                .filter(AuditLog.accion == "LOGIN_FALLIDO",
                        AuditLog.fecha >= ahora - timedelta(minutes=15),
                        username_expr.isnot(None))
                .group_by(username_expr)
                .having(func.count(AuditLog.id) >= 4).all())
        for username, n in rows:
            if _hay_alerta_abierta(db, "logins_fallidos_usuario", username=username):
                continue
            _crear_alerta(
                db, tipo="logins_fallidos_usuario", severidad="media",
                titulo=f"{n} logins fallidos para el usuario «{username}» en 15 min",
                detalle={"username": username, "intentos": int(n), "ventanaMin": 15},
            )
            creadas += 1

        # 3) denegados_repetidos: >=6 PERMISSION_DENIED del mismo usuario_id
        #    o de la misma IP en 15 min → media
        desde15 = ahora - timedelta(minutes=15)
        rows = (db.query(AuditLog.usuario_id, func.count(AuditLog.id))
                .filter(AuditLog.accion == "PERMISSION_DENIED",
                        AuditLog.fecha >= desde15,
                        AuditLog.usuario_id.isnot(None))
                .group_by(AuditLog.usuario_id)
                .having(func.count(AuditLog.id) >= 6).all())
        usuarios_alertados: set[str] = set()
        for uid, n in rows:
            if _hay_alerta_abierta(db, "denegados_repetidos", usuario_id=uid):
                continue
            nombre = _nombre_usuario(db, uid)
            _crear_alerta(
                db, tipo="denegados_repetidos", severidad="media",
                titulo=f"{n} accesos denegados (403) para {nombre or uid} en 15 min",
                detalle={"usuarioId": uid, "usuarioNombre": nombre,
                         "denegados": int(n), "ventanaMin": 15},
                usuario_id=uid,
            )
            usuarios_alertados.add(uid)
            creadas += 1
        q_ip = (db.query(AuditLog.ip, func.count(AuditLog.id))
                .filter(AuditLog.accion == "PERMISSION_DENIED",
                        AuditLog.fecha >= desde15,
                        AuditLog.ip.isnot(None)))
        if usuarios_alertados:
            # No duplicar por IP lo ya alertado por usuario en esta pasada
            q_ip = q_ip.filter(or_(AuditLog.usuario_id.is_(None),
                                   ~AuditLog.usuario_id.in_(usuarios_alertados)))
        rows = q_ip.group_by(AuditLog.ip).having(func.count(AuditLog.id) >= 6).all()
        for ip, n in rows:
            if _hay_alerta_abierta(db, "denegados_repetidos", ip=ip):
                continue
            _crear_alerta(
                db, tipo="denegados_repetidos", severidad="media",
                titulo=f"{n} accesos denegados (403) desde la IP {ip} en 15 min",
                detalle={"ip": ip, "denegados": int(n), "ventanaMin": 15}, ip=ip,
            )
            creadas += 1

        # 4) descarga_masiva: >=15 DOWNLOAD/EXPORT del mismo usuario en 10 min → media
        rows = (db.query(AuditLog.usuario_id, func.count(AuditLog.id))
                .filter(AuditLog.accion.in_(("DOWNLOAD", "EXPORT")),
                        AuditLog.fecha >= ahora - timedelta(minutes=10),
                        AuditLog.usuario_id.isnot(None))
                .group_by(AuditLog.usuario_id)
                .having(func.count(AuditLog.id) >= 15).all())
        for uid, n in rows:
            if _hay_alerta_abierta(db, "descarga_masiva", usuario_id=uid):
                continue
            nombre = _nombre_usuario(db, uid)
            _crear_alerta(
                db, tipo="descarga_masiva", severidad="media",
                titulo=f"Descarga masiva: {n} descargas/exportaciones de {nombre or uid} en 10 min",
                detalle={"usuarioId": uid, "usuarioNombre": nombre,
                         "descargas": int(n), "ventanaMin": 10},
                usuario_id=uid,
            )
            creadas += 1

        if creadas:
            logger.info("Monitoreo de seguridad: %d alerta(s) nueva(s)", creadas)
        return creadas
    except Exception as e:  # noqa: BLE001 — el job nunca debe reventar
        logger.error("evaluar_reglas falló: %s", e)
        try:
            db.rollback()
        except Exception:
            pass
        return creadas
    finally:
        db.close()


def _nombre_usuario(db: Session, usuario_id: str | None) -> str | None:
    if not usuario_id:
        return None
    try:
        from app.models.usuario import Usuario
        u = db.query(Usuario.nombre, Usuario.apellido).filter(
            Usuario.id == usuario_id).first()
        return f"{u.nombre} {u.apellido}".strip() if u else None
    except Exception:
        return None
