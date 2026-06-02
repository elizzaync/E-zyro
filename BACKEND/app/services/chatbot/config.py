"""
Configuración del chatbot. Todo es ajustable por variables de entorno para poder
iterar (proveedor, modelo, effort, límites) sin tocar código.

Proveedor:
  CHATBOT_PROVIDER=local   → Ollama en tu PC (Qwen2.5). Por defecto.
  CHATBOT_PROVIDER=claude  → Claude API (respaldo / validación).
"""
import os
from functools import lru_cache

from dotenv import load_dotenv

load_dotenv()

# ── Selección de proveedor ───────────────────────────────────────────────────
CHATBOT_PROVIDER = os.getenv("CHATBOT_PROVIDER", "local").lower().strip()

# ── IA local (Ollama, API compatible con OpenAI) ─────────────────────────────
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434/v1")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:7b-instruct")
# Ollama no exige API key, pero el SDK de OpenAI requiere un string no vacío.
OLLAMA_API_KEY = os.getenv("OLLAMA_API_KEY", "ollama")

# ── Claude (respaldo) ─────────────────────────────────────────────────────────
CHATBOT_MODEL = os.getenv("CHATBOT_MODEL", "claude-opus-4-8")
CHATBOT_EFFORT = os.getenv("CHATBOT_EFFORT", "medium")     # low|medium|high|max
CHATBOT_THINKING = os.getenv("CHATBOT_THINKING", "adaptive")  # adaptive|disabled

# ── Comunes ───────────────────────────────────────────────────────────────────
CHATBOT_MAX_TOKENS = int(os.getenv("CHATBOT_MAX_TOKENS", "2048"))
CHATBOT_MAX_ITERACIONES = int(os.getenv("CHATBOT_MAX_ITERACIONES", "8"))
# Temperatura para el modelo local (Claude no la usa en 4.7/4.8).
CHATBOT_TEMPERATURE = float(os.getenv("CHATBOT_TEMPERATURE", "0.3"))


@lru_cache(maxsize=1)
def get_anthropic_client():
    """Cliente Claude perezoso (solo si CHATBOT_PROVIDER=claude)."""
    import anthropic

    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY no configurada. Añádela al .env o usa CHATBOT_PROVIDER=local."
        )
    return anthropic.Anthropic(api_key=api_key)


@lru_cache(maxsize=1)
def get_local_client():
    """Cliente OpenAI-compatible apuntando a Ollama (CHATBOT_PROVIDER=local)."""
    from openai import OpenAI

    return OpenAI(base_url=OLLAMA_BASE_URL, api_key=OLLAMA_API_KEY)
