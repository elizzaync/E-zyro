"""
Asistente virtual (chatbot) de E-Zyro.

Arquitectura:
  - service.py : bucle agéntico de tool-use con el SDK de Anthropic.
  - tools.py   : herramientas read-only que consultan la BD, acotadas por
                 empresa_id (del JWT) y respetando RBAC.
  - prompt.py  : construcción del system prompt (con prompt caching).
  - config.py  : modelo, effort, límites y cliente Anthropic (lazy).

Punto de entrada público: `responder(db, payload, mensajes)`.
"""
from .service import responder

__all__ = ["responder"]
