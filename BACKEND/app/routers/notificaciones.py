from __future__ import annotations

import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from zoneinfo import ZoneInfo

from app.core.security import verificar_token
from app.core.tz import fmt_lima_iso
from app.db.database import get_db
from app.models.dispositivo_push import DispositivoPush
from app.models.notificacion import Notificacion
from app.services.fcm_service import enviar_push_a_usuario


def _uid(val: str | None) -> uuid.UUID | None:
    """Convierte string a UUID para filtros sobre columnas uuid nativas."""
    if not val:
        return None
    try:
        return uuid.UUID(str(val))
    except (ValueError, AttributeError):
        return None

router = APIRouter(prefix="/notificaciones", tags=["Notificaciones"])
ZONA = ZoneInfo("America/Lima")


# ── Schemas ────────────────────────────────────────────────────────────────────

class RegistrarDispositivoRequest(BaseModel):
    token_push: str
    plataforma: str  # "android" | "ios"


class NotificacionResponse(BaseModel):
    id: str
    tipo: str
    categoria: Optional[str]
    titulo: str
    mensaje: str
    leido: bool
    enviado: bool
    referencia_tabla: Optional[str]
    referencia_id: Optional[str]
    created_at: str


class InyectarNotificacionRequest(BaseModel):
    usuario_id: Optional[str] = None   # None → enviar a sí mismo
    titulo: str
    mensaje: str
    tipo: str = "general"              # general | comunicado | servicio | recordatorio
    categoria: Optional[str] = None
    referencia_tabla: Optional[str] = None
    referencia_id: Optional[str] = None


# ── Dispositivos ───────────────────────────────────────────────────────────────

