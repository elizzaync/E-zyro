"""
Punto de entrada del chatbot. Normaliza el historial, construye el system prompt
y despacha al proveedor configurado (local Ollama / Claude).

La API es stateless: el cliente (app) envía el historial completo en cada turno.
"""
from __future__ import annotations

import logging

from sqlalchemy.orm import Session

from . import config as cfg
from . import providers
from .prompt import construir_system

logger = logging.getLogger(__name__)

_ROLES_VALIDOS = {"user", "assistant"}


def _normalizar(mensajes: list[dict]) -> list[dict]:
    out: list[dict] = []
    for m in mensajes:
        role = (m.get("role") or "").strip()
        content = m.get("content")
        if role in _ROLES_VALIDOS and isinstance(content, str) and content.strip():
            out.append({"role": role, "content": content})
    if out and out[0]["role"] != "user":
        out = [{"role": "user", "content": "Hola"}, *out]
    return out


def responder(db: Session, payload: dict, mensajes: list[dict]) -> dict:
    historial = _normalizar(mensajes)
    if not historial:
        return {
            "respuesta": "¿En qué puedo ayudarte? Puedo consultar inventario, equipos, "
            "EPP, proyectos, clientes y más.",
            "herramientas_usadas": [],
            "stop_reason": "sin_mensaje",
        }

    system_blocks = construir_system(db, payload)

    if cfg.CHATBOT_PROVIDER == "claude":
        return providers.run_claude(db, payload, system_blocks, historial)

    # local (por defecto): el system va como texto plano
    system_text = system_blocks[0]["text"]
    return providers.run_local(db, payload, system_text, historial)
