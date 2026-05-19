from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel


class CatalogoItemOut(BaseModel):
    id: str
    nombre: str
    codigo: Optional[str]
    unidad: str
    stock: int
    categoria: Optional[str]
    descripcion: Optional[str] = None   # HU-15
    imagen_url: Optional[str] = None    # HU-15


class SolicitudDetalleOut(BaseModel):
    id: str
    material_id: str
    nombre: str
    unidad: str
    cantidad: int
    cantidad_aprobada: Optional[int]


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
    material_id: str
    cantidad: int


class CrearSolicitudBody(BaseModel):
    proyecto_id: str
    items: List[ItemSolicitudBody]
    observacion: Optional[str] = None
