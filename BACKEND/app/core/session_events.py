"""
Bus de eventos de sesión en tiempo real (WebSocket).

Permite que los endpoints HTTP (síncronos) de `auth.py` notifiquen al instante
a los dispositivos conectados:

- `nuevo_dispositivo`: se inició sesión en la cuenta desde otro equipo → se avisa
  a las sesiones YA existentes del usuario (con dispositivo + IP del nuevo).
- `sesion_cerrada`: una sesión fue cerrada (logout remoto / "cerrar todas") →
  se avisa a ESA sesión y se cierra su socket para forzar el logout.

Detalle técnico
---------------
Los endpoints de FastAPI declarados con `def` (no `async`) corren en un
threadpool, fuera del event loop. El WebSocket corre en el event loop. Para
emitir desde el threadpool hacia los sockets capturamos el loop una vez (cuando
se conecta el primer WS) y usamos `asyncio.run_coroutine_threadsafe`.

Multi-worker: el manager es por proceso, igual que `chat_ws`. La seguridad real
de expulsión NO depende de este bus (la garantiza `session_cache` +
`verificar_token`); esto es solo la capa de UX instantánea.
"""
from __future__ import annotations

import asyncio
import json
import threading
from typing import Dict, List, Optional

from fastapi import WebSocket


class SessionEventManager:
    def __init__(self) -> None:
        # usuario_id -> { token_hash -> [WebSocket, ...] }
        self._conns: Dict[str, Dict[str, List[WebSocket]]] = {}
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._lock = threading.Lock()

    # ── Ciclo de vida de la conexión (corre en el event loop) ────────────────

    def capturar_loop(self) -> None:
        """Guarda el event loop en ejecución (idempotente). Lo llama el endpoint
        WS al conectar, garantizando que si hay sockets, hay loop."""
        try:
            self._loop = asyncio.get_running_loop()
        except RuntimeError:
            pass

    async def conectar(self, ws: WebSocket, usuario_id: str, token_hash: str) -> None:
        await ws.accept()
        with self._lock:
            self._conns.setdefault(usuario_id, {}).setdefault(token_hash, []).append(ws)

    def desconectar(self, ws: WebSocket, usuario_id: str, token_hash: str) -> None:
        with self._lock:
            sockets = self._conns.get(usuario_id, {}).get(token_hash, [])
            if ws in sockets:
                sockets.remove(ws)
            if not sockets:
                self._conns.get(usuario_id, {}).pop(token_hash, None)
            if not self._conns.get(usuario_id):
                self._conns.pop(usuario_id, None)

    # ── Envío (corre en el event loop) ───────────────────────────────────────

    async def _enviar(self, ws: WebSocket, payload: dict) -> None:
        try:
            await ws.send_text(json.dumps(payload, default=str, ensure_ascii=False))
        except Exception:
            pass

    async def _emitir_a_usuario(
        self, usuario_id: str, payload: dict, excluir_token_hash: Optional[str]
    ) -> None:
        with self._lock:
            buckets = [
                (th, list(socks))
                for th, socks in self._conns.get(usuario_id, {}).items()
            ]
        for token_hash, sockets in buckets:
            if excluir_token_hash and token_hash == excluir_token_hash:
                continue
            for ws in sockets:
                await self._enviar(ws, payload)

    async def _emitir_a_sesion(self, usuario_id: str, token_hash: str, payload: dict) -> None:
        with self._lock:
            sockets = list(self._conns.get(usuario_id, {}).get(token_hash, []))
        for ws in sockets:
            await self._enviar(ws, payload)
        # Tras avisar, cerramos el socket para que el cliente no quede colgado.
        for ws in sockets:
            try:
                await ws.close(code=4002)
            except Exception:
                pass

    async def _emitir_y_cerrar_usuario(self, usuario_id: str, payload: dict) -> None:
        """Emite `payload` a TODAS las sesiones del usuario y cierra cada socket.
        Base del cierre forzado por administrador (afecta a todos los equipos)."""
        with self._lock:
            sockets = [
                ws
                for socks in self._conns.get(usuario_id, {}).values()
                for ws in socks
            ]
        for ws in sockets:
            await self._enviar(ws, payload)
        for ws in sockets:
            try:
                await ws.close(code=4002)
            except Exception:
                pass

    # ── API thread-safe para endpoints síncronos ─────────────────────────────

    def notificar_nuevo_dispositivo(
        self, usuario_id: str, info: dict, excluir_token_hash: Optional[str] = None
    ) -> None:
        payload = {"tipo": "nuevo_dispositivo", **info}
        self._lanzar(self._emitir_a_usuario(usuario_id, payload, excluir_token_hash))

    def notificar_sesion_cerrada(self, usuario_id: str, token_hash: str) -> None:
        payload = {"tipo": "sesion_cerrada"}
        self._lanzar(self._emitir_a_sesion(usuario_id, token_hash, payload))

    def notificar_cierre_forzado(self, usuario_id: str, motivo: Optional[str] = None) -> None:
        """Cierre forzado por un administrador: avisa a TODAS las sesiones del
        usuario (con motivo opcional) para que muestren el modal y se deslogueen."""
        payload = {"tipo": "cierre_forzado", "motivo": (motivo or "").strip() or None}
        self._lanzar(self._emitir_y_cerrar_usuario(usuario_id, payload))

    def _lanzar(self, coro) -> None:
        loop = self._loop
        if loop is None:
            # Nadie conectado por WS en este proceso → nada que notificar.
            coro.close()
            return
        try:
            asyncio.run_coroutine_threadsafe(coro, loop)
        except Exception:
            try:
                coro.close()
            except Exception:
                pass


manager = SessionEventManager()
