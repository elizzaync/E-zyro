"""
Router: WebSocket Chat en tiempo real
  - Cada sala está aislada por servicio_id (proyecto_servicio.id)
  - Canal general del servicio: broadcast a todos los conectados
  - Mensajes Directos (DM): broadcast solo al remitente + destinatario
  - Autenticación: ?token=<JWT> en el query string
  - Persistencia: cada mensaje se guarda en mensaje_chat con servicio_id
"""
from __future__ import annotations

import asyncio
import uuid
import json
import os
from datetime import datetime, timezone
from typing import Dict, List

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import jwt, JWTError

from ..db.database import SessionLocal
from ..models.mensaje_chat import MensajeChat
from ..models.usuario import Usuario
from ..models.proyecto_servicio import ProyectoServicio

router = APIRouter(tags=["chat-ws"])

_SECRET_KEY = os.getenv("SECRET_KEY", "")
_ALGORITHM  = "HS256"


# ── Autenticación desde query param ──────────────────────────────────────────

def _decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
    except JWTError:
        return None


# ── Connection Manager ────────────────────────────────────────────────────────

class ConnectionManager:
    """
    Cada sala (room) está identificada por servicio_id, garantizando
    que distintos servicios nunca compartan mensajes.

    Estructura:
        _activas[servicio_id][usuario_id] = [WebSocket, ...]

    Un usuario puede abrir múltiples pestañas/dispositivos;
    todos reciben el mensaje.
    """

    def __init__(self) -> None:
        self._activas: Dict[str, Dict[str, List[WebSocket]]] = {}

    async def conectar(self, ws: WebSocket, servicio_id: str, usuario_id: str) -> None:
        await ws.accept()
        self._activas.setdefault(servicio_id, {}).setdefault(usuario_id, []).append(ws)

    def desconectar(self, ws: WebSocket, servicio_id: str, usuario_id: str) -> None:
        sockets = self._activas.get(servicio_id, {}).get(usuario_id, [])
        if ws in sockets:
            sockets.remove(ws)
        if not sockets:
            self._activas.get(servicio_id, {}).pop(usuario_id, None)
        if not self._activas.get(servicio_id):
            self._activas.pop(servicio_id, None)

    async def _enviar(self, ws: WebSocket, payload: dict) -> None:
        try:
            await ws.send_text(json.dumps(payload, default=str, ensure_ascii=False))
        except Exception:
            pass

    async def broadcast_servicio(self, servicio_id: str, payload: dict) -> None:
        """Envía el mensaje a TODOS los conectados en este servicio."""
        for sockets in list(self._activas.get(servicio_id, {}).values()):
            for ws in sockets:
                await self._enviar(ws, payload)

    async def broadcast_dm(
        self,
        servicio_id:     str,
        remitente_id:    str,
        destinatario_id: str,
        payload:         dict,
    ) -> None:
        """Envía el DM solo al remitente y al destinatario dentro de este servicio."""
        sala = self._activas.get(servicio_id, {})
        for uid in (remitente_id, destinatario_id):
            for ws in list(sala.get(uid, [])):
                await self._enviar(ws, payload)


manager = ConnectionManager()


# ── Helpers de BD ─────────────────────────────────────────────────────────────

def _guardar_mensaje(
    servicio_id:     str,
    empresa_id:      str,
    remitente_id:    str,
    contenido:       str,
    destinatario_id: str | None = None,
    padre_id:        str | None = None,
) -> MensajeChat:
    db = SessionLocal()
    try:
        # Resolvemos proyecto_id desde proyecto_servicio para mantener la FK existente
        ps = db.query(ProyectoServicio).filter(ProyectoServicio.id == servicio_id).first()
        proyecto_id = ps.proyecto_id if ps else servicio_id

        msg = MensajeChat(
            id                   = str(uuid.uuid4()),
            proyecto_servicio_id = uuid.UUID(servicio_id),
            proyecto_id          = proyecto_id,
            empresa_id      = empresa_id,
            remitente_id    = remitente_id,
            destinatario_id = uuid.UUID(destinatario_id) if destinatario_id else None,
            padre_id        = padre_id,
            contenido       = contenido,
            fecha           = datetime.now(timezone.utc),
        )
        db.add(msg)
        db.commit()
        db.refresh(msg)
        return msg
    finally:
        db.close()


def _nombre_usuario(usuario_id: str) -> str:
    db = SessionLocal()
    try:
        u = db.query(Usuario).filter(Usuario.id == usuario_id).first()
        if u:
            return f"{u.nombre} {u.apellido}".strip()
        return "Usuario"
    finally:
        db.close()


def _notificar_push_chat(servicio_id, empresa_id, remitente_id, nombre_remitente,
                         contenido, destinatario_id, conectados):
    """Push de chat a los miembros del servicio que NO están conectados a la sala.
    DM → solo el destinatario. Respeta la preferencia 'chat' (default OFF)."""
    from ..services.fcm_service import enviar_push_a_usuario
    from ..models.proyecto_miembro import ProyectoMiembro
    from ..models.empleado import Empleado

    db = SessionLocal()
    try:
        if destinatario_id:
            destinatarios = {str(destinatario_id)}
        else:
            ps = db.query(ProyectoServicio).filter(ProyectoServicio.id == servicio_id).first()
            if not ps:
                return
            rows = (
                db.query(Empleado.usuario_id)
                .join(ProyectoMiembro, ProyectoMiembro.empleado_id == Empleado.id)
                .filter(ProyectoMiembro.proyecto_id == str(ps.proyecto_id),
                        ProyectoMiembro.activo == True,  # noqa: E712
                        Empleado.usuario_id.isnot(None))
                .all()
            )
            destinatarios = {str(r.usuario_id) for r in rows}

        destinatarios.discard(str(remitente_id))
        destinatarios -= {str(c) for c in conectados}  # ya están viendo la sala
        if not destinatarios:
            return

        titulo = f"💬 {nombre_remitente}"
        cuerpo = contenido if len(contenido) <= 140 else contenido[:137] + "..."
        for uid in destinatarios:
            try:
                enviar_push_a_usuario(
                    usuario_id=uid, titulo=titulo, mensaje=cuerpo, db=db,
                    tipo="chat", categoria="chat",
                    referencia_id=str(servicio_id), referencia_tabla="chat_servicio",
                )
            except Exception:
                pass
    finally:
        db.close()


