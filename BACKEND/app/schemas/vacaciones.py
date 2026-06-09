"""Schemas de Vacaciones por ley (Punto 3.3)."""
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, field_validator


# ── Configuración ────────────────────────────────────────────────────────────
class ConfigOut(BaseModel):
    regimen:          str
    dias_por_anio:    int
    tope_acumulacion: int


class ConfigIn(BaseModel):
    regimen:          str = "general"           # general|remype|otro
    dias_por_anio:    Optional[int] = None      # si None, se deriva del régimen
    tope_acumulacion: Optional[int] = None

    @field_validator("dias_por_anio", "tope_acumulacion")
    @classmethod
    def _pos(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v <= 0:
            raise ValueError("debe ser > 0")
        return v


# ── Saldo ────────────────────────────────────────────────────────────────────
class SaldoOut(BaseModel):
    empleado_id:    str
    empleado_nombre: Optional[str] = None
    fecha_ingreso:  Optional[str] = None
    meses_servicio: int = 0
    dias_por_anio:  int = 0
    devengado:      float = 0.0    # días ganados desde el ingreso
    gozado:         int = 0        # días aprobados
    disponible:     float = 0.0    # min(devengado - gozado, tope)
    tope_acumulacion: int = 0


# ── Solicitudes ──────────────────────────────────────────────────────────────
class SolicitudIn(BaseModel):
    empleado_id:  Optional[str] = None          # admin puede solicitar por otro; si None = propio
    fecha_inicio: str
    fecha_fin:    str
    motivo:       Optional[str] = None


class SolicitudOut(BaseModel):
    id:              str
    empleado_id:     str
    empleado_nombre: Optional[str] = None
    fecha_inicio:    Optional[str] = None
    fecha_fin:       Optional[str] = None
    dias:            int
    estado:          str
    motivo:          Optional[str] = None
    fecha_resolucion: Optional[str] = None
