"""Schemas del módulo de activos fijos (Fase 7)."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, field_validator, model_validator


class ActivoFijoCreate(BaseModel):
    nombre: str
    fecha_adquisicion: date
    valor_adquisicion: Decimal
    vida_util_meses: int
    valor_residual: Decimal = Decimal("0.00")
    fecha_inicio_depreciacion: Optional[date] = None
    equipo_id: Optional[str] = None
    centro_costo_id: Optional[str] = None

    @field_validator("vida_util_meses")
    @classmethod
    def _vida_pos(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("la vida útil debe ser mayor que 0 meses")
        return v

    @model_validator(mode="after")
    def _coherencia(self) -> "ActivoFijoCreate":
        if self.valor_adquisicion < 0 or self.valor_residual < 0:
            raise ValueError("los valores no pueden ser negativos")
        if self.valor_residual > self.valor_adquisicion:
            raise ValueError("el valor residual no puede superar el valor de adquisición")
        return self


class ActivoFijoUpdate(BaseModel):
    nombre: Optional[str] = None
    valor_residual: Optional[Decimal] = None
    centro_costo_id: Optional[str] = None


class ActivoFijoOut(BaseModel):
    id: str
    nombre: str
    equipo_id: Optional[str] = None
    fecha_adquisicion: date
    valor_adquisicion: Decimal
    valor_residual: Decimal
    vida_util_meses: int
    metodo_depreciacion: str
    fecha_inicio_depreciacion: date
    estado: str
    centro_costo_id: Optional[str] = None
    depreciacion_acumulada: Decimal
    valor_en_libros: Decimal


class DepreciacionFilaOut(BaseModel):
    periodo_id: str
    monto_depreciado: Decimal
    valor_en_libros_resultante: Decimal
    asiento_id: Optional[str] = None


class ProcesarDepreciacionOut(BaseModel):
    procesados: int
    omitidos: int
    total_depreciado: Decimal
