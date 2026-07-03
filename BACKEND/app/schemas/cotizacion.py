"""Schemas del módulo de cotizaciones (ciclo comercial)."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator

ESTADOS = {"borrador", "enviada", "aceptada", "rechazada", "vencida", "convertida"}


class ItemIn(BaseModel):
    descripcion: str
    unidad: Optional[str] = None
    cantidad: Decimal = Decimal("1")
    precio_unitario: Decimal = Decimal("0")

    @field_validator("descripcion")
    @classmethod
    def _desc(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("la descripción es obligatoria")
        return v

    @field_validator("cantidad")
    @classmethod
    def _cant(cls, v: Decimal) -> Decimal:
        if v <= 0:
            raise ValueError("la cantidad debe ser mayor a 0")
        return v

    @field_validator("precio_unitario")
    @classmethod
    def _precio(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("el precio no puede ser negativo")
        return v


class ClienteNuevoIn(BaseModel):
    razon_social: str
    ruc: Optional[str] = None


class CotizacionCreate(BaseModel):
    # cliente existente O datos para crearlo al vuelo (pre-venta)
    cliente_id: Optional[str] = None
    cliente_nuevo: Optional[ClienteNuevoIn] = None
    fecha_emision: Optional[date] = None
    validez_dias: int = 30
    moneda: str = "PEN"
    condiciones_pago: Optional[str] = None
    notas: Optional[str] = None
    items: List[ItemIn]

    @field_validator("items")
    @classmethod
    def _items(cls, v: List[ItemIn]) -> List[ItemIn]:
        if not v:
            raise ValueError("la cotización necesita al menos un ítem")
        return v


class CotizacionUpdate(BaseModel):
    """Solo en borrador: reemplaza cabecera y/o items."""
    validez_dias: Optional[int] = None
    condiciones_pago: Optional[str] = None
    notas: Optional[str] = None
    items: Optional[List[ItemIn]] = None


class ResolverIn(BaseModel):
    estado: str  # aceptada | rechazada

    @field_validator("estado")
    @classmethod
    def _estado(cls, v: str) -> str:
        if v not in {"aceptada", "rechazada"}:
            raise ValueError("estado debe ser 'aceptada' o 'rechazada'")
        return v


class ConvertirIn(BaseModel):
    jefe_operaciones_id: str
    nombre_proyecto: Optional[str] = None


class ItemOut(BaseModel):
    id: str
    descripcion: str
    unidad: Optional[str] = None
    cantidad: Decimal
    precio_unitario: Decimal
    total: Decimal


class CotizacionOut(BaseModel):
    id: str
    numero: str
    cliente_id: str
    cliente: str
    ruc: Optional[str] = None
    fecha_emision: date
    validez_dias: int
    vence: date
    estado: str
    moneda: str
    subtotal: Decimal
    igv: Decimal
    total: Decimal
    condiciones_pago: Optional[str] = None
    notas: Optional[str] = None
    proyecto_id: Optional[str] = None
    contrato_comercial_id: Optional[str] = None
    resuelto_via: Optional[str] = None
    fecha_resolucion: Optional[datetime] = None
    items: List[ItemOut] = []
