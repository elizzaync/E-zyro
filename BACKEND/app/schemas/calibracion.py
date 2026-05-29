"""Schemas de Calibraciones + Estado operativo de equipos (Fase 3)."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, field_validator


class CalibracionIn(BaseModel):
    equipo_id:           str
    fecha_ultima:        Optional[str] = None   # ISO yyyy-mm-dd
    fecha_proxima:       Optional[str] = None
    empresa_responsable: Optional[str] = None
    observacion:         Optional[str] = None


class CalibracionOut(BaseModel):
    id:                  str
    equipo_id:           str
    equipo_nombre:       Optional[str] = None
    fecha_ultima:        Optional[str] = None
    fecha_proxima:       Optional[str] = None
    empresa_responsable: Optional[str] = None
    certificado_url:     Optional[str] = None
    observacion:         Optional[str] = None


class CertificadoIn(BaseModel):
    archivo_base64: str


# ── Estado operativo ─────────────────────────────────────────────────────────
class EstadoMovIn(BaseModel):
    cantidad: int
    motivo:   Optional[str] = None

    @field_validator("cantidad")
    @classmethod
    def _pos(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("cantidad debe ser > 0")
        return v


class EquipoEstadoOut(BaseModel):
    equipo_id:            str
    nombre:               Optional[str] = None
    cantidad:             int
    cantidad_inoperativa: int
    estado_operativo:     str
