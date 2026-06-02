from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class MensajeChat(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatMensajeIn(BaseModel):
    # Historial completo de la conversación (la API es stateless).
    mensajes: list[MensajeChat] = Field(..., min_length=1)


class HerramientaUsada(BaseModel):
    nombre: str
    args: dict = {}


class ChatRespuestaOut(BaseModel):
    respuesta: str
    herramientas_usadas: list[HerramientaUsada] = []
    stop_reason: str | None = None
