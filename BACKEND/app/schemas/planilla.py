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


TIPOS_REGIMEN_LABORAL = {"micro", "pequena", "general"}
TIPOS_ESQUEMA_PAGO = {"mensual", "quincenal"}


class ConfigPlanillaOut(BaseModel):
    descuento_tardanza_auto: bool
    regimen_laboral: str
    esquema_pago_planilla: str


class ConfigPlanillaUpdate(BaseModel):
    descuento_tardanza_auto: Optional[bool] = None
    regimen_laboral: Optional[str] = None
    esquema_pago_planilla: Optional[str] = None

    @field_validator("regimen_laboral")
    @classmethod
    def _regimen(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_REGIMEN_LABORAL:
            raise ValueError(f"regimen_laboral debe ser uno de {sorted(TIPOS_REGIMEN_LABORAL)}")
        return v

    @field_validator("esquema_pago_planilla")
    @classmethod
    def _esquema(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_ESQUEMA_PAGO:
            raise ValueError(f"esquema_pago_planilla debe ser uno de {sorted(TIPOS_ESQUEMA_PAGO)}")
        return v


# ── Configuración previsional por empleado (Fase 8) ───────────────────────────
TIPOS_SISTEMA_PENSION = {"onp", "afp"}
TIPOS_ENTIDAD_AFP = {"integra", "prima", "profuturo", "habitat"}


class PensionConfigOut(BaseModel):
    empleado_id: str
    sistema_pension: str
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: bool


class PensionConfigUpdate(BaseModel):
    """Actualización parcial (PATCH semántico): solo los campos presentes
    en el body se modifican. comision_afp_personalizada=None restablece
    la comisión oficial de la AFP (ver AFP_COMISIONES)."""
    sistema_pension: Optional[str] = None
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: Optional[bool] = None

    @field_validator("sistema_pension")
    @classmethod
    def _sistema(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_SISTEMA_PENSION:
            raise ValueError(f"sistema_pension debe ser uno de {sorted(TIPOS_SISTEMA_PENSION)}")
        return v

    @field_validator("entidad_afp")
    @classmethod
    def _entidad(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_ENTIDAD_AFP:
            raise ValueError(f"entidad_afp debe ser uno de {sorted(TIPOS_ENTIDAD_AFP)}")
        return v

    @field_validator("comision_afp_personalizada")
    @classmethod
    def _comision(cls, v: Optional[Decimal]) -> Optional[Decimal]:
        if v is not None and (v < 0 or v > Decimal("0.5")):
            raise ValueError("comision_afp_personalizada debe estar entre 0 y 0.5 (50%)")
        return v


class SueldoBaseUpdate(BaseModel):
    monto: Decimal

    @field_validator("monto")
    @classmethod
    def _monto(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("monto no puede ser negativo")
        return v


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
    # Configuración previsional vigente (Fase 8) — de empleado_planilla_config,
    # con los defaults de código si el empleado no tiene fila propia todavía.
    sistema_pension: str = "onp"
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: bool = False


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
