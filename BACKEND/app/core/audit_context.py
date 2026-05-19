"""
Contexto de auditoría por petición HTTP.

Propaga usuario_id, empresa_id e ip a través de ContextVars
para que el listener de SQLAlchemy los consuma sin acoplamiento.
"""
from __future__ import annotations

import os
from contextvars import ContextVar

from fastapi import Request
from jose import jwt, JWTError
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

_SECRET: str = os.getenv("SECRET_KEY", "")
_ALGO:   str = "HS256"

# ── Una ContextVar por dato de contexto ──────────────────────────────────────
_ctx_usuario_id: ContextVar[str | None] = ContextVar("audit_usuario_id", default=None)
_ctx_empresa_id: ContextVar[str | None] = ContextVar("audit_empresa_id", default=None)
_ctx_ip:         ContextVar[str | None] = ContextVar("audit_ip",         default=None)


def get_audit_context() -> dict[str, str | None]:
    """Devuelve el contexto de auditoría de la coroutine actual."""
    return {
        "usuario_id": _ctx_usuario_id.get(),
        "empresa_id": _ctx_empresa_id.get(),
        "ip":         _ctx_ip.get(),
    }


# ── Utilidad interna ──────────────────────────────────────────────────────────

def _claims_from_token(token: str) -> dict:
    """Decodifica el JWT silenciosamente; retorna {} si falla."""
    try:
        return jwt.decode(token, _SECRET, algorithms=[_ALGO])
    except JWTError:
        return {}


# ── Middleware ────────────────────────────────────────────────────────────────

class AuditContextMiddleware(BaseHTTPMiddleware):
    """
    Intercepta cada request HTTP, extrae las claims JWT y las fija
    en ContextVars para que el listener de SQLAlchemy las consuma.

    Soporta:
    - Authorization: Bearer <token>   (HTTP normal)
    - ?token=<jwt>                    (WebSocket)
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        claims: dict = {}

        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            claims = _claims_from_token(auth.removeprefix("Bearer ").strip())

        if not claims:
            claims = _claims_from_token(request.query_params.get("token", ""))

        ip = request.client.host if request.client else None

        tok_u = _ctx_usuario_id.set(claims.get("id"))
        tok_e = _ctx_empresa_id.set(claims.get("empresa_id"))
        tok_i = _ctx_ip.set(ip)

        try:
            return await call_next(request)
        finally:
            _ctx_usuario_id.reset(tok_u)
            _ctx_empresa_id.reset(tok_e)
            _ctx_ip.reset(tok_i)
