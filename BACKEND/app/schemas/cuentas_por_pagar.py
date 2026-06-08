"""Schemas del módulo de Cuentas por Pagar — AP (Fase 3).

Primera capa de defensa: el cuadre `total == subtotal + igv` y la no
negatividad se validan aquí, antes de llegar al servicio. La validación
`monto_aplicado <= saldo_pendiente` requiere consultar la BD y vive en el
servicio (no se puede resolver solo con el body)."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator, model_validator

TIPOS_DOCUMENTO = {"factura", "boleta", "nota_credito", "nota_debito"}
MEDIOS_PAGO = {"efectivo", "transferencia", "cheque"}
ESTADOS_FACTURA = {"pendiente", "pagada_parcial", "pagada", "anulada"}


# ── Facturas ─────────────────────────────────────────────────────────────────
class FacturaCreate(BaseModel):
    proveedor_id: str
    numero_documento: str
    tipo_documento: str = "factura"
    fecha_emision: date
    fecha_vencimiento: date
    subtotal: Decimal
    igv: Decimal = Decimal("0.00")
    moneda: Optional[str] = None
    orden_compra_id: Optional[str] = None

    @field_validator("tipo_documento")
    @classmethod
    def _tipo_valido(cls, v: str) -> str:
        if v not in TIPOS_DOCUMENTO:
            raise ValueError(f"tipo_documento debe ser uno de {sorted(TIPOS_DOCUMENTO)}")
        return v

    @field_validator("subtotal", "igv")
    @classmethod
    def _no_negativo(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("los montos no pueden ser negativos")
        return v

    @model_validator(mode="after")
    def _subtotal_positivo(self) -> "FacturaCreate":
        if self.subtotal <= 0:
            raise ValueError("el subtotal debe ser mayor que 0")
        if self.fecha_vencimiento < self.fecha_emision:
            raise ValueError("la fecha de vencimiento no puede ser anterior a la de emisión")
        return self

    @property
    def total(self) -> Decimal:
        return (self.subtotal + self.igv).quantize(Decimal("0.01"))


class FacturaOut(BaseModel):
    id: str
    proveedor_id: str
    orden_compra_id: Optional[str] = None
    numero_documento: str
    tipo_documento: str
    fecha_emision: date
    fecha_vencimiento: date
    moneda: str
    subtotal: Decimal
    igv: Decimal
    total: Decimal
    estado: str
    saldo_pendiente: Decimal
    asiento_id: Optional[str] = None


# ── Pagos ────────────────────────────────────────────────────────────────────
class AplicacionIn(BaseModel):
    factura_id: str
    monto_aplicado: Decimal

    @field_validator("monto_aplicado")
    @classmethod
    def _positivo(cls, v: Decimal) -> Decimal:
        if v <= 0:
            raise ValueError("monto_aplicado debe ser mayor que 0")
        return v


class PagoCreate(BaseModel):
    proveedor_id: str
    fecha_pago: date
    medio_pago: str = "efectivo"
    referencia: Optional[str] = None
    aplicaciones: List[AplicacionIn]

    @field_validator("medio_pago")
    @classmethod
    def _medio_valido(cls, v: str) -> str:
        if v not in MEDIOS_PAGO:
            raise ValueError(f"medio_pago debe ser uno de {sorted(MEDIOS_PAGO)}")
        return v

    @field_validator("aplicaciones")
    @classmethod
    def _al_menos_una(cls, v: List[AplicacionIn]) -> List[AplicacionIn]:
        if not v:
            raise ValueError("el pago debe aplicarse al menos a una factura")
        return v

    @property
    def monto(self) -> Decimal:
        return sum((a.monto_aplicado for a in self.aplicaciones), Decimal("0.00")).quantize(Decimal("0.01"))


class AplicacionOut(BaseModel):
    factura_id: str
    monto_aplicado: Decimal


class PagoOut(BaseModel):
    id: str
    proveedor_id: str
    fecha_pago: date
    monto: Decimal
    medio_pago: str
    referencia: Optional[str] = None
    asiento_id: Optional[str] = None
    aplicaciones: List[AplicacionOut]


# ── Reportes ─────────────────────────────────────────────────────────────────
class SaldoProveedorOut(BaseModel):
    proveedor_id: str
    proveedor: str
    facturas_abiertas: int
    saldo_total: Decimal


class AntiguedadBucketOut(BaseModel):
    proveedor_id: str
    proveedor: str
    por_vencer: Decimal       # aún no vence al corte
    d_0_30: Decimal
    d_31_60: Decimal
    d_61_90: Decimal
    d_mas_90: Decimal
    total: Decimal
