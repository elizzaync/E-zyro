"""Schemas del repositorio de documentos de cumplimiento/SST (homologaciones,
ATS, PETAR, etc.)."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel


class DocumentoSstOut(BaseModel):
    id:                str
    tipo:              str
    titulo:            str
    cliente_id:        Optional[str] = None
    cliente_nombre:    Optional[str] = None
    entidad_emisora:   Optional[str] = None
    codigo:            Optional[str] = None
    fecha_emision:     Optional[str] = None
    fecha_vencimiento: Optional[str] = None
    estado:            str           # vigente | por_vencer | vencida | sin_fecha
    dias_para_vencer:  Optional[int] = None
    archivo_url:       Optional[str] = None
    nombre_archivo:    Optional[str] = None
    formato:           Optional[str] = None
    observaciones:     Optional[str] = None
    created_at:        Optional[str] = None


class DocumentoSstCrearIn(BaseModel):
    titulo:            str
    tipo:              str           = "homologacion"
    cliente_id:        Optional[str] = None
    entidad_emisora:   Optional[str] = None
    codigo:            Optional[str] = None
    fecha_emision:     Optional[str] = None   # ISO yyyy-mm-dd
    fecha_vencimiento: Optional[str] = None   # ISO yyyy-mm-dd
    observaciones:     Optional[str] = None
    archivo_base64:    Optional[str] = None   # PDF o imagen
    archivo_nombre:    Optional[str] = None   # para deducir la extensión


class DocumentoSstEditarIn(BaseModel):
    titulo:            Optional[str] = None
    tipo:              Optional[str] = None
    cliente_id:        Optional[str] = None
    entidad_emisora:   Optional[str] = None
    codigo:            Optional[str] = None
    fecha_emision:     Optional[str] = None
    fecha_vencimiento: Optional[str] = None
    observaciones:     Optional[str] = None
    archivo_base64:    Optional[str] = None   # si viene, reemplaza el archivo
    archivo_nombre:    Optional[str] = None
