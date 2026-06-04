"""Schemas Pydantic para préstamos de equipos/herramientas."""
from __future__ import annotations
from typing import List, Optional, Literal
from pydantic import BaseModel


# ── Catálogo (lo que el técnico ve para solicitar) ─────────────────────────────

class EquipoCatalogoOut(BaseModel):
    id:            str
    codigo:        Optional[str] = None
    nombre:        str
    clase:         str                       # 'equipo' | 'herramienta'
    tipo:          Optional[str] = None
    marca:         Optional[str] = None
    modelo:        Optional[str] = None
    almacen_nombre: Optional[str] = None
    cantidad_total: int                       # stock teórico (campo Equipo.cantidad)
    cantidad_disponible: int                  # cantidad - prestados activos
    requiere_mantenimiento: bool = False


# ── Items de un préstamo ───────────────────────────────────────────────────────

class PrestamoItemSolicitar(BaseModel):
    equipo_id: str
    cantidad:  int


class PrestamoItemOut(BaseModel):
    id:                  str
    equipo_id:           str
    equipo_nombre:       str
    equipo_codigo:       Optional[str] = None
    clase:               str
    cantidad_solicitada: int
    cantidad_entregada:  Optional[int] = None
    cantidad_devuelta:   Optional[int] = None
    cantidad_perdida:    int = 0
    observacion:         Optional[str] = None


# ── Préstamo (head) ────────────────────────────────────────────────────────────

class CrearPrestamoBody(BaseModel):
    items:        List[PrestamoItemSolicitar]
    observacion:  Optional[str] = None


class EntregarPrestamoItem(BaseModel):
    item_id:            str
    cantidad_entregada: int


class EntregarPrestamoBody(BaseModel):
    items:             List[EntregarPrestamoItem] = []   # vacío → entrega cantidad solicitada
    observacion:       Optional[str] = None
    firmaReceptorUrl:  Optional[str] = None   # firma del técnico al recibir


class DevolverPrestamoItem(BaseModel):
    item_id:           str
    cantidad_devuelta: int
    observacion:       Optional[str] = None


class DevolverPrestamoBody(BaseModel):
    items:        List[DevolverPrestamoItem]
    observacion:  Optional[str] = None


class ConfirmarDevolucionBody(BaseModel):
    aceptar:         bool = True               # False = rechaza la devolución y queda 'devuelto'
    observacion:     Optional[str] = None


class RechazarPrestamoBody(BaseModel):
    observacion: str


class PrestamoOut(BaseModel):
    id:                   str
    servicio_id:          str
    servicio_nombre:      Optional[str] = None
    proyecto_nombre:      Optional[str] = None
    solicitante_id:       str
    solicitante_nombre:   str
    estado:               str
    observacion:          Optional[str] = None
    observacion_logistico: Optional[str] = None
    entregado_por_nombre: Optional[str] = None
    devuelto_por_nombre:  Optional[str] = None
    confirmado_por_nombre: Optional[str] = None
    fecha_solicitud:      str
    fecha_entrega:        Optional[str] = None
    fecha_devolucion:     Optional[str] = None
    fecha_confirmacion:   Optional[str] = None
    firma_receptor_url:   Optional[str] = None
    items:                List[PrestamoItemOut]


# Subconjunto liviano usado en banners/avisos
class PrestamoAvisoOut(BaseModel):
    id:                str
    servicio_id:       str
    estado:            str
    fecha_devolucion:  Optional[str] = None
    total_items:       int

PrestamoEstado = Literal[
    "solicitado", "entregado", "devuelto", "confirmado", "rechazado", "todos",
]
