"""
Schemas Pydantic para el módulo de Logística (HU-15).

Modelan Materiales (catálogo + stock agregado) y Equipos/Herramientas
(unifica lo que en el legacy era la tabla `articulos`, separado por
campo `clase`).
"""
from __future__ import annotations

from datetime import date
from typing import Literal, Optional, List

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════════════════
# MATERIALES (catálogo + stock agregado por empresa)
# ═══════════════════════════════════════════════════════════════════════════

class MaterialOut(BaseModel):
    id:           str
    codigo:       str
    nombre:       str
    categoriaId:  Optional[str] = None
    categoria:    str
    unidadId:     Optional[str] = None
    unidad:       str
    descripcion:  Optional[str] = None
    cantidad:     int                 # stock total agregado (sum almacenes)
    stockMinimo: int = Field(0, alias="stockMinimo")
    almacenId:   Optional[str] = None
    almacen:     str
    precio:      Optional[float] = None
    activo:      bool

    class Config:
        populate_by_name = True


class MaterialIn(BaseModel):
    # codigo es opcional: si no viene, el backend lo autogenera (MAT-NNNN)
    codigo:       Optional[str] = None
    nombre:       str
    categoriaId:  str
    unidadId:     str
    descripcion:  Optional[str] = None
    cantidad:     int = 0
    stockMinimo: int = 0
    almacenId:   str
    precio:      Optional[float] = None
    activo:      bool = True


class MaterialPatch(BaseModel):
    codigo:       Optional[str] = None
    nombre:       Optional[str] = None
    categoriaId:  Optional[str] = None
    unidadId:     Optional[str] = None
    descripcion:  Optional[str] = None
    cantidad:     Optional[int] = None
    stockMinimo: Optional[int] = None
    almacenId:   Optional[str] = None
    precio:      Optional[float] = None
    activo:      Optional[bool] = None


class MaterialesListResponse(BaseModel):
    items: List[MaterialOut]
    total: int
    page:  int
    pageSize: int


# ═══════════════════════════════════════════════════════════════════════════
# EQUIPOS Y HERRAMIENTAS
# ═══════════════════════════════════════════════════════════════════════════

ClaseArticulo = Literal["equipo", "herramienta"]
EstadoEquipo  = Literal["operativo", "en_mantenimiento", "fuera_de_servicio", "baja"]
FrecuenciaMant = Literal["ninguno", "mensual", "trimestral", "semestral", "anual"]


class EquipoOut(BaseModel):
    id:          str
    codigo:      str
    nombre:      str
    clase:       ClaseArticulo
    tipoId:      Optional[str] = None
    tipo:        str
    marcaId:     Optional[str] = None
    marca:       Optional[str] = None
    modeloId:    Optional[str] = None
    modelo:      Optional[str] = None
    numeroSerie: Optional[str] = None
    almacenId:   Optional[str] = None
    ubicacion:   Optional[str] = None
    cantidad:    int
    estado:      EstadoEquipo
    requiereMantenimiento:     bool
    frecuenciaMantenimiento:   FrecuenciaMant
    proximaFechaMantenimiento: Optional[str] = None
    fechaAdquisicion:          Optional[str] = None
    fichaTecnica:              Optional[str] = None


class EquipoIn(BaseModel):
    # codigo autogenerado si viene vacío
    codigo:      Optional[str] = None
    nombre:      str
    clase:       ClaseArticulo = "equipo"
    tipoId:      Optional[str] = None      # FK → tipo_equipo.id (familia)
    marcaId:     Optional[str] = None
    modeloId:    Optional[str] = None
    numeroSerie: Optional[str] = None
    almacenId:   Optional[str] = None
    cantidad:    int = 1
    estado:      EstadoEquipo = "operativo"
    requiereMantenimiento:     bool = False
    frecuenciaMantenimiento:   FrecuenciaMant = "ninguno"
    proximaFechaMantenimiento: Optional[date] = None
    fechaAdquisicion:          Optional[date] = None
    fichaTecnica:              Optional[str]  = None


