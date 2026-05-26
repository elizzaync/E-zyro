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
