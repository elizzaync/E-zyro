from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel


# ── Proveedores ───────────────────────────────────────────────────

class ProveedorOut(BaseModel):
    id: str
    razon_social: str
    ruc: Optional[str] = None
    contacto: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    direccion: Optional[str] = None


class ProveedorBody(BaseModel):
    razon_social: str
    ruc: Optional[str] = None
    contacto: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    direccion: Optional[str] = None


# ── Órdenes de compra ─────────────────────────────────────────────

class DetalleCompraIn(BaseModel):
    material_id: str
    cantidad: int
    precio_unitario: float = 0.0


class CrearOrdenCompraBody(BaseModel):
    proveedor_id: str
    fecha_entrega_estimada: Optional[str] = None   # YYYY-MM-DD
    items: List[DetalleCompraIn]


class DetalleCompraOut(BaseModel):
    id: str
    material_id: str
    material_nombre: str
    unidad: str
    cantidad: int
    precio_unitario: float


class OrdenCompraOut(BaseModel):
    id: str
    proveedor_id: str
    proveedor_nombre: str
    estado: str
    fecha_emision: str
    fecha_entrega_estimada: Optional[str] = None
    total_referencial: float
    total_items: int
    items: List[DetalleCompraOut] = []


class CambiarEstadoOrdenBody(BaseModel):
    estado: str   # enviada | confirmada | en_transito | cancelada


# ── Recepción de mercadería ───────────────────────────────────────

class RecepcionItemIn(BaseModel):
    material_id: str
    cantidad_recibida: int


class RecibirOrdenBody(BaseModel):
    almacen_id: Optional[str] = None
    notas: Optional[str] = None
    items: Optional[List[RecepcionItemIn]] = None   # None = recibir completo según la orden
