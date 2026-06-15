"""Schemas del repositorio central de Garantías (cartas de garantía)."""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel


class GarantiaOut(BaseModel):
    id:                 str
    servicio_id:        Optional[str] = None
    servicio_nombre:    Optional[str] = None
    proyecto_id:        Optional[str] = None
    proyecto_nombre:    Optional[str] = None
    cliente_id:         Optional[str] = None
    cliente_nombre:     Optional[str] = None
    razon_social:       Optional[str] = None
    lugar:              Optional[str] = None
    fecha_operatividad: Optional[str] = None
    vigencia_garantia:  Optional[str] = None
    estado:             str           # vigente | por_vencer | vencida | sin_fecha
    dias_para_vencer:   Optional[int] = None
    documento_pdf_url:  Optional[str] = None
    created_at:         Optional[str] = None


class GarantiaManualIn(BaseModel):
    """Subida manual de una garantía (PDF) por si alguna no se generó desde el
    sistema. Se liga a un servicio si se indica; si no, queda con razón social."""
    archivo_base64:     str
    archivo_nombre:     Optional[str] = None
    razon_social:       Optional[str] = None
    cliente_id:         Optional[str] = None   # para inferir razón social si falta
    servicio_id:        Optional[str] = None
    lugar:              Optional[str] = None
    direccion:          Optional[str] = None
    fecha_operatividad: Optional[str] = None   # ISO yyyy-mm-dd
    vigencia_garantia:  Optional[str] = None   # ISO yyyy-mm-dd
