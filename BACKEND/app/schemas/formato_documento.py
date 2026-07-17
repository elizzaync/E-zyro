"""Schemas del módulo Biblioteca de Formatos (/formatos)."""
from typing import Optional

from pydantic import BaseModel


class FormatoVersionOut(BaseModel):
    id: str
    numero_version: int
    archivo_url: str
    nombre_archivo: Optional[str] = None
    tamano_bytes: Optional[int] = None
    nota: Optional[str] = None
    origen: str
    subido_por_nombre: Optional[str] = None
    created_at: Optional[str] = None
    es_vigente: bool = False


class FormatoOut(BaseModel):
    id: str
    nombre: str
    tipo_formato: Optional[str] = None
    version_actual: int
    archivo_url: Optional[str] = None          # URL de la versión vigente
    nombre_archivo: Optional[str] = None
    actualizado_por_nombre: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    total_versiones: int = 1


class FormatoCrearIn(BaseModel):
    nombre: str
    tipo_formato: Optional[str] = None
    nota: Optional[str] = None
    archivo_base64: str
    archivo_nombre: Optional[str] = None


class FormatoActualizarIn(BaseModel):
    # Metadatos opcionales; si viene archivo_base64 se crea una NUEVA versión.
    nombre: Optional[str] = None
    tipo_formato: Optional[str] = None
    nota: Optional[str] = None
    archivo_base64: Optional[str] = None
    archivo_nombre: Optional[str] = None
