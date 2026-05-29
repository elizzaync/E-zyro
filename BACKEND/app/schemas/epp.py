"""Schemas del módulo EPP."""
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, field_validator


# ── Catálogo ─────────────────────────────────────────────────────────────────
class EppIn(BaseModel):
    nombre:       str
    descripcion:  Optional[str] = None
    marca_id:     Optional[str] = None
    unidad_id:    Optional[str] = None
    zona_id:      Optional[str] = None
    stock_min:    int = 0
    precio:       Optional[float] = None


class EppOut(BaseModel):
    id:           str
    nombre:       str
    descripcion:  Optional[str] = None
    marca_id:     Optional[str] = None
    unidad_id:    Optional[str] = None
    zona_id:      Optional[str] = None
    stock_actual: int
    stock_min:    int
    precio:       Optional[float] = None
    imagen_url:   Optional[str] = None
    activo:       bool


class EppImagenIn(BaseModel):
    imagen_base64: str


# ── Entregas ─────────────────────────────────────────────────────────────────
class EntregaItemIn(BaseModel):
    epp_id:   str
    cantidad: int

    @field_validator("cantidad")
    @classmethod
    def _pos(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("cantidad debe ser > 0")
        return v


class EntregaIn(BaseModel):
    empleado_id:  str
    items:        List[EntregaItemIn]
    firma_base64: Optional[str] = None
    observacion:  Optional[str] = None


class EntregaItemOut(BaseModel):
    epp_id:     str
    nombre:     str
    cantidad:   int


class EntregaOut(BaseModel):
    id:           str
    empleado_id:  str
    empleado_nombre: Optional[str] = None
    fecha:        Optional[str] = None
    estado:       str
    firma_url:    Optional[str] = None
    pdf_url:      Optional[str] = None
    observacion:  Optional[str] = None
    items:        List[EntregaItemOut] = []


# ── Ingresos ─────────────────────────────────────────────────────────────────
class IngresoItemIn(BaseModel):
    epp_id:          str
    cantidad:        int
    precio_unitario: Optional[float] = None

    @field_validator("cantidad")
    @classmethod
    def _pos(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("cantidad debe ser > 0")
        return v


class IngresoIn(BaseModel):
    personal_compro_id: Optional[str] = None
    proveedor_id:       Optional[str] = None
    items:              List[IngresoItemIn]


class IngresoOut(BaseModel):
    id:           str
    fecha_compra: Optional[str] = None
    proveedor_id: Optional[str] = None
    items:        List[EntregaItemOut] = []
