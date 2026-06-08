"""Schemas del módulo de contabilidad (Fase 1 — Libro Mayor)."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator, model_validator


# ── Plan de cuentas ──────────────────────────────────────────────────────────
class CuentaOut(BaseModel):
    id: str
    codigo: str
    nombre: str
    tipo: str
    naturaleza: str
    nivel: str
    cuenta_padre_id: Optional[str] = None
    activo: bool


class CuentaActivarIn(BaseModel):
    activo: bool


# ── Periodos ─────────────────────────────────────────────────────────────────
class PeriodoCreate(BaseModel):
    anio: int
    mes: int

    @field_validator("mes")
    @classmethod
    def _mes_valido(cls, v: int) -> int:
        if not 1 <= v <= 12:
            raise ValueError("mes debe estar entre 1 y 12")
        return v

    @field_validator("anio")
    @classmethod
    def _anio_valido(cls, v: int) -> int:
        if not 2000 <= v <= 2100:
            raise ValueError("anio fuera de rango razonable")
        return v


class PeriodoOut(BaseModel):
    id: str
    anio: int
    mes: int
    estado: str
    cerrado_at: Optional[datetime] = None


# ── Asientos ─────────────────────────────────────────────────────────────────
class LineaAsientoIn(BaseModel):
    cuenta_id: str
    debito: Decimal = Decimal("0")
    credito: Decimal = Decimal("0")
    centro_costo_id: Optional[str] = None
    glosa: Optional[str] = None

    @model_validator(mode="after")
    def _debito_xor_credito(self):
        d = self.debito or Decimal("0")
        c = self.credito or Decimal("0")
        if d < 0 or c < 0:
            raise ValueError("los montos no pueden ser negativos")
        if (d > 0 and c > 0) or (d == 0 and c == 0):
            raise ValueError("cada línea debe tener débito XOR crédito (uno > 0, el otro = 0)")
        return self


class AsientoCreate(BaseModel):
    fecha: date
    descripcion: str
    lineas: List[LineaAsientoIn]
    referencia_id: Optional[str] = None

    @field_validator("lineas")
    @classmethod
    def _al_menos_dos(cls, v: List[LineaAsientoIn]) -> List[LineaAsientoIn]:
        if len(v) < 2:
            raise ValueError("un asiento de partida doble requiere al menos 2 líneas")
        return v

    @model_validator(mode="after")
    def _cuadra(self):
        td = sum((ln.debito or Decimal("0")) for ln in self.lineas)
        tc = sum((ln.credito or Decimal("0")) for ln in self.lineas)
        if td != tc:
            raise ValueError(f"asiento descuadrado: débitos {td} ≠ créditos {tc}")
        if td == 0:
            raise ValueError("el asiento no puede ser de monto cero")
        return self


class AsientoLineaOut(BaseModel):
    id: str
    cuenta_id: str
    cuenta_codigo: Optional[str] = None
    debito: Decimal
    credito: Decimal
    centro_costo_id: Optional[str] = None
    glosa: Optional[str] = None


class AsientoOut(BaseModel):
    id: str
    numero: str
    fecha: date
    periodo_id: str
    descripcion: str
    origen: str
    referencia_id: Optional[str] = None
    lineas: List[AsientoLineaOut] = []


# ── Reportes de la fase (balance de comprobación / mayor) ─────────────────────
class BalanceComprobacionFila(BaseModel):
    codigo: str
    nombre: str
    total_debito: Decimal
    total_credito: Decimal
    saldo_deudor: Decimal
    saldo_acreedor: Decimal


class BalanceComprobacionOut(BaseModel):
    periodo_id: str
    filas: List[BalanceComprobacionFila]
    total_deudor: Decimal
    total_acreedor: Decimal
    cuadra: bool
