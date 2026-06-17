"""
Router: WebSocket de sesiones en tiempo real.

Endpoint: /ws/sesiones?token=<JWT>

Sirve dos eventos que el cliente debe escuchar:
- {"tipo": "nuevo_dispositivo", "dispositivo": "...", "ip": "...", "sesion_id": "...", "fecha": "..."}
    Llega a las sesiones YA abiertas cuando otro equipo inicia sesión.
- {"tipo": "sesion_cerrada"}
    Llega a la sesión que fue cerrada remotamente → el cliente fuerza logout.
    Tras enviarlo, el servidor cierra el socket con code 4002.

Autenticación: misma que chat_ws (token JWT por query param). No exponemos datos
sensibles por el canal; solo descripción del dispositivo e IP.
"""
from __future__ import annotations

import hashlib
import json
import os

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import jwt, JWTError

from ..core.session_events import manager

router = APIRouter(tags=["session-ws"])

_SECRET_KEY = os.getenv("SECRET_KEY", "")
_ALGORITHM = "HS256"


def _decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
    except JWTError:
        return None


@router.websocket("/ws/sesiones")
async def ws_sesiones(ws: WebSocket, token: str = ""):
    payload = _decode_token(token)
    if payload is None or not payload.get("id"):
        await ws.accept()
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Token inválido"}))
        await ws.close(code=4001)
        return

    usuario_id = str(payload["id"])
    token_hash = hashlib.sha256(token.encode()).hexdigest()

    manager.capturar_loop()
    await manager.conectar(ws, usuario_id, token_hash)

    try:
        # El canal es de servidor→cliente. Mantenemos vivo el socket leyendo
        # (y descartando) lo que llegue, incl. pings del cliente.
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        manager.desconectar(ws, usuario_id, token_hash)
    except Exception:
        manager.desconectar(ws, usuario_id, token_hash)
