"""
Router: /chatbot — proxy autenticado hacia el asistente IA externo (E-Zybot).

La app móvil NO habla directo con el chatbot: este endpoint reenvía el mensaje
con la API key del servidor (CHATBOT_API_KEY, solo variable de entorno) y el
contexto del usuario actual (jwt, rol, nombre, permisos, pantalla). El function
calling ocurre del lado del servidor del chatbot; aquí se propagan `answer` y
las `acciones` estructuradas (p. ej. navegar) que la app ejecuta localmente.
Ante cualquier fallo del chatbot se responde 503 genérico: nunca se filtra la
API key ni el traceback (el motivo se loggea solo del lado del servidor).

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
from sqlalchemy.orm import Session

from ..core.security import security, verificar_token
from ..db.database import get_db
from ..models.usuario import Usuario

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
    # Catálogo de pantallas que la app sabe abrir para este usuario
    # ([{clave, nombre, descripcion}], ya filtrado por permisos del lado de la
    # app). Se reenvía al chatbot para que el LLM conozca el universo válido
    # de la acción `abrir_pantalla` sin redeployar su servidor.
    pantallas: Optional[list[dict]] = None


def _nombre_y_permisos(db: Session, usuario_id: str) -> tuple[str, list[str]]:
    """Nombre completo + lista de permisos del usuario. Si la consulta falla,
    devuelve valores vacíos: el chat no debe caerse por esto."""
    try:
        u = db.query(Usuario).filter(Usuario.id == usuario_id).first()
        nombre = f"{u.nombre} {u.apellido}".strip() if u else ""
        from .auth import _rol_y_permisos  # fuente única (login y /auth/me)
        _, permisos = _rol_y_permisos(db, usuario_id)
        return nombre, permisos
    except Exception:
        return "", []


@router.post("/chat")
def chat(
    body: ChatIn,
    payload: dict = Depends(verificar_token),
    credentials: HTTPAuthorizationCredentials = Security(security),
    db: Session = Depends(get_db),
):
    """Reenvía el mensaje al chatbot con la identidad del usuario actual."""
    api_key = os.getenv("CHATBOT_API_KEY", "")
    if not api_key:
        print("[chatbot] CHATBOT_API_KEY no configurada")
        raise _NO_DISPONIBLE

    nombre, permisos = _nombre_y_permisos(db, str(payload.get("id")))

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
                    "nombre": nombre,
                    "permisos": permisos,
                    "pantalla": body.pantalla,
                    "pantallas": body.pantallas or [],
                },
            },
            timeout=_TIMEOUT_SEGUNDOS,
        )
    except requests.RequestException as e:
        print(f"[chatbot] upstream inaccesible: {type(e).__name__}")
        raise _NO_DISPONIBLE

    if r.status_code != 200:
        print(f"[chatbot] upstream respondió status={r.status_code}")
        raise _NO_DISPONIBLE

    try:
        data = r.json()
        answer = data.get("answer")
    except ValueError:
        print("[chatbot] upstream devolvió JSON inválido")
        raise _NO_DISPONIBLE
    if not isinstance(answer, str):
        print("[chatbot] upstream sin campo 'answer' string")
        raise _NO_DISPONIBLE

    # Acciones estructuradas (p. ej. {tipo:'navegar', pantalla:'compras'}):
    # se propagan tal cual; la app decide si sabe ejecutarlas.
    acciones = data.get("acciones")
    if not isinstance(acciones, list):
        acciones = []

    return {"answer": answer, "acciones": acciones}
