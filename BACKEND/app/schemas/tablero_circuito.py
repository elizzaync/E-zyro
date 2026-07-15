from __future__ import annotations
from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class CircuitoIn(BaseModel):
    circuito:      str
    tipo_circuito: Optional[str] = "ITM"   # IG|ID|ITM
    capacidad_itm: Optional[str] = None
    descripcion:   Optional[str] = None
    orden:         Optional[int] = None


class CircuitoOut(BaseModel):
    id:                    str
    equipo_intervenido_id: str
    circuito:              str
    tipo_circuito:         str
    capacidad_itm:         Optional[str] = None
    descripcion:           Optional[str] = None
    orden:                 int
    created_at:            datetime

    class Config:
        from_attributes = True
