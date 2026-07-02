from __future__ import annotations
from datetime import date, datetime
from typing import Any, Optional
from pydantic import BaseModel

from .operaciones import ProcedimientoOut


class EquipoIntervenidoIn(BaseModel):
    proyecto_id:      Optional[str]  = None
    cliente_id:       Optional[str]  = None
    ubicacion_id:     Optional[str]  = None
    zona_id:          Optional[str]  = None
    area_id:          Optional[str]  = None
    area_descripcion: Optional[str]  = None
    nombre:           str
    codigo:           Optional[str]  = None
    ubicacion_referencia: Optional[str] = None
    tipo_equipo_id:   Optional[str]  = None
    marca:            Optional[str]  = None
    modelo:           Optional[str]  = None
    numero_serie:     Optional[str]  = None
    estado:           Optional[str]  = "operativo"
    fecha_instalacion: Optional[date] = None
    ultimo_mantenimiento:  Optional[date] = None
    proximo_mantenimiento: Optional[date] = None
    frecuencia_meses:      Optional[int]  = 6
    ficha_tecnica:    Optional[dict[str, Any]] = None
    observaciones:    Optional[str]  = None
    activo:           Optional[bool] = True


class EquipoIntervenidoOut(BaseModel):
    id:               str
    empresa_id:       str
    proyecto_id:      Optional[str]
    cliente_id:       Optional[str]
    ubicacion_id:     Optional[str]
    zona_id:          Optional[str]
    area_id:          Optional[str]
    area_descripcion: Optional[str]
    nombre:           str
    codigo:           Optional[str]
    ubicacion_referencia: Optional[str] = None
    tipo_equipo_id:   Optional[str]
    marca:            Optional[str]
    modelo:           Optional[str]
    numero_serie:     Optional[str]
    estado:           str
    fecha_instalacion: Optional[date]
    ultimo_mantenimiento:  Optional[date] = None
    proximo_mantenimiento: Optional[date] = None
    frecuencia_meses:      Optional[int]  = None
    ficha_tecnica:    Optional[dict[str, Any]]
    observaciones:    Optional[str]
    activo:           bool
    created_at:       datetime
    updated_at:       Optional[datetime]

    # Nombres resueltos (joins)
    proyecto_nombre:   Optional[str] = None
    cliente_nombre:    Optional[str] = None
    ubicacion_nombre:  Optional[str] = None
    zona_nombre:       Optional[str] = None
    area_nombre:       Optional[str] = None
    tipo_equipo_nombre: Optional[str] = None

    # Servicio al que está vinculado ahora mismo (si alguien inició una
    # inspección/mantenimiento sobre este equipo dentro de un servicio).
    proyecto_servicio_id:     Optional[str] = None
    proyecto_servicio_nombre: Optional[str] = None

    # Procedimientos designados del servicio al que está vinculado (solo en
    # el detalle; la lista los omite para no pagar el join por cada fila).
    procedimientos: list[ProcedimientoOut] = []

    class Config:
        from_attributes = True


# ── Historial de mantenimientos del equipo intervenido ───────────────────────

class MantenimientoEquipoIn(BaseModel):
    """Registro de un mantenimiento ejecutado sobre el equipo."""
    fecha:            Optional[date] = None     # default: hoy
    tipo:             Optional[str]  = "preventivo"   # preventivo|correctivo|inspeccion|otro
    descripcion:      Optional[str]  = None
    realizado_por:    Optional[str]  = None     # default: usuario autenticado
    frecuencia_meses: Optional[int]  = None     # override de la frecuencia del equipo


class MantenimientoEquipoOut(BaseModel):
    id:                    str
    equipo_intervenido_id: str
    fecha:                 date
    tipo:                  str
    descripcion:           Optional[str] = None
    realizado_por:         Optional[str] = None
    proximo_calculado:     Optional[date] = None
    created_at:            datetime

    class Config:
        from_attributes = True
