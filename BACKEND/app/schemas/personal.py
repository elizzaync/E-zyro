"""Schemas del módulo Personal/RR.HH. (Punto 3.1 — historial consolidado)."""
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel


class EmpleadoOut(BaseModel):
    id:                 str
    usuario_id:         str
    nombre:             Optional[str] = None     # nombre + apellido del usuario
    codigo:             Optional[str] = None
    cargo:              Optional[str] = None
    area:               Optional[str] = None
    tipo:               Optional[str] = None
    fecha_ingreso:      Optional[str] = None
    fecha_fin_contrato: Optional[str] = None
    activo:             bool = True
    foto_url:           Optional[str] = None


class ContratoItem(BaseModel):
    tipo:         str
    fecha_inicio: Optional[str] = None
    fecha_fin:    Optional[str] = None
    estado:       Optional[str] = None


class AsistenciaResumen(BaseModel):
    total:      int = 0
    validados:  int = 0
    pendientes: int = 0
    rechazados: int = 0


class MarcacionItem(BaseModel):
    tipo:       str
    fecha_hora: Optional[str] = None
    estado:     Optional[str] = None


class SolicitudItem(BaseModel):
    tipo:         str
    estado:       Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin:    Optional[str] = None
    url_pdf:      Optional[str] = None


class EppEntregaItem(BaseModel):
    fecha:  Optional[str] = None
    estado: Optional[str] = None
    items:  int = 0
    pdf_url: Optional[str] = None


class EvaluacionResumen(BaseModel):
    total:            int = 0
    promedio_general: Optional[float] = None      # promedio de puntajes (1-10)
    ultimo_periodo:   Optional[str] = None


class HistorialPersonal(BaseModel):
    empleado:    EmpleadoOut
    contratos:   List[ContratoItem] = []
    asistencia:  AsistenciaResumen
    marcaciones: List[MarcacionItem] = []         # últimas N
    solicitudes: List[SolicitudItem] = []
    epp:         List[EppEntregaItem] = []
    evaluaciones: EvaluacionResumen
