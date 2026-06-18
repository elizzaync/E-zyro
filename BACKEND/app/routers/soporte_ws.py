"""
WebSocket de Soporte TIC en tiempo real.
Endpoint: /ws/soporte?token=<JWT>

Eventos emitidos a todos los usuarios TI de la misma empresa:
  - ticket_nuevo         → nuevo ticket creado
  - ticket_actualizado   → ticket cambió estado/respuesta
  - sesion_nueva         → nuevo login en la empresa
  - sesion_cerrada       → sesión cerrada remotamente
  - ip_bloqueada         → IP agregada a blocklist
  - ip_desbloqueada      → IP removida de blocklist
  - auditoria_nueva      → nuevo registro de auditoría
  - dispositivos_cambio  → cambio en sesiones activas
"""
from __future__ import annotations

import asyncio
import json
import os
import threading
from typing import Dict, List, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import jwt, JWTError

router = APIRouter(tags=["soporte-ws"])

_SECRET_KEY = os.getenv("SECRET_KEY", "")
_ALGORITHM = "HS256"


def _decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
    except JWTError:
        return None


class SoporteEventManager:
    """Manager de conexiones WebSocket para el módulo Soporte TIC.

    Las conexiones se agrupan por empresa_id. Cuando ocurre un evento
    relevante (ticket creado, IP bloqueada, etc.) se emite a todos los
    sockets de esa empresa.

    Thread-safety: igual que SessionEventManager — los endpoints HTTP
    síncronos (threadpool) llaman a emit(), que usa
    asyncio.run_coroutine_threadsafe con el loop capturado en conectar().
    """

    def __init__(self) -> None:
        # empresa_id → lista de WebSockets conectados
        self._conns: Dict[str, List[WebSocket]] = {}
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._lock = threading.Lock()

    # ── Ciclo de vida ─────────────────────────────────────────────────────────

    def capturar_loop(self) -> None:
        """Guarda el event loop activo (idempotente). Llamado por el endpoint WS."""
        try:
            self._loop = asyncio.get_running_loop()
        except RuntimeError:
            pass

    async def conectar(self, ws: WebSocket, empresa_id: str) -> None:
        await ws.accept()
        with self._lock:
            self._conns.setdefault(empresa_id, []).append(ws)

    def desconectar(self, ws: WebSocket, empresa_id: str) -> None:
        with self._lock:
            sockets = self._conns.get(empresa_id, [])
            if ws in sockets:
                sockets.remove(ws)
            if not sockets:
                self._conns.pop(empresa_id, None)

    # ── Envío interno (corre en el event loop) ───────────────────────────────

    async def _broadcast(self, empresa_id: str, payload: dict) -> None:
        with self._lock:
            sockets = list(self._conns.get(empresa_id, []))
        text = json.dumps(payload, default=str, ensure_ascii=False)
        for ws in sockets:
            try:
                await ws.send_text(text)
            except Exception:
                pass

    # ── API thread-safe para endpoints síncronos ─────────────────────────────

    def emit(self, empresa_id: str, payload: dict) -> None:
        """Emite un evento a todos los clientes WS de la empresa (thread-safe)."""
        coro = self._broadcast(empresa_id, payload)
        loop = self._loop
        if loop is None:
            coro.close()
            return
        try:
            asyncio.run_coroutine_threadsafe(coro, loop)
        except Exception:
            try:
                coro.close()
            except Exception:
                pass


# Singleton compartido con soporte.py y auth.py
soporte_manager = SoporteEventManager()


# ── Endpoint WebSocket ───────────────────────────────────────────────────────

@router.websocket("/ws/soporte")
async def ws_soporte(ws: WebSocket, token: str = ""):
    payload = _decode_token(token)
    if payload is None or not payload.get("id"):
        await ws.accept()
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Token inválido"}))
        await ws.close(code=4001)
        return

    empresa_id = str(payload.get("empresa_id", ""))
    if not empresa_id:
        await ws.accept()
        await ws.send_text(json.dumps({"tipo": "error", "detalle": "Sin empresa en el token"}))
        await ws.close(code=4001)
        return

    # Verificar que el usuario tenga permiso de soporte (rol o permiso)
    rol = (payload.get("rol") or "").lower().replace(" ", "")
    roles_ti = {"administrador", "admin", "superadmin", "ti"}
    tiene_rol = any(r in rol for r in roles_ti)

    # Comprobar permiso en BD si no tiene rol privilegiado
    if not tiene_rol:
        from ..db.database import SessionLocal
        from ..core.permisos import tiene_permiso as _tiene_permiso
        db = SessionLocal()
        try:
            autorizado = _tiene_permiso(db, payload, "soporte", "gestionar")
        except Exception:
            autorizado = False
        finally:
            db.close()
        if not autorizado:
            await ws.accept()
            await ws.send_text(json.dumps({"tipo": "error", "detalle": "Sin permiso de soporte"}))
            await ws.close(code=4001)
            return

    soporte_manager.capturar_loop()
    await soporte_manager.conectar(ws, empresa_id)

    try:
        # Canal servidor→cliente. Descartamos cualquier mensaje del cliente.
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        soporte_manager.desconectar(ws, empresa_id)
    except Exception:
        soporte_manager.desconectar(ws, empresa_id)
