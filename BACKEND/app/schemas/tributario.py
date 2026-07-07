"""Schemas del módulo tributario (Fase 6)."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel


class RegimenOut(BaseModel):
    id: str
    codigo: str
    nombre: str
    tasa_igv: Decimal
    tasa_renta_referencial: Optional[Decimal] = None
    activo: bool


class ConfiguracionOut(BaseModel):
    regimen_id: str
    regimen_codigo: str
    tasa_igv: Decimal
    cuenta_igv_credito_fiscal_id: Optional[str] = None
    cuenta_igv_debito_fiscal_id: Optional[str] = None


class ConfiguracionUpdate(BaseModel):
    regimen_id: Optional[str] = None
    cuenta_igv_credito_fiscal_id: Optional[str] = None
    cuenta_igv_debito_fiscal_id: Optional[str] = None


class RegistroFila(BaseModel):
    fecha: date
    ruc: Optional[str] = None
    proveedor: Optional[str] = None
    cliente: Optional[str] = None
    tipo_documento: str
    numero_documento: str
    base_imponible: Decimal
    igv: Decimal
    total: Decimal
    # Multimoneda: montos arriba SIEMPRE en PEN; el doc origen se muestra aparte.
    moneda: str = "PEN"
    tipo_cambio: Decimal = Decimal("1")
    total_original: Optional[Decimal] = None
