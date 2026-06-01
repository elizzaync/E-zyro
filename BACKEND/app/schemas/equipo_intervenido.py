from __future__ import annotations
from datetime import date, datetime
from typing import Any, Optional
from pydantic import BaseModel


class EquipoIntervenidoIn(BaseModel):
    proyecto_id:      Optional[str]  = None
    cliente_id:       Optional[str]  = None
    ubicacion_id:     Optional[str]  = None
    zona_id:          Optional[str]  = None
    area_descripcion: Optional[str]  = None
    nombre:           str
    codigo:           Optional[str]  = None
    tipo_equipo_id:   Optional[str]  = None
    marca:            Optional[str]  = None
    modelo:           Optional[str]  = None
    numero_serie:     Optional[str]  = None
    estado:           Optional[str]  = "operativo"
    fecha_instalacion: Optional[date] = None
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
    area_descripcion: Optional[str]
    nombre:           str
    codigo:           Optional[str]
    tipo_equipo_id:   Optional[str]
    marca:            Optional[str]
    modelo:           Optional[str]
    numero_serie:     Optional[str]
    estado:           str
    fecha_instalacion: Optional[date]
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
    tipo_equipo_nombre: Optional[str] = None

    class Config:
        from_attributes = True
