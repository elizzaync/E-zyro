"""Schemas de Inspección ITSE (Fase 5)."""
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel


class InspeccionIn(BaseModel):
    cliente_id:    Optional[str] = None
    ubicacion_id:  Optional[str] = None
    zona_id:       Optional[str] = None
    modo:          str = "tablero"   # tablero|zona
    observaciones: Optional[str] = None


class InspeccionOut(BaseModel):
    id:            str
    cliente_id:    Optional[str] = None
    ubicacion_id:  Optional[str] = None
    zona_id:       Optional[str] = None
    modo:          str
    fecha:         Optional[str] = None
    estado:        str
    pdf_url:       Optional[str] = None
    observaciones: Optional[str] = None


class TableroIn(BaseModel):
    nombre:      str
    ambiente:    Optional[str] = None
    descripcion: Optional[str] = None


class TableroOut(BaseModel):
    id:           str
    inspeccion_id: str
    nombre:       str
    ambiente:     Optional[str] = None
    descripcion:  Optional[str] = None


class ItemIn(BaseModel):
    descripcion: str
    resultado:   str = "conforme"   # conforme|observado|no_conforme
    observacion: Optional[str] = None
    tablero_id:  Optional[str] = None


class ItemOut(BaseModel):
    id:          str
    tablero_id:  Optional[str] = None
    descripcion: str
    resultado:   str
    observacion: Optional[str] = None


class FotoIn(BaseModel):
    imagen_base64: str
    tablero_id:    Optional[str] = None
    descripcion:   Optional[str] = None
