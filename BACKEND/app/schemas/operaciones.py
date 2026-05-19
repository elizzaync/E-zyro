from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel


# ── Salida ────────────────────────────────────────────────────

class EvidenciaOut(BaseModel):
    id: str
    url_cloudinary: str
    descripcion: Optional[str]
    etapa: Optional[str]
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


class ProyectoListOut(BaseModel):
    id: str
    orden_trabajo: str
    nombre_proyecto: str
    estado: str
    fecha_inicio: Optional[str]
    cliente: str
    total_servicios: int
    servicios_completados: int
    jefe_nombre: str


class KpisProyectosOut(BaseModel):
    total_proyectos: int
    servicios_completados: int
    servicios_pendientes: int
    tasa_avance: int


class ProyectosConKpisOut(BaseModel):
    kpis: KpisProyectosOut
    proyectos: List[ProyectoListOut]


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


# ── HU-18: Equipos con tipo y progreso ───────────────────────────────────────

class EquipoItemOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str]
    ubicacion: Optional[str]
    estado: str
    tipo: Optional[str] = None
    progreso_porcentaje: Optional[float] = None


# ── HU-19: Historial de mantenimientos ───────────────────────────────────────

class FotoEvidenciaOut(BaseModel):
    url: str
    tipo: str
    paso: Optional[str] = None
    fecha: Optional[str] = None


class MantenimientoHistorialOut(BaseModel):
    id: str
    fecha: str
    tecnico_nombre: str
    proyecto_nombre: str
    estado: str
    fotos: List[FotoEvidenciaOut] = []
    informe_pdf_url: Optional[str] = None
    evidencias_zip_url: Optional[str] = None


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


class AgregarBorradorBody(BaseModel):
    material_id:    Optional[str] = None
    nombre:         Optional[str] = None
    unidad:         Optional[str] = None
    cantidad:       int
    especificacion: Optional[str] = None


