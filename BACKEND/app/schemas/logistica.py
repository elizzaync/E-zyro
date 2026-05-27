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

