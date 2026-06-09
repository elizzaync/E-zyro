"""Schemas del módulo de Conciliación Bancaria (Fase 5).

Convención de signo del extracto:
  - abono = entró dinero a la cuenta (depósito/cobro). En libros la cuenta de
    Bancos se DEBITA → se concilia contra una línea con débito en esa cuenta.
  - cargo = salió dinero de la cuenta (pago/comisión). En libros la cuenta de
    Bancos se ACREDITA → se concilia contra una línea con crédito en esa cuenta.

Saldo según banco = Σ abonos − Σ cargos. Saldo según libros = débitos − créditos
de la cuenta del PCGE vinculada. Cuando todo está registrado y conciliado, ambos
saldos coinciden; la diferencia son las "partidas pendientes".
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator

TIPOS_MOVIMIENTO = {"cargo", "abono"}
MONEDAS = {"PEN", "USD"}


# ── Cuenta bancaria ───────────────────────────────────────────────────────────
class CuentaBancariaCreate(BaseModel):
    banco: str
    numero_cuenta: str
    cuenta_contable_id: str          # cuenta del PCGE (familia 104) que la representa
    moneda: str = "PEN"
    alias: Optional[str] = None

    @field_validator("banco", "numero_cuenta")
    @classmethod
    def _no_vacio(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("campo obligatorio")
        return v.strip()

    @field_validator("moneda")
    @classmethod
    def _moneda_valida(cls, v: str) -> str:
        if v not in MONEDAS:
            raise ValueError(f"moneda debe ser una de {sorted(MONEDAS)}")
        return v


class CuentaBancariaUpdate(BaseModel):
    banco: Optional[str] = None
    numero_cuenta: Optional[str] = None
    cuenta_contable_id: Optional[str] = None
    moneda: Optional[str] = None
    alias: Optional[str] = None
    activo: Optional[bool] = None

    @field_validator("moneda")
    @classmethod
    def _moneda_valida(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in MONEDAS:
            raise ValueError(f"moneda debe ser una de {sorted(MONEDAS)}")
        return v


class CuentaBancariaOut(BaseModel):
    id: str
    banco: str
    numero_cuenta: str
    moneda: str
    cuenta_contable_id: str
    cuenta_contable_codigo: Optional[str] = None
    cuenta_contable_nombre: Optional[str] = None
    alias: Optional[str] = None
    activo: bool
    saldo_banco: Decimal            # Σ abonos − Σ cargos (extracto)
    saldo_libros: Decimal           # débitos − créditos de la cuenta PCGE
    diferencia: Decimal             # saldo_banco − saldo_libros
    n_pendientes: int               # movimientos del extracto sin conciliar


# ── Movimiento bancario (renglón del extracto) ────────────────────────────────
class MovimientoBancarioCreate(BaseModel):
    fecha: date
    descripcion: str
    tipo: str                       # cargo | abono
    monto: Decimal
    referencia: Optional[str] = None

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


class ImportarMovimientosIn(BaseModel):
    """Carga masiva de un extracto (el cliente parsea el CSV y envía las filas)."""
    movimientos: List[MovimientoBancarioCreate]

    @field_validator("movimientos")
    @classmethod
    def _no_vacia(cls, v: List[MovimientoBancarioCreate]) -> List[MovimientoBancarioCreate]:
        if not v:
            raise ValueError("no hay movimientos para importar")
        return v


class MovimientoBancarioOut(BaseModel):
    id: str
    cuenta_bancaria_id: str
    fecha: date
    descripcion: str
    referencia: Optional[str] = None
    tipo: str
    monto: Decimal
    estado: str
    origen_carga: str
    asiento_id: Optional[str] = None
    asiento_numero: Optional[str] = None
    conciliado_por_nombre: Optional[str] = None
    conciliado_at: Optional[datetime] = None


# ── Conciliación ──────────────────────────────────────────────────────────────
class SugerenciaAsiento(BaseModel):
    """Un asiento candidato a conciliar con un movimiento del extracto."""
    asiento_id: str
    numero: str
    fecha: date
    descripcion: str
    origen: str
    monto: Decimal                  # importe en la cuenta de bancos (lado que aplica)
    dias_diferencia: int            # |fecha extracto − fecha asiento|


class ConciliarIn(BaseModel):
    asiento_id: str


class ResumenConciliacion(BaseModel):
    cuenta_bancaria_id: str
    saldo_banco: Decimal
    saldo_libros: Decimal
    diferencia: Decimal
    total_movimientos: int
    conciliados: int
    pendientes: int
    importe_pendiente: Decimal      # Σ |monto| de los movimientos sin conciliar
