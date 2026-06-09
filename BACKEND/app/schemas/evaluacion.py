"""Schemas de Evaluaciones de desempeño (Punto 3.2)."""
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, field_validator


# ── Criterios ────────────────────────────────────────────────────────────────
class CriterioIn(BaseModel):
    nombre:      str
    descripcion: Optional[str] = None
    peso:        float = 1.0

    @field_validator("peso")
    @classmethod
    def _peso_pos(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("peso debe ser > 0")
        return v


class CriterioOut(BaseModel):
    id:          str
    nombre:      str
    descripcion: Optional[str] = None
    peso:        float
    activo:      bool = True


# ── Detalle (puntaje por criterio) ───────────────────────────────────────────
class DetalleIn(BaseModel):
    criterio_id: str
    puntaje:     int
    comentario:  Optional[str] = None

    @field_validator("puntaje")
    @classmethod
    def _rango(cls, v: int) -> int:
        if not (1 <= v <= 10):
            raise ValueError("puntaje debe estar entre 1 y 10")
        return v


class DetalleOut(BaseModel):
    id:             str
    criterio_id:    str
    criterio_nombre: Optional[str] = None
    peso:           Optional[float] = None
    puntaje:        int
    comentario:     Optional[str] = None


# ── Evaluación ───────────────────────────────────────────────────────────────
class EvaluacionIn(BaseModel):
    empleado_id:  str
    periodo:      str
    fecha:        Optional[str] = None       # ISO; default hoy
    detalles:     List[DetalleIn] = []


class EvaluacionOut(BaseModel):
    id:               str
    empleado_id:      str
    empleado_nombre:  Optional[str] = None
    evaluador_id:     str
    evaluador_nombre: Optional[str] = None
    periodo:          str
    estado:           str
    fecha:            Optional[str] = None
    promedio:         Optional[float] = None   # promedio ponderado por peso
    detalles:         List[DetalleOut] = []


class EstadoUpdate(BaseModel):
    estado: str                                # enviada|completada

    @field_validator("estado")
    @classmethod
    def _valido(cls, v: str) -> str:
        if v not in ("enviada", "completada"):
            raise ValueError("estado debe ser 'enviada' o 'completada'")
        return v