def _cargar_historial(servicio_id: str, limit: int = 50) -> list:
    """Carga los últimos `limit` mensajes del servicio, ordenados cronológicamente."""
    db = SessionLocal()
    try:
        rows = (
            db.query(MensajeChat, Usuario)
            .join(Usuario, MensajeChat.remitente_id == Usuario.id)
            .filter(MensajeChat.proyecto_servicio_id == uuid.UUID(servicio_id))
            .order_by(MensajeChat.fecha.desc())
            .limit(limit)
            .all()
        )
        rows.reverse()
        return [
            {
                "tipo":             "mensaje",
                "id":               msg.id,
                "remitente_id":     msg.remitente_id,
                "nombre_remitente": f"{u.nombre} {u.apellido}".strip(),
                "contenido":        msg.contenido,
                "destinatario_id":  str(msg.destinatario_id) if msg.destinatario_id else None,
                "padre_id":         msg.padre_id,
                "es_dm":            msg.destinatario_id is not None,
                "fecha":            msg.fecha.isoformat(),
            }
            for msg, u in rows
        ]
    finally:
        db.close()


# ── Endpoint WebSocket ────────────────────────────────────────────────────────

@router.websocket("/ws/chat/servicio/{servicio_id}")
async def ws_chat(ws: WebSocket, servicio_id: str, token: str = ""):
    """
    Conecta al chat aislado de un servicio específico (proyecto_servicio.id).

    Payload de ENTRADA (JSON string):
    {
      "contenido":       "Hola equipo",
      "destinatario_id": null,          // null = general, UUID = DM
      "padre_id":        null           // null = mensaje raíz, UUID = respuesta
    }

    Payload de SALIDA (JSON string):
    {
      "tipo":            "mensaje" | "historial" | "error",
      "id":              "<uuid>",
      "remitente_id":    "<uuid>",
      "nombre_remitente":"Nombre Apellido",
      "contenido":       "...",
      "destinatario_id": null | "<uuid>",
      "padre_id":        null | "<uuid>",
      "es_dm":           false | true,
      "fecha":           "2025-05-15T12:00:00"
    }
    """
    payload = _decode_token(token)
    if payload is None:
        await ws.accept()
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Token inválido o expirado"}, default=str))
        await ws.close(code=4001)
        return

    usuario_id = payload.get("id")
    empresa_id = payload.get("empresa_id")

    if not usuario_id or not empresa_id:
        await ws.accept()
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Token sin claims requeridos"}, default=str))
        await ws.close(code=4001)
        return

    await manager.conectar(ws, servicio_id, usuario_id)
    nombre = _nombre_usuario(usuario_id)

    # Enviar historial del servicio al usuario recién conectado
    historial = _cargar_historial(servicio_id)
    await ws.send_text(json.dumps({"tipo": "historial", "mensajes": historial}, default=str, ensure_ascii=False))

    try:
        while True:
            raw = await ws.receive_text()

            try:
                data = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                await ws.send_text(json.dumps({"tipo": "error", "detalle": "JSON inválido"}, default=str))
                continue

            contenido       = str(data.get("contenido", "")).strip()
            destinatario_id = data.get("destinatario_id") or None
            padre_id        = data.get("padre_id") or None

            if not contenido:
                continue

            msg = _guardar_mensaje(
                servicio_id     = servicio_id,
                empresa_id      = empresa_id,
                remitente_id    = usuario_id,
                contenido       = contenido,
                destinatario_id = destinatario_id,
                padre_id        = padre_id,
            )

            out_payload = {
                "tipo":             "mensaje",
                "id":               msg.id,
                "remitente_id":     usuario_id,
                "nombre_remitente": nombre,
                "contenido":        contenido,
                "destinatario_id":  destinatario_id,
                "padre_id":         padre_id,
                "es_dm":            destinatario_id is not None,
                "fecha":            msg.fecha.isoformat(),
            }

            if destinatario_id:
                await manager.broadcast_dm(
                    servicio_id     = servicio_id,
                    remitente_id    = usuario_id,
                    destinatario_id = destinatario_id,
                    payload         = out_payload,
                )
            else:
                await manager.broadcast_servicio(servicio_id, out_payload)

            # Push a quienes NO están conectados a la sala (en hilo aparte para
            # no bloquear el event loop del WebSocket).
            conectados = list(manager._activas.get(servicio_id, {}).keys())
            try:
                asyncio.get_event_loop().run_in_executor(
                    None, _notificar_push_chat, servicio_id, empresa_id, usuario_id,
                    nombre, contenido, destinatario_id, conectados,
                )
            except Exception:
                pass

    except WebSocketDisconnect:
        manager.desconectar(ws, servicio_id, usuario_id)
