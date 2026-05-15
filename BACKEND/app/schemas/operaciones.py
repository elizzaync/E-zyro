from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel


# ── Salida ────────────────────────────────────────────────────

class EvidenciaOut(BaseModel):
    id: str
    url_cloudinary: str
    descripcion: Optional[str]
    fecha_captura: str


class ProcedimientoOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str]
    orden: int
    estado: str
    evidencias: List[EvidenciaOut] = []


class MiembroEquipoOut(BaseModel):
    id: str
    nombre: str
    apellido: str
    foto_url: Optional[str]
    cargo: str
    rol_proyecto: str


class ItemMaterialOut(BaseModel):
    id: str
    requerimiento_id: str
    nombre: str
    unidad: str
    cantidad: int
    estado_req: str


class NotaOut(BaseModel):
    id: str
    fecha: str
    texto: str
    autor: str


class ServicioDetalleOut(BaseModel):
    id: str
    proyecto_id: str
    cliente: str
    tipo_servicio: str
    ubicacion: str
    fecha_str: str
    hora_str: str
    descripcion: str
    estado: str
    progreso: float
    equipo: List[MiembroEquipoOut]
    procedimientos: List[ProcedimientoOut]
    materiales_asignados: List[ItemMaterialOut]
    materiales_solicitados: List[ItemMaterialOut]
    notas: List[NotaOut]


class ProyectoListOut(BaseModel):
    id: str
    orden_trabajo: str
    nombre_proyecto: str
    estado: str
    fecha_inicio: Optional[str]
    cliente: str
    total_servicios: int


class ProyectoServicioListOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str]
    estado: str
    orden: int
    fecha_programada: Optional[str]
    estado_color: str


class DashboardMetricaOut(BaseModel):
    id: str
    titulo: str
    valor: int
    colorIcono: str
    resaltado: bool = False


class DashboardServicioOut(BaseModel):
    id: str
    cliente: str
    tipoServicio: str
    ubicacion: str
    fechaStr: str
    horaStr: str
    estado: str
    alerta: bool = False


# ── Entrada ───────────────────────────────────────────────────

class ActualizarEstadoBody(BaseModel):
    estado: str


class ActualizarProcedimientoBody(BaseModel):
    estado: str


class SolicitarMaterialBody(BaseModel):
    material_id: str
    cantidad: int


class ActualizarReqDetalleBody(BaseModel):
    cantidad: Optional[int] = None


class AgregarNotaBody(BaseModel):
    descripcion: str
