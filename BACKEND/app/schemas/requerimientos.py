from __future__ import annotations
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel


class CatalogoItemOut(BaseModel):
    id: UUID
    nombre: str
    codigo: Optional[str]
    unidad: str
    stock: int
    categoria: Optional[str]
    descripcion: Optional[str] = None
    imagen_url: Optional[str] = None


<<<<<<< HEAD
=======
# ── Panel del encargado de logística ──────────────────────────────

class MaterialBajoStockOut(BaseModel):
    id: str
    nombre: str
    unidad: str
    categoria: Optional[str] = None
    stock: int
    minimo: int


class InventarioResumenOut(BaseModel):
    total_items: int
    bajo_stock: int
    sin_stock: int
    items_bajo_stock: List[MaterialBajoStockOut] = []


# ── Bandeja de solicitudes del encargado ──────────────────────────

class SolicitudGestionOut(BaseModel):
    id: str
    estado: str
    fecha: str
    observacion: Optional[str] = None
    observacion_logistico: Optional[str] = None
    proyecto_nombre: str
    solicitante_nombre: str
    items: List[SolicitudDetalleOut] = []


class GestionarSolicitudBody(BaseModel):
    accion: str  # "aprobar" | "rechazar"
    observacion_logistico: Optional[str] = None


# ── Fase 3: ajuste de stock + movimientos ─────────────────────────

class AjusteStockBody(BaseModel):
    material_id: str
    tipo: str             # "entrada" | "salida" | "ajuste"
    cantidad: int         # entrada/salida: magnitud; ajuste: valor exacto a fijar
    motivo: Optional[str] = None
    almacen_id: Optional[str] = None   # opcional; por defecto el principal/que tiene stock


class MovimientoOut(BaseModel):
    id: str
    material_id: str
    material_nombre: str
    unidad: str
    tipo: str
    cantidad: int
    motivo: Optional[str] = None
    almacen_nombre: Optional[str] = None
    responsable_nombre: Optional[str] = None
    fecha: str


# ── Fase 4: editar materiales + categorías ────────────────────────

class EditarMaterialBody(BaseModel):
    nombre: Optional[str] = None
    codigo: Optional[str] = None
    unidad: Optional[str] = None
    descripcion: Optional[str] = None
    categoria_id: Optional[str] = None
    cantidad_minima: Optional[int] = None   # umbral de bajo stock


class CategoriaBody(BaseModel):
    nombre: str
    descripcion: Optional[str] = None


# ── Fase 6: transferencia entre almacenes ─────────────────────────

class TransferenciaBody(BaseModel):
    material_id: str
    almacen_origen_id: str
    almacen_destino_id: str
    cantidad: int
    motivo: Optional[str] = None


>>>>>>> 83bdd8fbf5d24159f34ef58e507370e5358088f5
class SolicitudDetalleOut(BaseModel):
    id: str
    material_id: Optional[str] = None
    nombre: str
    unidad: str
    cantidad: int
    cantidad_aprobada: Optional[int]
    nombre_libre: Optional[str] = None
    unidad_libre: Optional[str] = None
    especificacion: Optional[str] = None


class MiSolicitudOut(BaseModel):
    id: str
    estado: str
    fecha: str
    observacion: Optional[str]
    observacion_logistico: Optional[str] = None  # HU-16
    proyecto_nombre: str
    items: List[SolicitudDetalleOut]


# ── Entrada ───────────────────────────────────────────────────

class ItemSolicitudBody(BaseModel):
    material_id: Optional[str] = None
    cantidad: int
    nombre_libre: Optional[str] = None
    unidad_libre: Optional[str] = None
    especificacion: Optional[str] = None


class CrearSolicitudBody(BaseModel):
    proyecto_id: str
    items: List[ItemSolicitudBody]
    observacion: Optional[str] = None


class CategoriaOut(BaseModel):
    id: str
    nombre: str


class AlmacenOut(BaseModel):
    id: str
    nombre: str
    ubicacion: Optional[str]


class CrearMaterialBody(BaseModel):
    nombre: str
    codigo: Optional[str] = None
    unidad: str
    categoria_id: str
    descripcion: Optional[str] = None
    cantidad_inicial: int = 0
    almacen_id: Optional[str] = None