@router.post("/dispositivos/registrar", status_code=status.HTTP_200_OK)
def registrar_dispositivo(
    body: RegistrarDispositivoRequest,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """
    Registra (o reactiva) el token FCM del dispositivo del usuario actual.
    Si el token ya existe para este usuario lo marca como activo.
    Desactiva tokens anteriores del mismo usuario en la misma plataforma
    para que no se envíen duplicados.
    """
    usuario_id = payload["id"]
    uid = _uid(usuario_id)

    # Eliminar tokens anteriores de la misma plataforma para este usuario.
    # Cada reinstalación/rebuild del app genera un token FCM nuevo; si solo se
    # desactivaran, la tabla acumularía decenas de filas obsoletas (y Firebase
    # podría aceptar envíos a tokens muertos → falsos "fcm_enviado=true").
    # Dejamos exactamente un token activo por (usuario, plataforma).
    db.query(DispositivoPush).filter(
        DispositivoPush.usuario_id == uid,
        DispositivoPush.plataforma == body.plataforma,
        DispositivoPush.token_push != body.token_push,
    ).delete(synchronize_session=False)

    # Upsert: buscar por (usuario_id, token_push)
    existing = db.query(DispositivoPush).filter(
        DispositivoPush.usuario_id == uid,
        DispositivoPush.token_push == body.token_push,
    ).first()

    if existing:
        existing.activo = True
        existing.plataforma = body.plataforma
        existing.updated_at = datetime.now(ZONA)
    else:
        db.add(DispositivoPush(
            id=str(uuid.uuid4()),
            usuario_id=usuario_id,
            token_push=body.token_push,
            plataforma=body.plataforma,
            activo=True,
        ))

    db.commit()
    return {"status": "success", "mensaje": "Dispositivo registrado"}


@router.post("/dispositivos/desregistrar", status_code=status.HTTP_200_OK)
def desregistrar_dispositivo(
    body: RegistrarDispositivoRequest,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Desactiva el token FCM al hacer logout."""
    uid = _uid(payload["id"])
    db.query(DispositivoPush).filter(
        DispositivoPush.usuario_id == uid,
        DispositivoPush.token_push == body.token_push,
    ).update({"activo": False, "updated_at": datetime.now(ZONA)})
    db.commit()
    return {"status": "success", "mensaje": "Dispositivo desregistrado"}


# ── Notificaciones del usuario ─────────────────────────────────────────────────

@router.get("", response_model=List[NotificacionResponse])
def listar_notificaciones(
    solo_no_leidas: bool = False,
    limite: int = 50,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """
    Devuelve las notificaciones del usuario autenticado.
    - solo_no_leidas=true → filtra solo las no leídas
    - limite → máximo de registros (default 50)
    """
    usuario_id = payload["id"]
    uid = _uid(usuario_id)
    if uid is None:
        return []
    q = db.query(Notificacion).filter(Notificacion.usuario_id == uid)
    if solo_no_leidas:
        q = q.filter(Notificacion.leido == False)
    notificaciones = q.order_by(Notificacion.created_at.desc()).limit(limite).all()

    return [
        NotificacionResponse(
            id=str(n.id),
            tipo=str(n.tipo),
            categoria=str(n.categoria) if n.categoria else None,
            titulo=str(n.titulo),
            mensaje=str(n.mensaje),
            leido=bool(n.leido),
            enviado=bool(n.enviado),
            referencia_tabla=str(n.referencia_tabla) if n.referencia_tabla else None,
            referencia_id=str(n.referencia_id) if n.referencia_id else None,
            created_at=fmt_lima_iso(n.created_at) or "",
        )
        for n in notificaciones
    ]


@router.get("/no-leidas/count")
def contar_no_leidas(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Badge counter: número de notificaciones no leídas."""
    uid = _uid(payload["id"])
    if uid is None:
        return {"total": 0}
    total = db.query(Notificacion).filter(
        Notificacion.usuario_id == uid,
        Notificacion.leido == False,
    ).count()
    return {"total": total}


@router.post("/leer-todo")
def marcar_todas_leidas(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Marca todas las notificaciones del usuario como leídas."""
    uid = _uid(payload["id"])
    if uid:
        db.query(Notificacion).filter(
            Notificacion.usuario_id == uid,
            Notificacion.leido == False,
        ).update({"leido": True})
        db.commit()
    return {"status": "success"}


@router.post("/{notificacion_id}/leer")
def marcar_leida(
    notificacion_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Marca una notificación concreta como leída."""
    uid = _uid(payload["id"])
    n = db.query(Notificacion).filter(
        Notificacion.id == _uid(notificacion_id),
        Notificacion.usuario_id == uid,
    ).first()
    if not n:
        raise HTTPException(status_code=404, detail="Notificación no encontrada")
    n.leido = True
    db.commit()
    return {"status": "success"}


# ── Eliminar notificaciones ───────────────────────────────────────────────────

@router.delete("/eliminar-leidas")
def eliminar_leidas(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Elimina permanentemente todas las notificaciones ya leídas del usuario."""
    uid = _uid(payload["id"])
    if uid:
        db.query(Notificacion).filter(
            Notificacion.usuario_id == uid,
            Notificacion.leido == True,
        ).delete(synchronize_session=False)
    db.commit()
    return {"status": "success"}


@router.delete("/{notificacion_id}")
def eliminar_notificacion(
    notificacion_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Elimina una notificación concreta del usuario autenticado."""
    uid = _uid(payload["id"])
    n = db.query(Notificacion).filter(
        Notificacion.id == _uid(notificacion_id),
        Notificacion.usuario_id == uid,
    ).first()
    if not n:
        raise HTTPException(status_code=404, detail="Notificación no encontrada")
    db.delete(n)
    db.commit()
    return {"status": "success"}


# ── Inyección de prueba ────────────────────────────────────────────────────────

@router.post("/test/inyectar")
def inyectar_notificacion(
    body: InyectarNotificacionRequest,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """[ADMIN ONLY] Inyecta una notificación de prueba. Solo disponible para administradores."""
    rol = payload.get("rol", "")
    if rol.lower() not in ("admin", "administrador", "superadmin"):
        raise HTTPException(status_code=403, detail="Acceso denegado. Solo administradores.")
    destinatario_id = body.usuario_id or payload["id"]
    empresa_id = payload.get("empresa_id", "")

    # 1. Persistir en BD
    nueva = Notificacion(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        usuario_id=destinatario_id,
        tipo=body.tipo,
        categoria=body.categoria or "test",
        titulo=body.titulo,
        mensaje=body.mensaje,
        leido=False,
        enviado=False,
        fecha_envio=datetime.now(ZONA),
        referencia_tabla=body.referencia_tabla,
        referencia_id=body.referencia_id,
    )
    db.add(nueva)
    db.flush()  # para tener el ID antes del commit

    # 2. Enviar push FCM
    fcm_ok = enviar_push_a_usuario(
        usuario_id=destinatario_id,
        titulo=body.titulo,
        mensaje=body.mensaje,
        tipo=body.tipo,
        categoria=body.categoria or "",
        referencia_id=body.referencia_id or nueva.id,
        referencia_tabla=body.referencia_tabla or "",
        db=db,
    )

    nueva.enviado = fcm_ok
    db.commit()

    return {
        "status": "success",
        "notificacion_id": nueva.id,
        "fcm_enviado": fcm_ok,
        "destinatario_id": destinatario_id,
    }