class EquipoPatch(BaseModel):
    codigo:      Optional[str] = None
    nombre:      Optional[str] = None
    clase:       Optional[ClaseArticulo] = None
    tipoId:      Optional[str] = None
    marcaId:     Optional[str] = None
    modeloId:    Optional[str] = None
    numeroSerie: Optional[str] = None
    almacenId:   Optional[str] = None
    cantidad:    Optional[int] = None
    estado:      Optional[EstadoEquipo] = None
    requiereMantenimiento:     Optional[bool] = None
    frecuenciaMantenimiento:   Optional[FrecuenciaMant] = None
    proximaFechaMantenimiento: Optional[date] = None
    fechaAdquisicion:          Optional[date] = None
    fichaTecnica:              Optional[str]  = None


class EquiposListResponse(BaseModel):
    items: List[EquipoOut]
    total: int
    page:  int
    pageSize: int


# ═══════════════════════════════════════════════════════════════════════════
# KPIs
# ═══════════════════════════════════════════════════════════════════════════

class LogisticaKpis(BaseModel):
    totalMateriales:     int
    materialesStockBajo: int
    totalEquipos:        int
    totalHerramientas:   int
    enMantenimiento:     int


# ═══════════════════════════════════════════════════════════════════════════
# CATÁLOGOS (categoria, almacén, tipo, marca, modelo, unidad)
# ═══════════════════════════════════════════════════════════════════════════

class CatalogoItem(BaseModel):
    """Salida estándar para selects del frontend."""
    id:     str
    nombre: str


class CatalogoIn(BaseModel):
    nombre: str


class AlmacenOut(CatalogoItem):
    ubicacion: Optional[str] = None


class AlmacenIn(BaseModel):
    nombre:    str
    ubicacion: Optional[str] = None


class UnidadOut(CatalogoItem):
    abreviatura: Optional[str] = None


class UnidadIn(BaseModel):
    nombre:      str
    abreviatura: Optional[str] = None


class ModeloOut(CatalogoItem):
    marcaId: str


class ModeloIn(BaseModel):
    nombre:  str
    marcaId: str


# ═══════════════════════════════════════════════════════════════════════════
# REQUERIMIENTOS (HU-16 — control de stock y aprobación de pedidos)
# ═══════════════════════════════════════════════════════════════════════════

class RequerimientoItemOut(BaseModel):
    id:              str
    materialId:      Optional[str] = None
    nombre:          str
    unidad:          str
    cantidad:        int
    cantidadAprobada: Optional[int] = None
    stockDisponible: int = 0          # stock actual del material (0 si compra externa)
    enStock:         bool = False     # True si hay stock suficiente
    esCompraExterna: bool = False     # material_id NULL → no está en catálogo
    especificacion:  Optional[str] = None
    estadoItem:      str = "pendiente"
    agregadoPor:     Optional[str] = None


class RequerimientoOut(BaseModel):
    id:              str
    estado:          str
    fecha:           Optional[str] = None
    observacion:     Optional[str] = None
    observacionLogistico: Optional[str] = None
    proyectoId:      Optional[str] = None
    proyectoNombre:  str
    servicioId:      Optional[str] = None
    servicioNombre:  Optional[str] = None
    solicitanteId:   Optional[str] = None
    solicitanteNombre: str
    solicitanteFoto: Optional[str] = None
    items:           List[RequerimientoItemOut]
    # Entrega (si ya se entregó)
    entregadoPorNombre: Optional[str] = None
    recibidoPorNombre:  Optional[str] = None
    firmaUrl:           Optional[str] = None
    fechaEntrega:       Optional[str] = None


class RequerimientosListResponse(BaseModel):
    items: List[RequerimientoOut]
    total: int
    page:  int
    pageSize: int


class AprobarItemDecision(BaseModel):
    detalleId:        str
    decision:         Literal["aprobar", "compra", "rechazar"]
    cantidadAprobada: Optional[int] = None   # si None → toma cantidad solicitada (o stock disponible)


