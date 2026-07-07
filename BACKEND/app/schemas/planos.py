from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel


# ── Carpetas ─────────────────────────────────────────────────────────────────
class CarpetaIn(BaseModel):
    nombre: str
    padre_id: Optional[str] = None
    proyecto_id: Optional[str] = None


class CarpetaRename(BaseModel):
    nombre: str


class CarpetaOut(BaseModel):
    id: str
    nombre: str
    padre_id: Optional[str] = None
    proyecto_id: Optional[str] = None
    sub_carpetas: int = 0
    planos: int = 0
    created_at: Optional[str] = None


# ── Planos / versiones ───────────────────────────────────────────────────────
class VersionOut(BaseModel):
    id: str
    version: str
    url: str
    formato: Optional[str] = None
    bytes: Optional[int] = None
    fecha: Optional[str] = None
    es_activa: bool = False
    subido_por: Optional[str] = None


class PlanoOut(BaseModel):
    id: str
    nombre: str
    disciplina: Optional[str] = None
    descripcion: Optional[str] = None
    carpeta_id: Optional[str] = None
    proyecto_id: Optional[str] = None
    url: Optional[str] = None
    formato: Optional[str] = None
    bytes: Optional[int] = None
    version_activa: Optional[str] = None
    num_versiones: int = 0
    created_at: Optional[str] = None


class PlanoDetalleOut(PlanoOut):
    versiones: List[VersionOut] = []


class PlanoIn(BaseModel):
    nombre: str
    archivo_base64: str
    filename: str
    disciplina: Optional[str] = None
    descripcion: Optional[str] = None
    carpeta_id: Optional[str] = None
    proyecto_id: Optional[str] = None


class VersionIn(BaseModel):
    archivo_base64: str
    filename: str
    version: Optional[str] = None


class PlanoMover(BaseModel):
    """Mueve un plano a otra carpeta (drag & drop tipo Drive). carpeta_id=None
    lo mueve a la raíz."""
    carpeta_id: Optional[str] = None
