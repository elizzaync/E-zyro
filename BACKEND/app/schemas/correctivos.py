"""Schemas de Correctivos + Observaciones (Fase 4)."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel

ESTADOS_CORRECTIVO = {"registrado", "en_proceso", "en_revision", "aprobado", "desaprobado", "finalizado", "anulado"}
# Transiciones permitidas (origen -> destinos)
TRANSICIONES = {
    "registrado":  {"en_proceso", "anulado"},
    "en_proceso":  {"en_revision", "anulado"},
    "en_revision": {"aprobado", "desaprobado", "anulado"},
    "desaprobado": {"en_proceso", "anulado"},
    "aprobado":    {"finalizado", "anulado"},
}


class CorrectivoIn(BaseModel):
    servicio_id:  str
    alcance:      Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin:    Optional[str] = None


class CorrectivoOut(BaseModel):
    id:           str
    servicio_id:  str
    codigo:       Optional[str] = None
    alcance:      Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin:    Optional[str] = None
    estado:       str
    informe_url:  Optional[str] = None


class TransicionIn(BaseModel):
    nuevo_estado: str  # debe respetar TRANSICIONES


class InformeIn(BaseModel):
    archivo_base64: str


class ObservacionIn(BaseModel):
    observaciones:   Optional[str] = None
    recomendaciones: Optional[str] = None
    correctivo_id:   Optional[str] = None


class ObservacionOut(BaseModel):
    id:              str
    servicio_id:     str
    correctivo_id:   Optional[str] = None
    observaciones:   Optional[str] = None
    recomendaciones: Optional[str] = None
    fecha_descargo:  Optional[str] = None
