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
    codigo:       str
    nombre:       str
    categoria:    str
    unidad:       str
    descripcion:  Optional[str] = None
    cantidad:     int = 0
    stockMinimo: int = 0
    almacen:     str = "Almacén Central"
    precio:      Optional[float] = None
    activo:      bool = True


class MaterialPatch(BaseModel):
    codigo:       Optional[str] = None
    nombre:       Optional[str] = None
    categoria:    Optional[str] = None
    unidad:       Optional[str] = None
    descripcion:  Optional[str] = None
    cantidad:     Optional[int] = None
    stockMinimo: Optional[int] = None
    almacen:     Optional[str] = None
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
    tipo:        str
    marca:       Optional[str] = None
    modelo:      Optional[str] = None
    numeroSerie: Optional[str] = None
    ubicacion:   Optional[str] = None
    cantidad:    int
    estado:      EstadoEquipo
    requiereMantenimiento:     bool
    frecuenciaMantenimiento:   FrecuenciaMant
    proximaFechaMantenimiento: Optional[str] = None
    fechaAdquisicion:          Optional[str] = None
    fichaTecnica:              Optional[str] = None


class EquipoIn(BaseModel):
    codigo:      str
    nombre:      str
    clase:       ClaseArticulo = "equipo"
    tipo:        str
    marca:       Optional[str] = None
    modelo:      Optional[str] = None
    numeroSerie: Optional[str] = None
    ubicacion:   Optional[str] = None
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
    tipo:        Optional[str] = None
    marca:       Optional[str] = None
    modelo:      Optional[str] = None
    numeroSerie: Optional[str] = None
    ubicacion:   Optional[str] = None
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
