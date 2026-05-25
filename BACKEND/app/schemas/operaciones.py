from __future__ import annotations
from typing import List, Optional, Dict
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
    responsable_id: Optional[str] = None      # empleado.id del responsable
    fecha_inicio_tarea: Optional[str] = None  # YYYY-MM-DD raw (para Gantt)
    fecha_limite: Optional[str] = None        # YYYY-MM-DD raw (fin planificado)


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
    # Campos extra para el modal de edición
    catalogo_servicio_id: Optional[str] = None
    nombre: Optional[str] = None          # alias de tipo_servicio
    fecha_programada: Optional[str] = None  # YYYY-MM-DD raw
    fecha_inicio: Optional[str] = None
    fecha_fin: Optional[str] = None


class ProyectoListOut(BaseModel):
    id: str
    orden_trabajo: str
    nombre_proyecto: str
    estado: str
    fecha_inicio: Optional[str]
    fecha_fin_estimada: Optional[str] = None   # para Gantt / cronograma
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
    fecha_fin: Optional[str] = None            # fecha real de cierre, para Gantt
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
    cantidad:       Optional[int] = None
    nombre:         Optional[str] = None
    especificacion: Optional[str] = None


class AgregarBorradorBody(BaseModel):
    material_id:    Optional[str] = None
    nombre:         Optional[str] = None
    unidad:         Optional[str] = None
    cantidad:       int
    especificacion: Optional[str] = None


# ── HU-MANT: Checklist de equipo (pasos + evidencias) ────────────────────────

class PasoChecklistOut(BaseModel):
    id: str
    nombre: str
    descripcion: str = ""
    orden: int
    estado: str
    fotos_urls: List[str] = []


class ChecklistEquipoOut(BaseModel):
    equipo_id: str
    equipo_nombre: str
    pasos: List[PasoChecklistOut] = []


class PatchMantenimientoBody(BaseModel):
    status: str  # 'pendiente' | 'en_proceso' | 'completado'


# ══════════════════════════════════════════════════════════════════════════════
# CRUD: Clientes, Catálogo, Personal, Proyectos, Servicios
# ══════════════════════════════════════════════════════════════════════════════

# ── Clientes ─────────────────────────────────────────────────────────────────
class ClienteOut(BaseModel):
    id: str
    razon_social: str
    ruc: Optional[str] = None


# ── Catálogo de Servicios ─────────────────────────────────────────────────────
class CatalogoServicioOut(BaseModel):
    id: str
    nombre: str
    tipo_trabajo: str
    descripcion: Optional[str] = None


# ── Personal / Técnicos ───────────────────────────────────────────────────────
class TecnicoOut(BaseModel):
    id: str               # empleado.id
    usuario_id: str
    nombre: str
    apellido: str
    cargo: str
    foto_url: Optional[str] = None
    grupo_nombre: Optional[str] = None   # alias de grupo_actual (compat)
    grupo_id: Optional[str] = None
    grupo_actual: Optional[str] = None   # nombre del grupo actual (HU-13 alert)


class GrupoConMiembrosOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str] = None
    jefe_nombre: str
    miembros: List[TecnicoOut]


class PersonalTecnicosOut(BaseModel):
    tecnicos: List[TecnicoOut]
    grupos: List[GrupoConMiembrosOut]


# ── Proyecto — Detalle para edición ──────────────────────────────────────────
class ProyectoEditOut(BaseModel):
    id: str
    nombre_proyecto: str
    cliente_id: str
    orden_trabajo: str
    estado: str
    fecha_inicio: Optional[str] = None        # YYYY-MM-DD
    fecha_fin_estimada: Optional[str] = None  # YYYY-MM-DD
    zona_ejecucion: Optional[str] = None
    alcance: Optional[str] = None
    jefe_nombre: Optional[str] = None


# ── Body: Crear Proyecto ──────────────────────────────────────────────────────
class CrearProyectoBody(BaseModel):
    nombre_proyecto: str
    cliente_id: str
    orden_trabajo: str
    estado: str = "Pendiente"
    fecha_inicio: Optional[str] = None
    fecha_fin_estimada: Optional[str] = None
    zona_ejecucion: Optional[str] = None
    alcance: Optional[str] = None


# ── Body: Actualizar Proyecto ─────────────────────────────────────────────────
class ActualizarProyectoBody(BaseModel):
    nombre_proyecto: Optional[str] = None
    cliente_id: Optional[str] = None
    orden_trabajo: Optional[str] = None
    estado: Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin_estimada: Optional[str] = None
    zona_ejecucion: Optional[str] = None
    alcance: Optional[str] = None


# ── Body: Crear Servicio ──────────────────────────────────────────────────────
class CrearServicioBody(BaseModel):
    nombre: str
    catalogo_servicio_id: str
    descripcion: Optional[str] = None
    estado: str = "Pendiente"
    fecha_programada: Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin: Optional[str] = None


# ── Body: Actualizar Servicio ─────────────────────────────────────────────────
class ActualizarServicioBody(BaseModel):
    nombre: Optional[str] = None
    catalogo_servicio_id: Optional[str] = None
    descripcion: Optional[str] = None
    estado: Optional[str] = None
    fecha_programada: Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin: Optional[str] = None


# ── Body: Configurar Servicio (equipo + procedimientos/Gantt) ─────────────────
class ProcedimientoConfigBody(BaseModel):
    id: Optional[str] = None        # si ya existe (modo editar)
    nombre: str
    responsable_id: str             # empleado.id
    fecha_inicio: str               # YYYY-MM-DD
    fecha_fin: str                  # YYYY-MM-DD


class ConfigurarServicioBody(BaseModel):
    equipo: List[str]                       # list of empleado.id
    procedimientos: List[ProcedimientoConfigBody]
    lider_id: Optional[str] = None          # empleado.id del responsable del servicio


# ── Body: Validar cruce de horarios ──────────────────────────────────────────
class ValidarHorarioBody(BaseModel):
    empleado_id: str                        # empleado.id a validar
    fecha_inicio: str                       # YYYY-MM-DD
    fecha_fin: str                          # YYYY-MM-DD
    excluir_servicio_id: Optional[str] = None  # no reportar conflictos del mismo servicio


# ── Body: Nota / Seguimiento ──────────────────────────────────────────────────
class AgregarNotaBody(BaseModel):
    descripcion: str


