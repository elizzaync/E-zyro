"""Schemas del módulo de Cuentas por Cobrar — AR (Fase 4). Simétrico a AP."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator, model_validator

TIPOS_DOCUMENTO = {"factura", "boleta", "nota_credito", "nota_debito"}
MEDIOS_PAGO = {"efectivo", "transferencia", "cheque"}


class ComprobanteCreate(BaseModel):
    cliente_id: str
    numero_documento: str
    tipo_documento: str = "factura"
    fecha_emision: date
    fecha_vencimiento: Optional[date] = None
    subtotal: Decimal
    igv: Decimal = Decimal("0.00")
    moneda: Optional[str] = None
    proyecto_id: Optional[str] = None
    proyecto_servicio_id: Optional[str] = None   # servicio que origina la factura
    al_contado: bool = False   # True → se cobra de inmediato (Db caja), estado 'cobrada'

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
    def _coherencia(self) -> "ComprobanteCreate":
        if self.subtotal <= 0:
            raise ValueError("el subtotal debe ser mayor que 0")
        if not self.al_contado and self.fecha_vencimiento is None:
            raise ValueError("una venta a crédito requiere fecha de vencimiento")
        if self.fecha_vencimiento is not None and self.fecha_vencimiento < self.fecha_emision:
            raise ValueError("la fecha de vencimiento no puede ser anterior a la de emisión")
        return self

    @property
    def total(self) -> Decimal:
        return (self.subtotal + self.igv).quantize(Decimal("0.01"))


class FacturarServicioIn(BaseModel):
    """Emite la factura de venta de un servicio completado. El cliente se deriva
    del proyecto; el monto se captura aquí (no existe en el modelo del servicio)."""
    servicio_id: str
    numero_documento: str
    tipo_documento: str = "factura"
    fecha_emision: date
    fecha_vencimiento: Optional[date] = None
    subtotal: Decimal
    igv: Decimal = Decimal("0.00")
    moneda: Optional[str] = None
    al_contado: bool = False

    @field_validator("subtotal", "igv")
    @classmethod
    def _no_neg(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("los montos no pueden ser negativos")
        return v

    @model_validator(mode="after")
    def _coherencia(self) -> "FacturarServicioIn":
        if self.subtotal <= 0:
            raise ValueError("el subtotal debe ser mayor que 0")
        if not self.al_contado and self.fecha_vencimiento is None:
            raise ValueError("una venta a crédito requiere fecha de vencimiento")
        if self.fecha_vencimiento is not None and self.fecha_vencimiento < self.fecha_emision:
            raise ValueError("la fecha de vencimiento no puede ser anterior a la de emisión")
        return self


class ServicioFacturableOut(BaseModel):
    servicio_id: str
    servicio_nombre: str
    proyecto_id: Optional[str] = None
    proyecto_nombre: Optional[str] = None
    cliente_id: Optional[str] = None
    cliente_nombre: Optional[str] = None
    nro_documento_cliente: Optional[str] = None   # OC/proforma del cliente, si la hay


class ComprobanteOut(BaseModel):
    id: str
    cliente_id: str
    proyecto_id: Optional[str] = None
    numero_documento: str
    tipo_documento: str
    fecha_emision: date
    fecha_vencimiento: Optional[date] = None
    moneda: str
    subtotal: Decimal
    igv: Decimal
    total: Decimal
    estado: str
    saldo_pendiente: Decimal
    asiento_id: Optional[str] = None


class AplicacionCobroIn(BaseModel):
    factura_id: str
    monto_aplicado: Decimal

    @field_validator("monto_aplicado")
    @classmethod
    def _positivo(cls, v: Decimal) -> Decimal:
        if v <= 0:
            raise ValueError("monto_aplicado debe ser mayor que 0")
        return v


class CobroCreate(BaseModel):
    cliente_id: str
    fecha_cobro: date
    medio_pago: str = "efectivo"
    referencia: Optional[str] = None
    aplicaciones: List[AplicacionCobroIn]

    @field_validator("medio_pago")
    @classmethod
    def _medio_valido(cls, v: str) -> str:
        if v not in MEDIOS_PAGO:
            raise ValueError(f"medio_pago debe ser uno de {sorted(MEDIOS_PAGO)}")
        return v

    @field_validator("aplicaciones")
    @classmethod
    def _al_menos_una(cls, v: List[AplicacionCobroIn]) -> List[AplicacionCobroIn]:
        if not v:
            raise ValueError("el cobro debe aplicarse al menos a una factura")
        return v

    @property
    def monto(self) -> Decimal:
        return sum((a.monto_aplicado for a in self.aplicaciones), Decimal("0.00")).quantize(Decimal("0.01"))


class AplicacionCobroOut(BaseModel):
    factura_id: str
    monto_aplicado: Decimal


class CobroOut(BaseModel):
    id: str
    cliente_id: str
    fecha_cobro: date
    monto: Decimal
    medio_pago: str
    referencia: Optional[str] = None
    asiento_id: Optional[str] = None
    aplicaciones: List[AplicacionCobroOut]


class SaldoClienteOut(BaseModel):
    cliente_id: str
    cliente: str
    facturas_abiertas: int
    saldo_total: Decimal


class AntiguedadClienteOut(BaseModel):
    cliente_id: str
    cliente: str
    por_vencer: Decimal
    d_0_30: Decimal
    d_31_60: Decimal
    d_61_90: Decimal
    d_mas_90: Decimal
    total: Decimal
