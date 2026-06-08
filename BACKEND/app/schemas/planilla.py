"""Schemas del módulo de planilla (Fase 8)."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator

TIPOS_CONCEPTO = {"ingreso", "descuento", "aporte_empleador"}


class ConceptoCreate(BaseModel):
    codigo: str
    nombre: str
    tipo: str
    monto_referencial: Optional[Decimal] = None
    formula_referencial: Optional[str] = None
    cuenta_contable_id: Optional[str] = None

    @field_validator("tipo")
    @classmethod
    def _tipo(cls, v: str) -> str:
        if v not in TIPOS_CONCEPTO:
            raise ValueError(f"tipo debe ser uno de {sorted(TIPOS_CONCEPTO)}")
        return v


class ConceptoOut(BaseModel):
    id: str
    codigo: str
    nombre: str
    tipo: str
    monto_referencial: Optional[Decimal] = None
    activo: bool


class PlanillaOut(BaseModel):
    id: str
    periodo_id: str
    fecha_proceso: date
    estado: str
    total_ingresos: Decimal
    total_descuentos: Decimal
    total_aportes: Decimal
    total_neto: Decimal
    asiento_provision_id: Optional[str] = None
    asiento_pago_id: Optional[str] = None


class BoletaDetalleOut(BaseModel):
    concepto_id: str
    monto: Decimal


class BoletaOut(BaseModel):
    id: str
    empleado_id: str
    total_ingresos: Decimal
    total_descuentos: Decimal
    total_aportes: Decimal
    total_neto: Decimal
    detalles: List[BoletaDetalleOut]
