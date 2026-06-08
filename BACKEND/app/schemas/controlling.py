"""Schemas del módulo de controlling / centros de costo (Fase 2)."""
from __future__ import annotations

from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, field_validator

TIPOS_REFERENCIA = {"proyecto", "area", "empleado", "libre"}


class CentroCostoCreate(BaseModel):
    codigo: str
    nombre: str
    tipo_referencia: str = "libre"
    referencia_id: Optional[str] = None
    presupuesto_referencial: Optional[Decimal] = None

    @field_validator("tipo_referencia")
    @classmethod
    def _tipo_valido(cls, v: str) -> str:
        if v not in TIPOS_REFERENCIA:
            raise ValueError(f"tipo_referencia debe ser uno de {sorted(TIPOS_REFERENCIA)}")
        return v

    @field_validator("presupuesto_referencial")
    @classmethod
    def _presupuesto_no_negativo(cls, v: Optional[Decimal]) -> Optional[Decimal]:
        if v is not None and v < 0:
            raise ValueError("el presupuesto no puede ser negativo")
        return v


class CentroCostoUpdate(BaseModel):
    nombre: Optional[str] = None
    tipo_referencia: Optional[str] = None
    referencia_id: Optional[str] = None
    presupuesto_referencial: Optional[Decimal] = None
    activo: Optional[bool] = None

    @field_validator("tipo_referencia")
    @classmethod
    def _tipo_valido(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_REFERENCIA:
            raise ValueError(f"tipo_referencia debe ser uno de {sorted(TIPOS_REFERENCIA)}")
        return v


class CentroCostoOut(BaseModel):
    id: str
    codigo: str
    nombre: str
    tipo_referencia: str
    referencia_id: Optional[str] = None
    presupuesto_referencial: Optional[Decimal] = None
    activo: bool


class CostoRealOut(BaseModel):
    centro_costo_id: str
    total_debito: Decimal
    total_credito: Decimal
    costo_real: Decimal


class ComparativoOut(BaseModel):
    centro_costo_id: str
    codigo: str
    nombre: str
    presupuesto_referencial: Optional[Decimal] = None
    costo_real: Decimal
    desviacion: Optional[Decimal] = None
    ejecucion_pct: Optional[Decimal] = None
