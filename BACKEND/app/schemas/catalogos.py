"""Schemas de catálogos base: Ubicación, Zona, Área."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel


# ── Ubicación ───────────────────────────────────────────────────────────────
class UbicacionIn(BaseModel):
    nombre: str
    region: Optional[str] = None


class UbicacionOut(BaseModel):
    id:     str
    nombre: str
    region: Optional[str] = None


# ── Zona ──────────────────────────────────────────────────────────────────--
class ZonaIn(BaseModel):
    nombre:       str
    tipo:         Optional[str] = None
    ubicacion_id: Optional[str] = None


class ZonaOut(BaseModel):
    id:               str
    nombre:           str
    tipo:             Optional[str] = None
    ubicacion_id:     Optional[str] = None
    ubicacion_nombre: Optional[str] = None


# ── Área ─────────────────────────────────────────────────────────────────--─
class AreaIn(BaseModel):
    nombre: str


class AreaOut(BaseModel):
    id:     str
    nombre: str
