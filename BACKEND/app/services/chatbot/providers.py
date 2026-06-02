"""
Proveedores de LLM. Cada función ejecuta el bucle agéntico completo (pensar →
llamar herramientas → reinyectar resultados → repetir) en el formato nativo de
su API, y devuelve el mismo dict normalizado:

    {"respuesta": str, "herramientas_usadas": [...], "stop_reason": str}

Comparten las mismas herramientas (`TOOL_DEFS` / `ejecutar_tool`), el mismo RBAC
y el mismo aislamiento por empresa. Cambiar de proveedor NO cambia las consultas.
"""
from __future__ import annotations

import json
import logging

from sqlalchemy.orm import Session

from . import config as cfg
from .tools import TOOL_DEFS, ejecutar_tool

logger = logging.getLogger(__name__)


# ─────────────────────────── PROVEEDOR LOCAL (Ollama) ───────────────────────

def _tools_openai() -> list[dict]:
    """Convierte TOOL_DEFS (formato Anthropic) al formato function-calling de OpenAI."""
    return [
        {
            "type": "function",
            "function": {
                "name": t["name"],
                "description": t["description"],
                "parameters": t["input_schema"],
            },
        }
        for t in TOOL_DEFS
    ]


def run_local(db: Session, payload: dict, system_text: str, historial: list[dict]) -> dict:
    client = cfg.get_local_client()
    tools = _tools_openai()

    mensajes = [{"role": "system", "content": system_text}, *historial]
    herramientas_usadas: list[dict] = []

    for _ in range(cfg.CHATBOT_MAX_ITERACIONES):
        resp = client.chat.completions.create(
            model=cfg.OLLAMA_MODEL,
            messages=mensajes,
            tools=tools,
            tool_choice="auto",
            temperature=cfg.CHATBOT_TEMPERATURE,
            max_tokens=cfg.CHATBOT_MAX_TOKENS,
        )
        msg = resp.choices[0].message
        tool_calls = getattr(msg, "tool_calls", None)

        if tool_calls:
            # Reinyectar el turno del asistente con sus tool_calls
            mensajes.append(
                {
                    "role": "assistant",
                    "content": msg.content or "",
                    "tool_calls": [
                        {
                            "id": tc.id,
                            "type": "function",
                            "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                        }
                        for tc in tool_calls
                    ],
                }
            )
            for tc in tool_calls:
                try:
                    args = json.loads(tc.function.arguments or "{}")
                except json.JSONDecodeError:
                    args = {}
                herramientas_usadas.append({"nombre": tc.function.name, "args": args})
                salida = ejecutar_tool(db, payload, tc.function.name, args)
                mensajes.append({"role": "tool", "tool_call_id": tc.id, "content": salida})
            continue

        texto = (msg.content or "").strip() or "No obtuve una respuesta. Reformula tu pregunta."
        return {
            "respuesta": texto,
            "herramientas_usadas": herramientas_usadas,
            "stop_reason": resp.choices[0].finish_reason or "stop",
        }

    return {
        "respuesta": "La consulta resultó demasiado compleja. Divídela en preguntas más simples.",
        "herramientas_usadas": herramientas_usadas,
        "stop_reason": "max_iteraciones",
    }


# ─────────────────────────── PROVEEDOR CLAUDE (respaldo) ─────────────────────

def run_claude(db: Session, payload: dict, system_blocks: list[dict], historial: list[dict]) -> dict:
    client = cfg.get_anthropic_client()

    kwargs: dict = {
        "model": cfg.CHATBOT_MODEL,
        "max_tokens": max(cfg.CHATBOT_MAX_TOKENS, 4096),
        "system": system_blocks,
        "tools": TOOL_DEFS,
        "messages": list(historial),
    }
    if cfg.CHATBOT_THINKING == "adaptive":
        kwargs["thinking"] = {"type": "adaptive"}
        kwargs["output_config"] = {"effort": cfg.CHATBOT_EFFORT}

    herramientas_usadas: list[dict] = []

    for _ in range(cfg.CHATBOT_MAX_ITERACIONES):
        resp = client.messages.create(**kwargs)

        if resp.stop_reason == "tool_use":
            kwargs["messages"].append({"role": "assistant", "content": resp.content})
            resultados = []
            for bloque in resp.content:
                if bloque.type == "tool_use":
                    herramientas_usadas.append({"nombre": bloque.name, "args": bloque.input})
                    salida = ejecutar_tool(db, payload, bloque.name, bloque.input)
                    resultados.append(
                        {"type": "tool_result", "tool_use_id": bloque.id, "content": salida}
                    )
            kwargs["messages"].append({"role": "user", "content": resultados})
            continue

        texto = "".join(b.text for b in resp.content if b.type == "text").strip()
        if resp.stop_reason == "refusal":
            texto = texto or "No puedo ayudar con esa solicitud."
        elif not texto:
            texto = "No obtuve una respuesta. Reformula tu pregunta, por favor."
        return {
            "respuesta": texto,
            "herramientas_usadas": herramientas_usadas,
            "stop_reason": resp.stop_reason,
        }

    return {
        "respuesta": "La consulta resultó demasiado compleja. Divídela en preguntas más simples.",
        "herramientas_usadas": herramientas_usadas,
        "stop_reason": "max_iteraciones",
    }
