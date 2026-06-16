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
    es_base: bool = False   # concepto base (sueldo) → valor día = monto/30

    @field_validator("tipo")
    @classmethod
    def _tipo(cls, v: str) -> str:
        if v not in TIPOS_CONCEPTO:
            raise ValueError(f"tipo debe ser uno de {sorted(TIPOS_CONCEPTO)}")
        return v


class ConceptoUpdate(BaseModel):
    """Actualización parcial de un concepto (p. ej. marcarlo como base)."""
    nombre: Optional[str] = None
    monto_referencial: Optional[Decimal] = None
    activo: Optional[bool] = None
    es_base: Optional[bool] = None


class ConceptoOut(BaseModel):
    id: str
    codigo: str
    nombre: str
    tipo: str
    monto_referencial: Optional[Decimal] = None
    activo: bool
    es_base: bool = False


class BoletaDetalleUpdate(BaseModel):
    """Override manual de un concepto en una boleta (antes de aprobar).
    monto = 0 elimina el concepto de la boleta."""
    concepto_id: str
    monto: Decimal


class ConfigPlanillaOut(BaseModel):
    descuento_tardanza_auto: bool


class ConfigPlanillaUpdate(BaseModel):
    descuento_tardanza_auto: bool


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
    concepto_nombre: Optional[str] = None
    concepto_codigo: Optional[str] = None
    monto: Decimal


class BoletaOut(BaseModel):
    id: str
    empleado_id: str
    empleado_nombre: Optional[str] = None
    total_ingresos: Decimal
    total_descuentos: Decimal
    total_aportes: Decimal
    total_neto: Decimal
    detalles: List[BoletaDetalleOut]


# ── Sueldos por empleado (asignación de montos por concepto) ──────────────────
class EmpleadoPlanillaOut(BaseModel):
    """Empleado activo, para asignarle montos por concepto en Planilla."""
    id: str
    nombre: Optional[str] = None
    cargo: Optional[str] = None


class AsignacionOut(BaseModel):
    empleado_id: str
    concepto_id: str
    monto: Decimal


class AsignacionItem(BaseModel):
    """Una asignación a guardar. monto None elimina el override (vuelve al referencial)."""
    concepto_id: str
    monto: Optional[Decimal] = None


TIPOS_MODALIDAD = {"planilla", "contrato", "practicante"}


class ModalidadUpdate(BaseModel):
    """Modalidad laboral del empleado (afecta el cálculo de planilla)."""
    tipo: str

    @field_validator("tipo")
    @classmethod
    def _tipo(cls, v: str) -> str:
        if v not in TIPOS_MODALIDAD:
            raise ValueError(f"tipo debe ser uno de {sorted(TIPOS_MODALIDAD)}")
        return v
