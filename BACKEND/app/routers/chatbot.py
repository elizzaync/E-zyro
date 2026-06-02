"""
Router: /chatbot — asistente virtual con tool-use sobre los datos de la empresa.
Lectura/consulta: cualquier usuario autenticado (las herramientas internas
aplican RBAC donde corresponde, p. ej. personal).
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..schemas.chatbot import ChatMensajeIn, ChatRespuestaOut
from ..services.chatbot import responder

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/chatbot", tags=["chatbot"])


@router.post("/mensaje", response_model=ChatRespuestaOut)
def enviar_mensaje(
    body: ChatMensajeIn,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    try:
        return responder(db, payload, [m.model_dump() for m in body.mensajes])
    except RuntimeError as e:
        # API key no configurada u otra condición de servicio
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:  # noqa: BLE001
        logger.exception("Error en chatbot")
        raise HTTPException(status_code=500, detail=f"Error del asistente: {e}")
