"""Schemas de la Galería Global (índice recurso_cloudinary)."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel


class RecursoOut(BaseModel):
    id:           str
    secure_url:   str
    public_id:    str
    recurso_tipo: str
    entidad_tipo: str
    entidad_id:   Optional[str] = None
    descripcion:  Optional[str] = None
    formato:      Optional[str] = None
    bytes:        Optional[int] = None
    created_at:   Optional[str] = None


class RecursoSubirIn(BaseModel):
    """Subida libre a la galería."""
    imagen_base64: str
    descripcion:   Optional[str] = None
    entidad_tipo:  Optional[str] = "galeria"
    entidad_id:    Optional[str] = None
