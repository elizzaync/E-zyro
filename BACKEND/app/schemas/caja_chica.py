"""Schemas del módulo de Caja Chica (Fase 5).

Caja chica operativa: efectivo físico que un responsable administra para
gastos menores. CADA movimiento genera su asiento contable automático
(principio "todo conectado a Finanzas"):

  Constitución / reposición del fondo (ingreso):
      Db 101 Caja chica   /   Cr 104 Bancos
  Gasto pagado con la caja (egreso):
      Db 6xx Gasto        /   Cr 101 Caja chica

El saldo de la caja = Σ ingresos − Σ egresos (el monto_asignado_referencial
es solo el fondo fijo objetivo, no un movimiento). Un egreso no puede dejar
la caja en negativo: primero hay que constituir el fondo con un ingreso.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, field_validator

TIPOS_MOVIMIENTO = {"ingreso", "egreso"}
ESTADOS_CAJA = {"abierta", "cerrada", "suspendida"}


# ── Caja ─────────────────────────────────────────────────────────────────────
class CajaChicaCreate(BaseModel):
    responsable_id: Optional[str] = None   # default: el empleado que crea la caja
    nombre: str
    descripcion: Optional[str] = None
    monto_asignado_referencial: Optional[Decimal] = None
    proyecto_id: Optional[str] = None
    fecha_apertura: Optional[date] = None

    @field_validator("nombre")
    @classmethod
    def _nombre_no_vacio(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("el nombre de la caja es obligatorio")
        return v.strip()

    @field_validator("monto_asignado_referencial")
    @classmethod
    def _monto_no_negativo(cls, v: Optional[Decimal]) -> Optional[Decimal]:
        if v is not None and v < 0:
            raise ValueError("el monto asignado no puede ser negativo")
        return v


class CajaChicaOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str] = None
    responsable_id: str
    responsable_nombre: Optional[str] = None
    proyecto_id: Optional[str] = None
    monto_asignado_referencial: Optional[Decimal] = None
    fecha_apertura: date
    fecha_cierre: Optional[date] = None
    estado: str
    total_ingresos: Decimal
    total_egresos: Decimal
    saldo_actual: Decimal
    n_movimientos: int


# ── Movimientos ──────────────────────────────────────────────────────────────
class MovimientoCajaCreate(BaseModel):
    tipo: str                       # ingreso | egreso
    monto: Decimal
    descripcion: str
    concepto: Optional[str] = None
    fecha: Optional[datetime] = None
    comprobante_url: Optional[str] = None
    public_id_cloudinary: Optional[str] = None
    # Override opcional de la cuenta contable contrapartida (código PCGE):
    #  - egreso: cuenta de gasto a debitar (default 659)
    #  - ingreso: cuenta de origen del dinero a acreditar (default 104 bancos)
    cuenta_codigo: Optional[str] = None

    @field_validator("tipo")
    @classmethod
    def _tipo_valido(cls, v: str) -> str:
        if v not in TIPOS_MOVIMIENTO:
            raise ValueError(f"tipo debe ser uno de {sorted(TIPOS_MOVIMIENTO)}")
        return v

    @field_validator("monto")
    @classmethod
    def _monto_positivo(cls, v: Decimal) -> Decimal:
        if v <= 0:
            raise ValueError("el monto debe ser mayor que 0")
        return v

    @field_validator("descripcion")
    @classmethod
    def _desc_no_vacia(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("la descripción es obligatoria")
        return v.strip()


class MovimientoCajaOut(BaseModel):
    id: str
    caja_id: str
    tipo: str
    monto: Decimal
    descripcion: str
    concepto: Optional[str] = None
    comprobante_url: Optional[str] = None
    registrado_por: str
    registrado_por_nombre: Optional[str] = None
    fecha: datetime
    asiento_id: Optional[str] = None
