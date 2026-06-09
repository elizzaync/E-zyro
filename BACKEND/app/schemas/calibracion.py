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
    total_eventos:       int = 0


class CertificadoIn(BaseModel):
    archivo_base64: str


# ── Historial de calibraciones (eventos) ─────────────────────────────────────
class EventoIn(BaseModel):
    equipo_id:           str
    fecha_realizada:     str                        # ISO yyyy-mm-dd (requerida)
    periodicidad_meses:  Optional[int] = None       # calcula fecha_proxima si no se envía
    fecha_proxima:       Optional[str] = None
    realizada_por:       Optional[str] = None
    empresa_responsable: Optional[str] = None
    numero_certificado:  Optional[str] = None
    resultado:           Optional[str] = None       # conforme|observado
    observacion:         Optional[str] = None

    @field_validator("periodicidad_meses")
    @classmethod
    def _periodo_pos(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v <= 0:
            raise ValueError("periodicidad_meses debe ser > 0")
        return v


class EventoOut(BaseModel):
    id:                  str
    equipo_id:           str
    equipo_nombre:       Optional[str] = None
    fecha_realizada:     Optional[str] = None
    periodicidad_meses:  Optional[int] = None
    fecha_proxima:       Optional[str] = None
    realizada_por:       Optional[str] = None
    empresa_responsable: Optional[str] = None
    numero_certificado:  Optional[str] = None
    resultado:           Optional[str] = None
    certificado_url:     Optional[str] = None
    observacion:         Optional[str] = None


class CertificadoEventoIn(BaseModel):
    archivo_base64: str
    extension:      Optional[str] = "pdf"           # pdf|jpg|png…


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