class AprobarBody(BaseModel):
    almacenId:    Optional[str] = None       # almacén de salida; si None usa el primero
    decisiones:   List[AprobarItemDecision] = []
    observacion:  Optional[str] = None


class RechazarBody(BaseModel):
    observacion: str


class EntregarBody(BaseModel):
    recibidoPorId: Optional[str] = None       # si None usa el receptor que firmó
    firmaUrl:      Optional[str] = None        # si None usa la firma ya capturada
    notas:         Optional[str] = None


class FirmarBody(BaseModel):
    """El técnico confirma recepción en el detalle del servicio (firma virtual)."""
    recibidoPorId: Optional[str] = None        # si None usa el empleado del usuario logueado
    firmaUrl:      str                         # data-url de la firma


# ═══════════════════════════════════════════════════════════════════════════
# COMPRAS (HU-17 — tickets de compra generados desde requerimientos)
# ═══════════════════════════════════════════════════════════════════════════

class TicketCompraItemOut(BaseModel):
    id:                 str
    ticketId:           str
    materialId:         Optional[str] = None
    nombre:             str
    cantidad:           int
    cantidadComprada:   Optional[int]   = None
    unidad:             str             = ""
    precioUnitario:     Optional[float] = None
    totalItem:          Optional[float] = None
    proveedorId:        Optional[str]   = None
    proveedorNombre:    Optional[str]   = None
    canalPersonalizado: Optional[str]   = None
    factura:            Optional[str]   = None
    estadoItem:         str             = "pendiente"
    nota:               Optional[str]   = None


class TicketCompraOut(BaseModel):
    id:                   str
    codigo:               str
    requerimientoId:      Optional[str] = None
    proyectoId:           Optional[str] = None
    proyectoNombre:       str
    servicioId:           Optional[str] = None
    servicioNombre:       Optional[str] = None
    solicitanteNombre:    str
    estado:               str
    items:                List[TicketCompraItemOut]
    modoUnificado:        Optional[bool]  = None
    proveedorUnicoId:     Optional[str]   = None
    proveedorUnicoNombre: Optional[str]   = None
    canalUnico:           Optional[str]   = None
    totalEstimado:        Optional[float] = None
    totalReal:            Optional[float] = None
    responsableId:        Optional[str]   = None
    responsableNombre:    Optional[str]   = None
    nota:                 Optional[str]   = None
    creadoEn:             str
    actualizadoEn:        Optional[str]   = None


class ComprasListResponse(BaseModel):
    items:    List[TicketCompraOut]
    total:    int
    page:     int
    pageSize: int


class ProcesarCompraItemBody(BaseModel):
    itemId:             str
    cantidadComprada:   int = 0
    precioUnitario:     Optional[float] = None
    proveedorId:        Optional[str]   = None
    proveedorNombre:    Optional[str]   = None
    canalPersonalizado: Optional[str]   = None
    factura:            Optional[str]   = None
    nota:               Optional[str]   = None


class ProcesarCompraBody(BaseModel):
    modoUnificado:        bool
    proveedorUnicoId:     Optional[str]   = None
    proveedorUnicoNombre: Optional[str]   = None
    canalUnico:           Optional[str]   = None
    nota:                 Optional[str]   = None
    completado:           bool            = False
    items:                List[ProcesarCompraItemBody] = []


class CancelarCompraBody(BaseModel):
    motivo: Optional[str] = None


class ComprasResumen(BaseModel):
    pendiente:  int = 0
    en_proceso: int = 0
    completado: int = 0
    cancelado:  int = 0


# ═══════════════════════════════════════════════════════════════════════════
# PROVEEDORES
# ═══════════════════════════════════════════════════════════════════════════

class ProveedorOut(BaseModel):
    id:        str
    nombre:    str
    ruc:       Optional[str] = None
    contacto:  Optional[str] = None
    email:     Optional[str] = None
    rating:    int = 0
    categorias: List[str] = []
    activo:    bool = True


class ProveedorIn(BaseModel):
    nombre:   str
    ruc:      Optional[str] = None
    contacto: Optional[str] = None
    email:    Optional[str] = None
    rating:   int = 0

