"""
Router: /chatbot — proxy autenticado hacia el asistente IA externo.

La app móvil NO habla directo con el chatbot: este endpoint reenvía el mensaje
con la API key del servidor (CHATBOT_API_KEY, solo variable de entorno) y el
contexto del usuario actual. El function calling ocurre del lado del servidor
del chatbot; aquí solo se propaga {answer}. Ante cualquier fallo del chatbot se
responde 503 genérico: nunca se filtra la API key ni el traceback.

Nota: app/services/chatbot/ solo conserva __pycache__ (el fuente fue retirado);
no se reutiliza — esta integración es un proxy puro.
"""
from __future__ import annotations

import os
from typing import Optional

import requests
from fastapi import APIRouter, Depends, HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel

from ..core.security import security, verificar_token

router = APIRouter(prefix="/chatbot", tags=["chatbot"])

_CHATBOT_URL = "https://chatbot.mystic-byte.com/chat"
_TIMEOUT_SEGUNDOS = 60

_NO_DISPONIBLE = HTTPException(
    status_code=503,
    detail="El asistente no está disponible en este momento",
)


class ChatIn(BaseModel):
    message: str
    pantalla: Optional[str] = None


@router.post("/chat")
def chat(
    body: ChatIn,
    payload: dict = Depends(verificar_token),
    credentials: HTTPAuthorizationCredentials = Security(security),
):
    """Reenvía el mensaje al chatbot con la identidad del usuario actual."""
    api_key = os.getenv("CHATBOT_API_KEY", "")
    if not api_key:
        raise _NO_DISPONIBLE

    try:
        r = requests.post(
            _CHATBOT_URL,
            headers={"X-API-Key": api_key},
            json={
                "user_id": str(payload.get("id")),
                "message": body.message,
                "context": {
                    "jwt": credentials.credentials,
                    "rol": payload.get("rol"),
                    "pantalla": body.pantalla,
                },
            },
            timeout=_TIMEOUT_SEGUNDOS,
        )
    except requests.RequestException:
        raise _NO_DISPONIBLE

    if r.status_code != 200:
        raise _NO_DISPONIBLE

    try:
        answer = r.json().get("answer")
    except ValueError:
        raise _NO_DISPONIBLE
    if not isinstance(answer, str):
        raise _NO_DISPONIBLE

    return {"answer": answer}
