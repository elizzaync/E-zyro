"""
Router: WebSocket Chat en tiempo real
  - Canal general del proyecto: broadcast a todos los conectados
  - Mensajes Directos (DM): broadcast solo al remitente + destinatario
  - Autenticación: ?token=<JWT> en el query string
  - Persistencia: cada mensaje se guarda en mensaje_chat
"""
from __future__ import annotations

import uuid
import json
import os
from datetime import datetime
from typing import Dict, List

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import jwt, JWTError

from ..db.database import SessionLocal
from ..models.mensaje_chat import MensajeChat
from ..models.usuario import Usuario

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
    Estructura:
        _activas[proyecto_id][usuario_id] = [WebSocket, ...]

    Un usuario puede abrir múltiples pestañas/dispositivos;
    todos reciben el mensaje.
    """

    def __init__(self) -> None:
        self._activas: Dict[str, Dict[str, List[WebSocket]]] = {}

    async def conectar(self, ws: WebSocket, proyecto_id: str, usuario_id: str) -> None:
        await ws.accept()
        self._activas.setdefault(proyecto_id, {}).setdefault(usuario_id, []).append(ws)

    def desconectar(self, ws: WebSocket, proyecto_id: str, usuario_id: str) -> None:
        sockets = self._activas.get(proyecto_id, {}).get(usuario_id, [])
        if ws in sockets:
            sockets.remove(ws)
        if not sockets:
            self._activas.get(proyecto_id, {}).pop(usuario_id, None)
        if not self._activas.get(proyecto_id):
            self._activas.pop(proyecto_id, None)

    async def _enviar(self, ws: WebSocket, payload: dict) -> None:
        try:
            await ws.send_text(json.dumps(payload, ensure_ascii=False))
        except Exception:
            pass

    async def broadcast_proyecto(self, proyecto_id: str, payload: dict) -> None:
        """Envía el mensaje a TODOS los conectados en el proyecto."""
        for sockets in list(self._activas.get(proyecto_id, {}).values()):
            for ws in sockets:
                await self._enviar(ws, payload)

    async def broadcast_dm(
        self,
        proyecto_id:     str,
        remitente_id:    str,
        destinatario_id: str,
        payload:         dict,
    ) -> None:
        """Envía el DM solo al remitente y al destinatario."""
        proyecto_sockets = self._activas.get(proyecto_id, {})
        for uid in (remitente_id, destinatario_id):
            for ws in list(proyecto_sockets.get(uid, [])):
                await self._enviar(ws, payload)


manager = ConnectionManager()


# ── Helpers de BD ─────────────────────────────────────────────────────────────

def _guardar_mensaje(
    proyecto_id:     str,
    empresa_id:      str,
    remitente_id:    str,
    contenido:       str,
    destinatario_id: str | None = None,
    padre_id:        str | None = None,
) -> MensajeChat:
    db = SessionLocal()
    try:
        msg = MensajeChat(
            id              = str(uuid.uuid4()),
            proyecto_id     = proyecto_id,
            empresa_id      = empresa_id,
            remitente_id    = remitente_id,
            destinatario_id = uuid.UUID(destinatario_id) if destinatario_id else None,
            padre_id        = padre_id,
            contenido       = contenido,
            fecha           = datetime.utcnow(),
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


# ── Endpoint WebSocket ────────────────────────────────────────────────────────

@router.websocket("/ws/chat/{proyecto_id}")
async def ws_chat(ws: WebSocket, proyecto_id: str, token: str = ""):
    """
    Conecta al canal de chat de un proyecto.

    Payload de ENTRADA (JSON string):
    {
      "contenido":       "Hola equipo",
      "destinatario_id": null,          // null = general, UUID = DM
      "padre_id":        null           // null = mensaje raíz, UUID = respuesta
    }

    Payload de SALIDA (JSON string):
    {
      "tipo":            "mensaje" | "error",
      "id":              "<uuid>",
      "remitente_id":    "<uuid>",
      "remitente_nombre":"Nombre Apellido",
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
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Token inválido o expirado"}))
        await ws.close(code=4001)
        return

    usuario_id = payload.get("id")
    empresa_id = payload.get("empresa_id")

    if not usuario_id or not empresa_id:
        await ws.accept()
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Token sin claims requeridos"}))
        await ws.close(code=4001)
        return

    await manager.conectar(ws, proyecto_id, usuario_id)
    nombre = _nombre_usuario(usuario_id)

    try:
        while True:
            raw = await ws.receive_text()

            try:
                data = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                await ws.send_text(json.dumps({"tipo": "error", "detalle": "JSON inválido"}))
                continue

            contenido       = str(data.get("contenido", "")).strip()
            destinatario_id = data.get("destinatario_id") or None
            padre_id        = data.get("padre_id") or None

            if not contenido:
                continue

            msg = _guardar_mensaje(
                proyecto_id     = proyecto_id,
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
                "remitente_nombre": nombre,
                "contenido":        contenido,
                "destinatario_id":  destinatario_id,
                "padre_id":         padre_id,
                "es_dm":            destinatario_id is not None,
                "fecha":            msg.fecha.isoformat(),
            }

            if destinatario_id:
                await manager.broadcast_dm(
                    proyecto_id     = proyecto_id,
                    remitente_id    = usuario_id,
                    destinatario_id = destinatario_id,
                    payload         = out_payload,
                )
            else:
                await manager.broadcast_proyecto(proyecto_id, out_payload)

    except WebSocketDisconnect:
        manager.desconectar(ws, proyecto_id, usuario_id)
