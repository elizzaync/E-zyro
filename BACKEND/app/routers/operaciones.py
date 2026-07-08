"""
Router: /operaciones
Gestión completa del módulo de Operaciones / Detalle de Servicio.
"""
from __future__ import annotations

import io
import json
import logging
import re
import unicodedata
import uuid as _uuid
import zipfile
from datetime import date, datetime

logger = logging.getLogger(__name__)

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Query, UploadFile, File, Form, status
from fastapi.responses import StreamingResponse
from typing import List, Optional

from sqlalchemy import func, or_, case, cast, Text as SAText
from sqlalchemy.exc import IntegrityError, ProgrammingError
from sqlalchemy.orm import Session, aliased

from ..core.security import verificar_token, es_superadmin
from ..core.permisos import (
    exigir_permiso, es_tecnico, es_jefe_operaciones,
    exigir_no_tecnico, exigir_solo_admin,
)
from ..core.audit_context import set_justificacion
from ..core.tz import fmt_lima
from ..db.database import get_db
import requests as _requests
from ..services.cloudinary_service import subir_archivo_cloudinary, subir_pdf_bytes_cloudinary, subir_bytes_raw_cloudinary

# Modelos ORM
from ..models.proyecto_servicio import ProyectoServicio
from ..models.proyecto import Proyecto
from ..models.proyecto_detalle import ProyectoDetalle
from ..models.proyecto_miembro import ProyectoMiembro
from ..models.cliente import Cliente
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.procedimiento import Procedimiento
from ..models.tarea import Tarea
from ..models.plantilla_procedimiento import PlantillaProcedimiento
from ..models.evidencia_procedimiento import EvidenciaProcedimiento
from ..models.requerimiento import Requerimiento, RequerimientoDetalle
from ..models.material import Material, Stock
from ..models.equipo import Equipo
from ..models.prestamo import Prestamo, PrestamoItem
from ..models.tipo_equipo import TipoEquipo
from ..models.orden_mantenimiento import OrdenMantenimiento
from ..models.evidencia_mantenimiento import EvidenciaMantenimiento
from ..models.informe_tecnico import InformeTecnico
from ..models.paso_mantenimiento import PasoMantenimiento
from ..models.equipo_intervenido import EquipoIntervenido
from ..models.historial_inspeccion import HistorialInspeccion
from ..models.historial_mantenimiento import HistorialMantenimiento
from ..models.ubicacion import Ubicacion
from ..models.zona import Zona
from ..models.catalogo_servicio import CatalogoServicio
from ..models.grupo_trabajo import GrupoTrabajo, GrupoMiembro
from ..models.seguimiento_proyecto import SeguimientoProyecto
from ..models.rol import Rol
from ..models.usuario_rol import UsuarioRol

# Schemas Pydantic
from ..schemas.operaciones import (
    ServicioDetalleOut,
    MiembroEquipoOut,
    ProcedimientoOut,
    TareaOut,
    PlantillaProcedimientoIn,
    PlantillaProcedimientoOut,
    ProcesoItem,
    EvidenciaOut,
    ItemMaterialOut,
    ActualizarEstadoBody,
    ActualizarProcedimientoBody,
    SolicitarMaterialBody,
    ActualizarReqDetalleBody,
    AgregarBorradorBody,
    ProyectoListOut,
    ProyectoServicioListOut,
    KpisProyectosOut,
    ProyectosConKpisOut,
    PaginacionMeta,
    ServiciosPaginadosOut,
    EquipoItemOut,
    MantenimientoHistorialOut,
    FotoEvidenciaOut,
    ChecklistEquipoOut,
    PasoChecklistOut,
    PatchMantenimientoBody,
    # CRUD nuevos
    ClienteOut,
    CatalogoServicioOut,
    CatalogoServicioIn,
    CatalogoServicioEstadoBody,
    TecnicoOut,
    GrupoConMiembrosOut,
    PersonalTecnicosOut,
    ProyectoEditOut,
    CrearProyectoBody,
    ActualizarProyectoBody,
    CrearServicioBody,
    ActualizarServicioBody,
    ConfigurarServicioBody,
    AgregarNotaBody,
    ActualizarNotaBody,
    NotaOut,
    ValidarHorarioBody,
    PersonaServicioOut,
    SiguienteOrdenOut,
)

router = APIRouter(prefix="/operaciones", tags=["operaciones"])


# ── Helpers ───────────────────────────────────────────────────────────────────


def _extract_public_id(url: str) -> str:
    try:
        partes = url.split("/upload/")
        if len(partes) > 1:
            ruta = re.sub(r"^v\d+/", "", partes[1])
            return ruta.rsplit(".", 1)[0]
    except Exception:
        pass
    return ""


def _get_empleado_or_403(db: Session, usuario_id: str, empresa_id: str) -> Empleado:
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    if not emp:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")
    return emp


def _get_empleado_optional(db: Session, usuario_id: str, empresa_id: str) -> "Empleado | None":
    """Como _get_empleado_or_403 pero no lanza excepción.
    Úsalo en endpoints donde los administradores (sin fila en 'empleado')
    también deben poder operar.  Quien llama decide qué hacer con None."""
    return db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()


# ── GET /operaciones/proyectos/lista ─────────────────────────────────────────
# Lista básica para pickers/selectores en formularios (sin KPIs, sin paginación).
# Accesible a cualquier rol autenticado que pueda crear servicios.

@router.get("/proyectos/lista")
def get_proyectos_lista(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    JefeEmpleado = aliased(Empleado)
    JefeUsuario  = aliased(Usuario)

    base_q = (
        db.query(
            Proyecto.id,
            Proyecto.nombre_proyecto,
            Proyecto.orden_trabajo,
            Proyecto.estado,
            Cliente.razon_social.label("cliente"),
        )
        .join(Cliente, Cliente.id == Proyecto.cliente_id)
        .filter(Proyecto.empresa_id == empresa_id)
        .order_by(Proyecto.created_at.desc())
    )

    if es_tecnico(payload):
        empleado = _get_empleado_or_403(db, usuario_id, empresa_id)
        # Proyectos donde el técnico es miembro del equipo (ProyectoMiembro)
        miembro_sq = (
            db.query(ProyectoMiembro.proyecto_id)
            .filter(ProyectoMiembro.empleado_id == empleado.id)
            .subquery()
        )
        # O proyectos donde tiene tareas asignadas en el cronograma
        tarea_sq = (
            db.query(ProyectoServicio.proyecto_id)
            .join(Tarea, Tarea.proyecto_servicio_id == ProyectoServicio.id)
            .filter(
                Tarea.responsable_id == empleado.id,
                Tarea.empresa_id     == empresa_id,
            )
            .distinct()
            .subquery()
        )
        rows = base_q.filter(
            or_(Proyecto.id.in_(miembro_sq), Proyecto.id.in_(tarea_sq))
        ).all()
    else:
        rows = base_q.all()

    return [
        {
            "id":            str(r.id),
            "nombre":        r.nombre_proyecto or "",
            "orden_trabajo": r.orden_trabajo   or "",
            "estado":        r.estado          or "Pendiente",
            "cliente":       r.cliente         or "",
        }
        for r in rows
    ]


# ── GET /operaciones/proyectos ────────────────────────────────────────────────

@router.get("/proyectos", response_model=ProyectosConKpisOut)
def get_proyectos(
    q:         Optional[str] = Query(None, description="Buscar por nombre, orden de trabajo o cliente"),
    estado:    Optional[str] = Query(None, description="Filtrar por estado"),
    page:      int           = Query(1, ge=1),
    page_size: int           = Query(12, ge=1, le=100),
    payload:   dict          = Depends(verificar_token),
    db:        Session       = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    rol        = payload.get("rol", "")

    # Subquery: total de servicios por proyecto
    svc_total_sq = (
        db.query(
            ProyectoServicio.proyecto_id,
            func.count(ProyectoServicio.id).label("total"),
        )
        .group_by(ProyectoServicio.proyecto_id)
        .subquery()
    )

    # Subquery: servicios completados por proyecto
    svc_comp_sq = (
        db.query(
            ProyectoServicio.proyecto_id,
            func.count(ProyectoServicio.id).label("completados"),
        )
        .filter(ProyectoServicio.estado == "Completado")
        .group_by(ProyectoServicio.proyecto_id)
        .subquery()
    )

    # Alias para acceder al empleado y usuario del jefe sin colisionar con el empleado logueado
    JefeEmpleado = aliased(Empleado)
    JefeUsuario  = aliased(Usuario)

    base_q = (
        db.query(
            Proyecto,
            Cliente.razon_social.label("cliente"),
            func.coalesce(svc_total_sq.c.total,       0).label("total_servicios"),
            func.coalesce(svc_comp_sq.c.completados,  0).label("servicios_completados"),
            (JefeUsuario.nombre + " " + JefeUsuario.apellido).label("jefe_nombre"),
        )
        .join(Cliente,        Cliente.id        == Proyecto.cliente_id)
        .outerjoin(svc_total_sq, svc_total_sq.c.proyecto_id == Proyecto.id)
        .outerjoin(svc_comp_sq,  svc_comp_sq.c.proyecto_id  == Proyecto.id)
        .outerjoin(JefeEmpleado, JefeEmpleado.id == Proyecto.jefe_operaciones_id)
        .outerjoin(JefeUsuario,  JefeUsuario.id  == JefeEmpleado.usuario_id)
        .filter(Proyecto.empresa_id == empresa_id)
    )

    if rol == "Administrador" or es_jefe_operaciones(payload):
        # Admin y Jefe de Operaciones ven todos los proyectos de la empresa
        rows = base_q.order_by(Proyecto.created_at.desc()).all()
    elif es_tecnico(payload):
        # Técnico: proyectos donde es miembro del equipo (ProyectoMiembro) O tiene tareas asignadas
        empleado = _get_empleado_or_403(db, usuario_id, empresa_id)
        miembro_sq = (
            db.query(ProyectoMiembro.proyecto_id)
            .filter(ProyectoMiembro.empleado_id == empleado.id)
            .subquery()
        )
        tarea_sq = (
            db.query(ProyectoServicio.proyecto_id)
            .join(Tarea, Tarea.proyecto_servicio_id == ProyectoServicio.id)
            .filter(
                Tarea.responsable_id == empleado.id,
                Tarea.empresa_id     == empresa_id,
            )
            .distinct()
            .subquery()
        )
        rows = (
            base_q
            .filter(or_(Proyecto.id.in_(miembro_sq), Proyecto.id.in_(tarea_sq)))
            .order_by(Proyecto.created_at.desc())
            .all()
        )
    else:
        # Soporte, Logística, TI, Administración y cualquier otro rol registrado
        # ven todos los proyectos de la empresa.
        rows = base_q.order_by(Proyecto.created_at.desc()).all()

    # ── Aplicar filtros adicionales sobre los rows ────────────────────────────
    if estado:
        rows = [r for r in rows if (r.Proyecto.estado or "") == estado]

    if q:
        q_low = q.lower().strip()
        rows = [
            r for r in rows
            if q_low in (r.Proyecto.nombre_proyecto or "").lower()
            or q_low in (r.Proyecto.orden_trabajo or "").lower()
            or q_low in (r.cliente or "").lower()
        ]

    # KPIs calculados sobre el universo completo (sin paginar)
    all_proyectos = [
        ProyectoListOut(
            id=str(p.Proyecto.id),
            orden_trabajo=p.Proyecto.orden_trabajo or "",
            nombre_proyecto=p.Proyecto.nombre_proyecto or "",
            estado=p.Proyecto.estado or "Pendiente",
            fecha_inicio=p.Proyecto.fecha_inicio.strftime("%d %b %Y") if p.Proyecto.fecha_inicio else None,
            fecha_fin_estimada=p.Proyecto.fecha_fin_estimada.strftime("%d %b %Y") if p.Proyecto.fecha_fin_estimada else None,
            cliente=p.cliente or "Sin Cliente",
            total_servicios=int(p.total_servicios),
            servicios_completados=int(p.servicios_completados),
            jefe_nombre=p.jefe_nombre or "Sin asignar",
        )
        for p in rows
    ]

    total       = len(all_proyectos)
    total_pages = max(1, -(-total // page_size))  # ceil division
    offset_     = (page - 1) * page_size
    proyectos   = all_proyectos[offset_: offset_ + page_size]

    total_svc  = sum(p.total_servicios for p in all_proyectos)
    total_comp = sum(p.servicios_completados for p in all_proyectos)

    return ProyectosConKpisOut(
        kpis=KpisProyectosOut(
            total_proyectos=total,
            servicios_completados=total_comp,
            servicios_pendientes=total_svc - total_comp,
            tasa_avance=round(total_comp / total_svc * 100) if total_svc else 0,
        ),
        proyectos=proyectos,
        paginacion=PaginacionMeta(
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )


# ── GET /operaciones/proyecto/{proyecto_id}/servicios ─────────────────────────

@router.get("/proyecto/{proyecto_id}/servicios", response_model=ServiciosPaginadosOut)
def get_servicios_proyecto(
    proyecto_id: str,
    q:           Optional[str] = Query(None, description="Buscar por nombre del servicio"),
    estado:      Optional[str] = Query(None, description="Filtrar por estado"),
    page:        int           = Query(1, ge=1),
    page_size:   int           = Query(20, ge=1, le=100),
    payload:     dict          = Depends(verificar_token),
    db:          Session       = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    rol        = payload.get("rol", "")

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    # Solo los Técnicos tienen acceso restringido a proyectos; los demás roles
    # (Soporte, Logística, TI, etc.) pueden ver servicios de cualquier proyecto.
    if es_tecnico(payload):
        empleado = _get_empleado_or_403(db, usuario_id, empresa_id)
        es_jefe    = proyecto.jefe_operaciones_id == empleado.id
        es_miembro = db.query(ProyectoMiembro).filter(
            ProyectoMiembro.proyecto_id == proyecto_id,
            ProyectoMiembro.empleado_id == empleado.id,
        ).first() is not None
        if not es_jefe and not es_miembro:
            raise HTTPException(status_code=403, detail="No tienes acceso a este proyecto")
    servicios = (
        db.query(ProyectoServicio)
        .filter(
            ProyectoServicio.proyecto_id == proyecto_id,
            ProyectoServicio.empresa_id  == empresa_id,
        )
        .order_by(ProyectoServicio.orden.asc())
        .all()
    )

    # ── Visibilidad por dueño (SOLO Jefe de Operaciones) ───────────────────────
    # Un Jefe de Operaciones ve un servicio únicamente si NADIE lo acaparó
    # todavía (lider_id vacío = pendiente, disponible para tomar) o si ÉL es el
    # líder. Los servicios ya tomados por OTRO jefe no le aparecen. Admin,
    # Soporte, Logística y demás roles NO se filtran: mantienen visibilidad
    # total (gestión/monitoreo global). Técnico ya quedó restringido arriba por
    # acceso al proyecto.
    if es_jefe_operaciones(payload):
        mi_emp = db.query(Empleado.id).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        mi_emp_id = str(mi_emp[0]) if mi_emp else None
        servicios = [
            s for s in servicios
            if s.lider_id is None or (mi_emp_id and str(s.lider_id) == mi_emp_id)
        ]

    # ── Filtros adicionales ────────────────────────────────────────────────────
    if estado:
        servicios = [s for s in servicios if (s.estado or "") == estado]
    if q:
        q_low = q.lower().strip()
        servicios = [s for s in servicios if q_low in (s.nombre or "").lower()]

    # ── Paginación ─────────────────────────────────────────────────────────────
    total_svc   = len(servicios)
    total_pages = max(1, -(-total_svc // page_size))
    offset_     = (page - 1) * page_size
    servicios   = servicios[offset_: offset_ + page_size]

    # Avance por TAREAS: contadores (total y completadas) por servicio en un
    # solo round-trip. Alimenta la barra de progreso de la lista.
    svc_ids = [str(ps.id) for ps in servicios]
    tareas_por_svc: dict[str, tuple[int, int]] = {}
    if svc_ids:
        cnt_rows = (
            db.query(
                Tarea.proyecto_servicio_id,
                func.count(Tarea.id).label("total"),
                func.sum(
                    case((Tarea.estado == "completado", 1), else_=0)
                ).label("completadas"),
            )
            .filter(Tarea.proyecto_servicio_id.in_(svc_ids))
            .group_by(Tarea.proyecto_servicio_id)
            .all()
        )
        for sid, total_t, comp_t in cnt_rows:
            tareas_por_svc[str(sid)] = (int(total_t or 0), int(comp_t or 0))

    hoy = date.today()
    items = []
    for ps in servicios:
        if ps.estado == "Completado":
            estado_color = "verde"
        elif ps.fecha_programada is not None and ps.fecha_programada < hoy:
            estado_color = "rojo"
        else:
            estado_color = "amarillo"

        total_t, comp_t = tareas_por_svc.get(str(ps.id), (0, 0))
        items.append(ProyectoServicioListOut(
            id=str(ps.id),
            nombre=ps.nombre or "",
            descripcion=ps.descripcion,
            estado=ps.estado or "Pendiente",
            orden=ps.orden or 1,
            fecha_programada=ps.fecha_programada.strftime("%d %b %Y") if ps.fecha_programada else None,
            fecha_fin=ps.fecha_fin.strftime("%d %b %Y") if ps.fecha_fin else None,
            estado_color=estado_color,
            total_tareas=total_t,
            tareas_completadas=comp_t,
        ))

    return ServiciosPaginadosOut(
        servicios=items,
        paginacion=PaginacionMeta(
            total=total_svc,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )


# ── GET /operaciones/dashboard ────────────────────────────────────────────────

@router.get("/dashboard")
def get_dashboard(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    hoy        = date.today()

    # Subquery: proyectos donde el usuario es miembro activo
    miembro_subq = (
        db.query(ProyectoMiembro.proyecto_id)
        .join(Empleado, Empleado.id == ProyectoMiembro.empleado_id)
        .filter(
            Empleado.usuario_id    == usuario_id,
            ProyectoMiembro.activo == True,
        )
        .subquery()
    )

    # Todos los servicios donde el técnico es miembro activo (sin filtro de fecha)
    rows = (
        db.query(
            ProyectoServicio,
            Proyecto.fecha_inicio.label("fecha_proyecto"),
            Cliente.razon_social.label("cliente"),
            func.coalesce(ProyectoServicio.zona_ejecucion, Proyecto.nombre_proyecto).label("ubicacion"),
        )
        .join(Proyecto, Proyecto.id == ProyectoServicio.proyecto_id)
        .join(Cliente,  Cliente.id  == Proyecto.cliente_id)
        .filter(
            ProyectoServicio.empresa_id == empresa_id,
            ProyectoServicio.proyecto_id.in_(miembro_subq),
        )
        .order_by(Proyecto.fecha_inicio.asc(), ProyectoServicio.orden.asc())
        .all()
    )

    _estado_map = {"Pendiente": "Pendiente", "En_Proceso": "Activo", "Completado": "Completado"}
    pendientes = activos = hechos = hoy_count = 0
    servicios: list[dict] = []

    for row in rows:
        ps         = row.ProyectoServicio
        est_raw    = ps.estado or "Pendiente"
        est_fe     = _estado_map.get(est_raw, est_raw)
        fecha_proy = row.fecha_proyecto
        hora_svc   = ps.fecha_programada

        if est_raw == "Pendiente":    pendientes += 1
        elif est_raw == "En_Proceso": activos    += 1
        elif est_raw == "Completado": hechos     += 1

        if fecha_proy == hoy:
            hoy_count += 1

        # Semáforo de prioridad
        if est_raw == "Completado":
            estado_color = "verde"
        elif fecha_proy is not None and fecha_proy < hoy:
            estado_color = "rojo"
        else:
            estado_color = "amarillo"

        servicios.append({
            "id":           ps.id,
            "cliente":      row.cliente,
            "tipoServicio": ps.nombre,
            "ubicacion":    row.ubicacion or "",
            "fechaStr":     fecha_proy.strftime("%d %b %Y") if fecha_proy else "Sin fecha",
            "horaStr":      hora_svc.strftime("%I:%M %p") if hora_svc else "--:--",
            "estado":       est_fe,
            "alerta":       est_raw != "Completado" and fecha_proy is not None and fecha_proy < hoy,
            "estadoColor":  estado_color,
        })

    metricas = [
        {"id": "pendientes", "titulo": "Pendientes",  "valor": pendientes, "colorIcono": "#f59e0b", "resaltado": False},
        {"id": "activos",    "titulo": "En Proceso",   "valor": activos,    "colorIcono": "#3b82f6", "resaltado": activos > 0},
        {"id": "hechos",     "titulo": "Completados",  "valor": hechos,     "colorIcono": "#91d337", "resaltado": False},
        {"id": "hoy",        "titulo": "Para Hoy",     "valor": hoy_count,  "colorIcono": "#8b5cf6", "resaltado": False},
    ]

    return {"status": "success", "data": {"metricas": metricas, "servicios": servicios}}


# ── GET /operaciones/servicio/{servicio_id} ───────────────────────────────────

@router.get("/servicio/{servicio_id}", response_model=ServicioDetalleOut)
def get_detalle_servicio(
    servicio_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    # 1. Datos base
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    proyecto = db.query(Proyecto).filter(Proyecto.id == ps.proyecto_id).first()
    cliente  = db.query(Cliente).filter(Cliente.id  == proyecto.cliente_id).first()
    # Nombres de ubicacion/zona para prefill del modal de edicion (evita race en frontend)
    ubic_nombre = None
    zona_nombre = None
    if ps.ubicacion_id:
        _u = db.query(Ubicacion).filter(Ubicacion.id == ps.ubicacion_id).first()
        ubic_nombre = _u.nombre if _u else None
    if ps.zona_id:
        _z = db.query(Zona).filter(Zona.id == ps.zona_id).first()
        zona_nombre = _z.nombre if _z else None
    # Texto a mostrar como "ubicación": catálogo nuevo (zona/ubicación) primero,
    # zona_ejecucion (legado, texto libre) después, nombre del proyecto al final.
    if zona_nombre and ubic_nombre:
        ubicacion = f"{zona_nombre} - {ubic_nombre}"
    elif zona_nombre or ubic_nombre:
        ubicacion = zona_nombre or ubic_nombre
    else:
        ubicacion = (ps.zona_ejecucion or proyecto.nombre_proyecto) or ""

    # Alerta de calidad: el tipo de servicio tiene catálogo asignado pero el
    # servicio no tiene ningún procedimiento estándar instanciado (sin plantilla
    # definida para ese tipo, o instanciación pendiente). No bloquea — solo avisa.
    sin_proc_estandar = bool(ps.catalogo_servicio_id) and not (
        db.query(func.count(Procedimiento.id))
        .filter(
            Procedimiento.proyecto_servicio_id == ps.id,
            Procedimiento.equipo_intervenido_id.is_(None),
        )
        .scalar()
    )

    # 2. Verificar acceso: Jefe de Operaciones (cualquiera, por rol) SIEMPRE tiene
    #    acceso completo; Técnico solo si está designado (miembro del proyecto).
    #    admin: bypass. Los NO designados reciben una vista BÁSICA (cabecera +
    #    tareas + equipo asignado, SIN materiales/procedimientos/evidencias) en
    #    lugar de un 403, para que puedan ver que el servicio existe y quién lo
    #    integra sin exponer datos de trabajo ni depender de endpoints de
    #    Logística/Requerimientos a los que Técnico/Jefe de Operaciones no
    #    tienen acceso (evita el bloqueo/error visto al abrir el detalle).
    acceso_completo = True
    if payload.get("rol", "") != "Administrador":
        empleado_actual = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if not empleado_actual:
            raise HTTPException(status_code=403, detail="No eres empleado registrado")

        # Acceso "de jefe" al detalle: un Jefe de Operaciones tiene acceso
        # completo SOLO a los servicios sin líder (pendientes) o de los que él es
        # el líder — no a los ya tomados por otro jefe (misma regla que el
        # listado). Otros roles no-admin (p. ej. Supervisor) conservan el acceso
        # por ser jefe del PROYECTO.
        if es_jefe_operaciones(payload):
            es_jefe = ps.lider_id is None or str(ps.lider_id) == str(empleado_actual.id)
        else:
            es_jefe = proyecto.jefe_operaciones_id == empleado_actual.id
        es_miembro = db.query(ProyectoMiembro).filter(
            ProyectoMiembro.proyecto_id == ps.proyecto_id,
            ProyectoMiembro.empleado_id == empleado_actual.id,
        ).first() is not None

        acceso_completo = es_jefe or es_miembro

    fp        = ps.fecha_programada
    fecha_str = fp.strftime("%d %b %Y") if fp else "Sin fecha"
    hora_str  = fp.strftime("%I:%M %p") if fp else "--:--"

    # 3. Equipo de trabajo — POR SERVICIO, no por proyecto.
    # ProyectoMiembro es a nivel de PROYECTO (sirve para control de acceso):
    # un servicio recién creado "heredaría" a los técnicos asignados a OTROS
    # servicios del mismo proyecto. La asignación real por servicio son los
    # responsables de las TAREAS de este servicio (creadas en configurar).
    equipo_rows = (
        db.query(
            Usuario,
            Empleado.cargo,
            Empleado.id.label("empleado_id"),
            ProyectoMiembro.rol_proyecto,
        )
        .select_from(Tarea)
        .join(Empleado, Empleado.id == Tarea.responsable_id)
        .join(Usuario,  Usuario.id  == Empleado.usuario_id)
        .outerjoin(ProyectoMiembro, (ProyectoMiembro.proyecto_id == ps.proyecto_id)
                                  & (ProyectoMiembro.empleado_id == Empleado.id))
        .filter(
            Tarea.proyecto_servicio_id == servicio_id,
            Tarea.responsable_id.isnot(None),
        )
        .distinct()
        .all()
    )

    # El equipo muestra SOLO a los asignados explícitamente a ESTE servicio:
    # líder del servicio, técnico líder y responsables de sus tareas.
    # El creador / jefe de operaciones del proyecto NO se muestra aquí salvo
    # que esté asignado (queda solo en los campos de auditoría del proyecto).
    lider_emp_id   = str(ps.lider_id)       if ps.lider_id       else None
    tecnico_emp_id = str(ps.responsable_id) if ps.responsable_id else None

    equipo: list[MiembroEquipoOut] = []
    _vistos: set[str] = set()

    def _add_asignado(emp_id: str | None, rol: str) -> None:
        """Agrega líder / técnico líder al equipo (tolera IDs nulos o huérfanos)."""
        if not emp_id or emp_id in _vistos:
            return
        emp = db.query(Empleado).filter(Empleado.id == emp_id).first()
        usr = db.query(Usuario).filter(Usuario.id == emp.usuario_id).first() if emp else None
        if not emp or not usr:
            return
        _vistos.add(emp_id)
        equipo.append(MiembroEquipoOut(
            id=str(emp.id),  # empleado.id — requerido por el modal de configurar
            nombre=usr.nombre or "",
            apellido=usr.apellido or "",
            foto_url=usr.foto_url or "",
            cargo=emp.cargo or "Sin Cargo",
            rol_proyecto=rol,
        ))

    _add_asignado(lider_emp_id,   "Líder del Servicio")
    _add_asignado(tecnico_emp_id, "Técnico Líder")

    for r in equipo_rows:
        emp_id = str(r.empleado_id)
        if emp_id in _vistos:
            continue  # ya listado como líder / técnico líder
        _vistos.add(emp_id)
        equipo.append(MiembroEquipoOut(
            id=emp_id,
            nombre=r.Usuario.nombre or "",
            apellido=r.Usuario.apellido or "",
            foto_url=r.Usuario.foto_url or "",
            cargo=r.cargo or "Sin Cargo",
            rol_proyecto=r.rol_proyecto or "Técnico",
        ))

    # Quien solicitó materiales/herramientas para este servicio también cuenta
    # como parte del equipo (solo puede pedir quien está en el servicio). No
    # se usa una Tarea sintética para esto porque Tarea alimenta el cálculo de
    # progreso (completado/total) y una tarea inventada lo distorsionaría.
    solicitante_rows = (
        db.query(Usuario, Empleado.cargo, Empleado.id.label("empleado_id"))
        .select_from(Requerimiento)
        .join(Empleado, Empleado.id == Requerimiento.solicitante_id)
        .join(Usuario,  Usuario.id  == Empleado.usuario_id)
        .filter(
            Requerimiento.proyecto_servicio_id == servicio_id,
            Requerimiento.solicitante_id.isnot(None),
        )
        .distinct()
        .all()
    )
    for r in solicitante_rows:
        emp_id = str(r.empleado_id)
        if emp_id in _vistos:
            continue
        _vistos.add(emp_id)
        equipo.append(MiembroEquipoOut(
            id=emp_id,
            nombre=r.Usuario.nombre or "",
            apellido=r.Usuario.apellido or "",
            foto_url=r.Usuario.foto_url or "",
            cargo=r.cargo or "Sin Cargo",
            rol_proyecto="Solicitante de Materiales",
        ))

    # 4. Procedimientos (pasos fijos) + Evidencias — solo con acceso completo.
    # Replanteo 2026-07-08: ya NO se instancian procedimientos por tipo de
    # servicio (los checklists viven en tipo_equipo.procedimientos_template y
    # se trabajan por inspección de equipo). Los servicios antiguos conservan
    # sus procedimientos/evidencias como histórico.
    if acceso_completo:
        # Solo los procedimientos GENERALES del servicio: los ligados a un
        # equipo intervenido viven en el detalle de cada equipo.
        procs = (
            db.query(Procedimiento)
            .filter(
                Procedimiento.proyecto_servicio_id == servicio_id,
                Procedimiento.equipo_intervenido_id.is_(None),
            )
            .order_by(Procedimiento.orden.asc())
            .all()
        )
        # Concepto retirado: sin plantillas por servicio, que un servicio no
        # tenga procedimientos generales ya no es una anomalía que alertar.
        sin_proc_estandar = False
        evidencias = (
            db.query(EvidenciaProcedimiento)
            .filter(
                EvidenciaProcedimiento.proyecto_servicio_id == servicio_id,
                EvidenciaProcedimiento.equipo_intervenido_id.is_(None),
            )
            .order_by(EvidenciaProcedimiento.fecha_captura.asc())
            .all()
        )

        ev_by_proc: dict[str, list] = {}
        for ev in evidencias:
            ev_by_proc.setdefault(ev.procedimiento_id, []).append(
                EvidenciaOut(
                    id=str(ev.id),
                    url_cloudinary=ev.url_cloudinary or "",
                    descripcion=ev.descripcion or "",
                    etapa=ev.etapa,
                    fecha_captura=fmt_lima(ev.fecha_captura, "%I:%M %p"),
                )
            )

        # Procedimientos = pasos fijos (avance/informe). Las evidencias cuelgan aquí.
        procedimientos = [
            ProcedimientoOut(
                id=str(p.id),
                nombre=p.nombre or "",
                descripcion=p.descripcion or "",
                orden=p.orden or 0,
                estado=p.estado or "pendiente",
                evidencias=ev_by_proc.get(p.id, []),
            )
            for p in procs
        ]
    else:
        procedimientos = []

    # 4b. Tareas (cronograma: responsable + fechas)
    # Técnico: solo sus propias tareas; otros roles: todas
    _tareas_q = db.query(Tarea).filter(Tarea.proyecto_servicio_id == servicio_id)
    if es_tecnico(payload):
        _emp_tec = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if _emp_tec:
            _tareas_q = _tareas_q.filter(Tarea.responsable_id == _emp_tec.id)
        else:
            _tareas_q = _tareas_q.filter(False)
    tareas_rows = _tareas_q.order_by(Tarea.orden.asc()).all()
    tareas = [
        TareaOut(
            id=str(t.id),
            nombre=t.nombre or "",
            descripcion=t.descripcion or "",
            orden=t.orden or 0,
            estado=t.estado or "pendiente",
            responsable_id=str(t.responsable_id) if t.responsable_id else None,
            fecha_inicio_tarea=t.fecha_inicio_tarea.isoformat() if t.fecha_inicio_tarea else None,
            fecha_limite=t.fecha_limite.isoformat() if t.fecha_limite else None,
        )
        for t in tareas_rows
    ]

    # El avance depende SOLO de las TAREAS del cronograma (no de los
    # procedimientos, que ahora son informativos). Se cuentan TODAS las tareas
    # del servicio, sin el filtro por técnico de arriba.
    _tareas_avance = (
        db.query(Tarea.estado)
        .filter(Tarea.proyecto_servicio_id == servicio_id)
        .all()
    )
    total     = len(_tareas_avance)
    completos = sum(1 for (e,) in _tareas_avance if e == "completado")
    progreso  = round(completos / total * 100, 1) if total else 0.0

    # 5. Materiales/Herramientas/Equipos — solo con acceso completo (excluye
    # borradores; soporta compras externas con material_id=NULL y salidas de
    # equipo/herramienta con equipo_id). Depende de Requerimientos, cuyos
    # endpoints de Logística bloquean a Técnico/Jefe de Operaciones sin
    # designación — por eso se omite por completo en la vista básica.
    mat_asignados: list[ItemMaterialOut]   = []
    mat_solicitados: list[ItemMaterialOut] = []

    if acceso_completo:
        mat_rows = (
            db.query(
                RequerimientoDetalle,
                Requerimiento.id.label("req_id"),
                Requerimiento.estado.label("req_estado"),
                func.coalesce(
                    Material.nombre,
                    Equipo.nombre,
                    RequerimientoDetalle.nombre_libre,
                ).label("mat_nombre"),
                func.coalesce(
                    Material.unidad,
                    RequerimientoDetalle.unidad_libre,
                ).label("mat_unidad"),
                Material.tipo.label("mat_tipo"),
                Equipo.id.label("equipo_id"),
                Equipo.numero_serie.label("equipo_serie"),
            )
            .join(Requerimiento, Requerimiento.id == RequerimientoDetalle.requerimiento_id)
            .outerjoin(Material, Material.id      == RequerimientoDetalle.material_id)
            .outerjoin(Equipo, Equipo.id          == RequerimientoDetalle.equipo_id)
            .filter(
                Requerimiento.proyecto_servicio_id == servicio_id,
                Requerimiento.empresa_id           == empresa_id,
                Requerimiento.tipo.in_(["material", "herramienta", "equipo_especial"]),
                Requerimiento.estado               != "borrador",
            )
            .order_by(Requerimiento.created_at.asc())
            .all()
        )

        for m in mat_rows:
            rd = m.RequerimientoDetalle
            # Clasificación: campo explícito de la línea; si falta, derivar del
            # catálogo (material.tipo) o de si es un equipo/herramienta de
            # inventario propio (equipo_id); por defecto 'material'.
            tipo_item = (getattr(rd, "tipo_item_compra", None) or "").lower()
            if tipo_item not in ("material", "herramienta"):
                if m.mat_tipo == "herramienta" or m.equipo_id:
                    tipo_item = "herramienta"
                else:
                    tipo_item = "material"
            item = ItemMaterialOut(
                id=str(rd.id),
                requerimiento_id=str(m.req_id),
                nombre=m.mat_nombre or "Material Sin Nombre",
                unidad=m.mat_unidad or "Und",
                cantidad=rd.cantidad or 0,
                estado_req=m.req_estado or "pendiente",
                tipo=tipo_item,
                equipo_id=str(m.equipo_id) if m.equipo_id else None,
                numero_serie=m.equipo_serie,
            )
            if m.req_estado in ("entregado", "aprobado"):
                mat_asignados.append(item)
            else:
                mat_solicitados.append(item)

    return ServicioDetalleOut(
        id=str(ps.id),
        proyecto_id=str(ps.proyecto_id),
        cliente=cliente.razon_social if cliente and cliente.razon_social else "Cliente Sin Nombre",
        tipo_servicio=ps.nombre or "Servicio Técnico",
        nombre=ps.nombre or "Servicio Técnico",
        ubicacion=ubicacion or "",
        fecha_str=fecha_str or "",
        hora_str=hora_str or "",
        descripcion=ps.descripcion or "",
        estado=ps.estado or "Pendiente",
        progreso=progreso,
        equipo=equipo,
        procedimientos=procedimientos,
        tareas=tareas,
        materiales_asignados=mat_asignados,
        materiales_solicitados=mat_solicitados,
        # Campos extra para modal de edición
        catalogo_servicio_id=str(ps.catalogo_servicio_id) if ps.catalogo_servicio_id else None,
        fecha_programada=ps.fecha_programada.isoformat() if ps.fecha_programada else None,
        fecha_inicio=ps.fecha_inicio.isoformat() if ps.fecha_inicio else None,
        fecha_fin=ps.fecha_fin.isoformat() if ps.fecha_fin else None,
        lider_id=str(ps.lider_id) if ps.lider_id else None,
        responsable_id=str(ps.responsable_id) if ps.responsable_id else None,
        zona_ejecucion=ps.zona_ejecucion or None,
        alcance=ps.alcance or None,
        tipo_documento_cliente=ps.tipo_documento_cliente or None,
        nro_documento=ps.nro_documento or None,
        es_mantenimiento=bool(ps.tiene_equipos_intervenidos),
        inspeccion_equipos_activa=bool(ps.tiene_equipos_intervenidos),
        ubicacion_id=str(ps.ubicacion_id) if ps.ubicacion_id else None,
        zona_id=str(ps.zona_id) if ps.zona_id else None,
        ubicacion_nombre=ubic_nombre,
        zona_nombre=zona_nombre,
        sin_procedimientos_estandar=sin_proc_estandar,
        acceso_completo=acceso_completo,
    )

# ── PATCH /operaciones/servicio/{id}/estado ───────────────────────────────────

def _motivos_inicio(db: Session, servicio_id: str) -> list[str]:
    """Requisitos mínimos para iniciar un servicio (checklist de Preparación).

    Devuelve la lista de lo que falta; vacía = se puede iniciar. Se valida en el
    servidor para que la regla no dependa solo de la UI (web o móvil).
    """
    motivos: list[str] = []
    # Solo los procedimientos GENERALES: las copias por equipo intervenido no
    # llevan responsable y bloquearían el inicio para siempre.
    procs = (
        db.query(Procedimiento)
        .filter(
            Procedimiento.proyecto_servicio_id == servicio_id,
            Procedimiento.equipo_intervenido_id.is_(None),
        )
        .all()
    )
    if not procs:
        motivos.append("repartir las tareas del servicio")
    elif any(not p.responsable_id for p in procs):
        motivos.append("asignar un responsable a todas las tareas")
    return motivos


async def _notificar_cambio_estado_servicio(db: Session, ps: ProyectoServicio, nuevo: str) -> None:
    """Notifica SOLO a los técnicos asignados a ESTE servicio (líder, técnico
    líder y responsables de sus tareas) — no a todo el proyecto, que puede
    tener otros servicios ajenos a este cierre."""
    from ..services.fcm_service import notificar_usuario
    from .chat_ws import manager as _ws_manager

    emp_ids: set[str] = set()
    if ps.lider_id:
        emp_ids.add(str(ps.lider_id))
    if ps.responsable_id:
        emp_ids.add(str(ps.responsable_id))
    tarea_resps = (
        db.query(Tarea.responsable_id)
        .filter(Tarea.proyecto_servicio_id == str(ps.id), Tarea.responsable_id.isnot(None))
        .distinct()
        .all()
    )
    emp_ids.update(str(r) for (r,) in tarea_resps)

    usuario_ids: list[str] = []
    if emp_ids:
        rows = (
            db.query(Empleado.usuario_id)
            .filter(Empleado.id.in_(emp_ids), Empleado.usuario_id.isnot(None))
            .distinct()
            .all()
        )
        usuario_ids = [uid for (uid,) in rows]

    nombre_srv = ps.nombre or "El servicio"
    if nuevo == "Completado":
        titulo  = "Servicio finalizado"
        mensaje = f"{nombre_srv} finalizó. Revisa qué materiales/herramientas debes retornar."
    else:
        titulo, mensaje = "Servicio cancelado", f"{nombre_srv} fue cancelado."
    for uid in usuario_ids:
        notificar_usuario(
            db, empresa_id=ps.empresa_id, usuario_id=uid,
            titulo=titulo, mensaje=mensaje,
            tipo="servicio", categoria="servicio",
            referencia_id=str(ps.id), referencia_tabla="proyecto_servicio",
        )
    db.commit()

    if nuevo == "Completado":
        try:
            await _ws_manager.broadcast_servicio(str(ps.id), {"tipo": "servicio_completado_retorno"})
        except Exception:
            pass


@router.patch("/servicio/{servicio_id}/estado")
async def actualizar_estado_servicio(
    servicio_id: str,
    body: ActualizarEstadoBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
    x_justificacion: str | None = Header(default=None, alias="X-Justificacion"),
):
    exigir_no_tecnico(payload, "Técnico no puede cambiar el estado de un servicio")
    if es_jefe_operaciones(payload) and (x_justificacion or "").strip():
        set_justificacion(x_justificacion)
    estados_validos = {"Pendiente", "En_Proceso", "Completado", "Cancelado"}
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail="Estado inválido")

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == payload["empresa_id"],
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    estado_actual = ps.estado
    nuevo         = body.estado
    es_lider      = _rol_es_lider(payload.get("rol"))

    # Las reglas solo aplican cuando hay cambio real de estado.
    if estado_actual != nuevo:
        # 1. Un servicio cerrado es inmutable salvo reapertura por líder/admin.
        if estado_actual == "Completado" and not es_lider:
            raise HTTPException(
                status_code=403,
                detail="El servicio está cerrado. Solo el Jefe de Operaciones puede reabrirlo.",
            )

        # 2. Finalizar o cancelar: solo Jefe de Operaciones / Admin.
        if nuevo in ("Completado", "Cancelado") and not es_lider:
            raise HTTPException(
                status_code=403,
                detail="Solo el Jefe de Operaciones puede finalizar o cancelar el servicio.",
            )

        # 3. Finalizar requiere el 100% de las TAREAS del cronograma completadas.
        #    El avance del servicio se rige por las Tareas (no por los
        #    Procedimientos, que son informativos / evidencias). Un servicio sin
        #    tareas puede cerrarse: no hay cronograma que bloquee el cierre.
        if nuevo == "Completado":
            tareas = (
                db.query(Tarea.estado)
                .filter(Tarea.proyecto_servicio_id == servicio_id)
                .all()
            )
            if any(e != "completado" for (e,) in tareas):
                raise HTTPException(
                    status_code=409,
                    detail="No puedes finalizar el servicio: faltan tareas por completar.",
                )

            # 3b. Si el servicio maneja Equipos Intervenidos (botón al crear/
            #     editar el servicio), no puede cerrarse con equipos a medias.
            #     Los cancelados no bloquean.
            if ps.tiene_equipos_intervenidos:
                sin_completar = (
                    db.query(EquipoIntervenido)
                    .filter(
                        EquipoIntervenido.proyecto_servicio_id == servicio_id,
                        EquipoIntervenido.empresa_id           == payload["empresa_id"],
                        EquipoIntervenido.activo               == True,
                        EquipoIntervenido.estado_intervencion.notin_(
                            ("completado", "cancelado")),
                    )
                    .count()
                )
                if sin_completar:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            f"No puedes finalizar el servicio: {sin_completar} "
                            "equipo(s) intervenido(s) sin completar."
                        ),
                    )

        # 4. Iniciar (Pendiente → En_Proceso) exige el checklist de Preparación.
        if nuevo == "En_Proceso" and estado_actual == "Pendiente":
            faltan = _motivos_inicio(db, servicio_id)
            if faltan:
                raise HTTPException(
                    status_code=409,
                    detail="No puedes iniciar el servicio. Falta: " + " · ".join(faltan) + ".",
                )

    ps.estado     = nuevo
    ps.updated_at = datetime.utcnow()
    db.commit()

    # Avisar a los técnicos del servicio cuando se cierra o cancela.
    if estado_actual != nuevo and nuevo in ("Completado", "Cancelado"):
        try:
            await _notificar_cambio_estado_servicio(db, ps, nuevo)
        except Exception:
            pass

    return {"ok": True, "estado": nuevo}


# ── PATCH /operaciones/procedimiento/{id}/estado ──────────────────────────────

@router.patch("/procedimiento/{proc_id}/estado")
def actualizar_estado_procedimiento(
    proc_id: str,
    body:    ActualizarProcedimientoBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    estados_validos = {"pendiente", "en_proceso", "completado", "bloqueado"}
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail="Estado inválido")

    proc = db.query(Procedimiento).filter(
        Procedimiento.id         == proc_id,
        Procedimiento.empresa_id == payload["empresa_id"],
    ).first()
    if not proc:
        raise HTTPException(status_code=404, detail="Procedimiento no encontrado")

    _assert_servicio_abierto(proc.proyecto_servicio_id, db, payload["empresa_id"])

    proc.estado     = body.estado
    proc.updated_at = datetime.utcnow()
    _rollup_equipo_por_procedimientos(db, proc)
    db.commit()
    return {"ok": True, "estado": body.estado}


# ── PATCH /operaciones/tarea/{id}/estado ──────────────────────────────────────
# Estado organizativo de una tarea del cronograma. NO afecta el avance (eso lo
# controlan los procedimientos fijos).

@router.patch("/tarea/{tarea_id}/estado")
def actualizar_estado_tarea(
    tarea_id: str,
    body:     ActualizarProcedimientoBody,
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
    x_justificacion: str | None = Header(default=None, alias="X-Justificacion"),
):
    estados_validos = {"pendiente", "en_proceso", "completado", "bloqueado"}
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail="Estado inválido")

    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    tarea = db.query(Tarea).filter(
        Tarea.id         == tarea_id,
        Tarea.empresa_id == empresa_id,
    ).first()
    if not tarea:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    # Técnico: solo puede actualizar sus propias tareas
    if es_tecnico(payload):
        emp = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if not emp or tarea.responsable_id != emp.id:
            raise HTTPException(status_code=403, detail="Solo puedes actualizar tus propias tareas")

    # Jefe de Operaciones: si está asignado al proyecto/servicio gestiona libre;
    # la justificación solo se exige al tocar tareas de un servicio que no es suyo.
    if es_jefe_operaciones(payload):
        if not _jefe_op_asignado_al_servicio(db, payload, empresa_id, tarea.proyecto_servicio_id):
            if not (x_justificacion or "").strip():
                raise HTTPException(
                    status_code=422,
                    detail="Se requiere justificación (X-Justificacion) para modificar tareas de un servicio que no tienes asignado",
                )
        if (x_justificacion or "").strip():
            set_justificacion(x_justificacion)

    _assert_servicio_abierto(tarea.proyecto_servicio_id, db, empresa_id)

    tarea.estado     = body.estado
    tarea.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado": body.estado}


# ── Plantillas de Procedimientos (estándar por tipo de servicio) ──────────────
# Gestión admin del manual estándar que se instancia en cada servicio.

def _plantilla_out(p: PlantillaProcedimiento, catalogo_nombre: str | None = None) -> PlantillaProcedimientoOut:
    try:
        procesos = json.loads(p.procesos or "[]")
    except (ValueError, TypeError):
        procesos = []
    return PlantillaProcedimientoOut(
        id=str(p.id),
        catalogo_servicio_id=str(p.catalogo_servicio_id) if p.catalogo_servicio_id else None,
        catalogo_servicio_nombre=catalogo_nombre,
        tipo_trabajo=p.tipo_trabajo,
        nombre=p.nombre or "",
        procesos=[ProcesoItem(**x) for x in procesos if isinstance(x, dict)],
        version=p.version or 1,
        activo=bool(p.activo),
    )


@router.get("/plantillas-procedimiento", response_model=List[PlantillaProcedimientoOut])
def listar_plantillas_procedimiento(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    exigir_permiso(db, payload, "catalogos", "ver")
    rows = (
        db.query(PlantillaProcedimiento, CatalogoServicio.nombre)
        .outerjoin(CatalogoServicio, CatalogoServicio.id == PlantillaProcedimiento.catalogo_servicio_id)
        .filter(PlantillaProcedimiento.empresa_id == payload["empresa_id"])
        .order_by(CatalogoServicio.nombre.asc().nullslast(), PlantillaProcedimiento.tipo_trabajo.asc())
        .all()
    )
    return [_plantilla_out(p, catalogo_nombre) for p, catalogo_nombre in rows]


@router.get("/plantillas-procedimiento/por-catalogo/{catalogo_servicio_id}", response_model=PlantillaProcedimientoOut)
def obtener_plantilla_por_catalogo(
    catalogo_servicio_id: str,
    payload:               dict    = Depends(verificar_token),
    db:                    Session = Depends(get_db),
):
    """Procedimientos estándar del tipo de servicio (vía FK). Es la forma
    preferida de consultar — ver también el endpoint legacy por tipo_trabajo."""
    exigir_permiso(db, payload, "catalogos", "ver")
    p = db.query(PlantillaProcedimiento).filter(
        PlantillaProcedimiento.empresa_id           == payload["empresa_id"],
        PlantillaProcedimiento.catalogo_servicio_id == catalogo_servicio_id,
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Este tipo de servicio aún no tiene procedimientos estándar")
    catalogo = db.query(CatalogoServicio).filter(CatalogoServicio.id == catalogo_servicio_id).first()
    return _plantilla_out(p, catalogo.nombre if catalogo else None)


@router.get("/plantillas-procedimiento/{tipo_trabajo}", response_model=PlantillaProcedimientoOut)
def obtener_plantilla_procedimiento(
    tipo_trabajo: str,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    """Legacy: consulta por el string tipo_trabajo. Preferir
    /plantillas-procedimiento/por-catalogo/{catalogo_servicio_id}."""
    exigir_permiso(db, payload, "catalogos", "ver")
    p = db.query(PlantillaProcedimiento).filter(
        PlantillaProcedimiento.empresa_id   == payload["empresa_id"],
        PlantillaProcedimiento.tipo_trabajo == tipo_trabajo,
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Plantilla no encontrada")
    catalogo_nombre = None
    if p.catalogo_servicio_id:
        catalogo = db.query(CatalogoServicio).filter(CatalogoServicio.id == p.catalogo_servicio_id).first()
        catalogo_nombre = catalogo.nombre if catalogo else None
    return _plantilla_out(p, catalogo_nombre)


@router.put("/plantillas-procedimiento", response_model=PlantillaProcedimientoOut)
def guardar_plantilla_procedimiento(
    body:    PlantillaProcedimientoIn,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Upsert del estándar por tipo de servicio. Preferido: `catalogo_servicio_id`
    (FK real). Legacy: `tipo_trabajo` solo si no se manda catalogo_servicio_id.
    Incrementa la versión en cada guardado. No reescribe los procedimientos ya
    instanciados en servicios existentes (esos se mantienen tal cual; los
    nuevos servicios usan la última)."""
    exigir_permiso(db, payload, "catalogos", "editar")
    empresa_id = payload["empresa_id"]

    catalogo = None
    cat_id = (body.catalogo_servicio_id or "").strip() or None
    if cat_id:
        catalogo = db.query(CatalogoServicio).filter(
            CatalogoServicio.id         == cat_id,
            CatalogoServicio.empresa_id == empresa_id,
        ).first()
        if not catalogo:
            raise HTTPException(status_code=404, detail="Tipo de servicio no encontrado")
        tipo = catalogo.tipo_trabajo  # cache, siempre se deriva del catálogo
    else:
        tipo = (body.tipo_trabajo or "").strip()
        if not tipo:
            raise HTTPException(status_code=422, detail="catalogo_servicio_id o tipo_trabajo es obligatorio")

    procesos_json = json.dumps(
        [p.model_dump() for p in body.procesos], ensure_ascii=False
    )

    if cat_id:
        p = db.query(PlantillaProcedimiento).filter(
            PlantillaProcedimiento.empresa_id           == empresa_id,
            PlantillaProcedimiento.catalogo_servicio_id == cat_id,
        ).first()
    else:
        p = db.query(PlantillaProcedimiento).filter(
            PlantillaProcedimiento.empresa_id           == empresa_id,
            PlantillaProcedimiento.tipo_trabajo         == tipo,
            PlantillaProcedimiento.catalogo_servicio_id.is_(None),
        ).first()

    if p:
        p.nombre     = body.nombre[:200]
        p.tipo_trabajo = tipo
        p.procesos   = procesos_json
        p.activo     = body.activo
        p.version    = (p.version or 1) + 1
        p.updated_at = datetime.utcnow()
    else:
        p = PlantillaProcedimiento(
            id                   = str(_uuid.uuid4()),
            empresa_id           = empresa_id,
            catalogo_servicio_id = cat_id,
            tipo_trabajo         = tipo,
            nombre               = body.nombre[:200],
            procesos             = procesos_json,
            version              = 1,
            activo               = body.activo,
            created_at           = datetime.utcnow(),
        )
        db.add(p)

    db.commit()
    db.refresh(p)
    return _plantilla_out(p, catalogo.nombre if catalogo else None)


# ── POST /operaciones/procedimiento/{id}/evidencia ────────────────────────────

_ETAPAS_VALIDAS = {"antes", "durante", "despues"}


def _rollup_equipo_por_procedimientos(db: Session, proc: Procedimiento) -> None:
    """Deriva estado_intervencion del equipo desde sus procedimientos del
    servicio vigente: todos completados → completado; todos pendientes →
    pendiente; mezcla → en_proceso. No toca equipos sin procedimientos
    ligados (los maneja el motor de inspección) ni equipos cuya intervención
    vigente pertenece a otro servicio."""
    eq_id = proc.equipo_intervenido_id
    if not eq_id:
        return
    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id         == eq_id,
        EquipoIntervenido.empresa_id == proc.empresa_id,
    ).first()
    if not ei or str(ei.proyecto_servicio_id or "") != str(proc.proyecto_servicio_id):
        return
    estados = [
        e for (e,) in db.query(Procedimiento.estado).filter(
            Procedimiento.equipo_intervenido_id == eq_id,
            Procedimiento.proyecto_servicio_id  == proc.proyecto_servicio_id,
        ).all()
    ]
    if not estados:
        return
    if all(e == "completado" for e in estados):
        nuevo = "completado"
    elif all(e == "pendiente" for e in estados):
        nuevo = "pendiente"
    else:
        nuevo = "en_proceso"
    if ei.estado_intervencion != nuevo:
        ei.estado_intervencion = nuevo
        ei.updated_at = datetime.utcnow()


@router.post("/procedimiento/{proc_id}/evidencia", status_code=status.HTTP_201_CREATED)
async def subir_evidencia(
    proc_id:     str,
    archivo:     UploadFile = File(...),
    etapa:       str        = Form(...),
    descripcion: str        = Form(default=""),
    payload:     dict       = Depends(verificar_token),
    db:          Session    = Depends(get_db),
):
    if etapa not in _ETAPAS_VALIDAS:
        raise HTTPException(
            status_code=422,
            detail=f"etapa debe ser uno de: {', '.join(sorted(_ETAPAS_VALIDAS))}",
        )

    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    proc = db.query(Procedimiento).filter(
        Procedimiento.id         == proc_id,
        Procedimiento.empresa_id == empresa_id,
    ).first()
    if not proc:
        raise HTTPException(status_code=404, detail="Procedimiento no encontrado")

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    ps = _assert_servicio_abierto(proc.proyecto_servicio_id, db, empresa_id)

    folder = f"evidencias/{empresa_id}/{ps.proyecto_id}"
    url    = await subir_archivo_cloudinary(archivo, folder)
    pub_id = _extract_public_id(url)

    ev = EvidenciaProcedimiento(
        id                   = str(_uuid.uuid4()),
        procedimiento_id     = proc_id,
        proyecto_servicio_id = proc.proyecto_servicio_id,
        proyecto_id          = ps.proyecto_id,
        empresa_id           = empresa_id,
        subido_por           = empleado.id,
        equipo_intervenido_id = proc.equipo_intervenido_id,
        url_cloudinary       = url,
        public_id_cloudinary = pub_id,
        etapa                = etapa,
        descripcion          = descripcion,
    )
    db.add(ev)

    # 'durante' es la evidencia estándar del trabajo y completa el
    # procedimiento. 'antes'/'despues' son registro fotográfico opcional:
    # no cambian estados ni alimentan observaciones del informe.
    if etapa == "durante":
        proc.estado     = "completado"
        proc.updated_at = datetime.utcnow()
        _rollup_equipo_por_procedimientos(db, proc)
    db.commit()

    return {"ok": True, "evidencia_id": ev.id, "url": url, "etapa": etapa}


# ── POST /operaciones/servicio/{id}/requerimiento ─────────────────────────────

@router.post("/servicio/{servicio_id}/requerimiento", status_code=status.HTTP_201_CREATED)
def solicitar_material(
    servicio_id: str,
    body: SolicitarMaterialBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    ps = _assert_servicio_abierto(servicio_id, db, empresa_id)

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    req = Requerimiento(
        id                   = str(_uuid.uuid4()),
        proyecto_id          = ps.proyecto_id,
        proyecto_servicio_id = servicio_id,
        empresa_id           = empresa_id,
        solicitante_id       = empleado.id,
        tipo                 = "material",
        estado               = "pendiente",
        fecha                = date.today(),
    )
    db.add(req)
    db.flush()

    rd = RequerimientoDetalle(
        id               = str(_uuid.uuid4()),
        requerimiento_id = req.id,
        material_id      = body.material_id,
        cantidad         = body.cantidad,
    )
    db.add(rd)
    db.commit()

    return {"ok": True, "requerimiento_id": req.id, "detalle_id": rd.id}


# ── PATCH /operaciones/requerimiento-detalle/{id} ─────────────────────────────

@router.patch("/requerimiento-detalle/{rd_id}")
def actualizar_requerimiento_detalle(
    rd_id:   str,
    body:    ActualizarReqDetalleBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    if body.cantidad is not None and body.cantidad < 1:
        raise HTTPException(status_code=422, detail="Cantidad inválida")

    empresa_id = payload["empresa_id"]

    rd = db.query(RequerimientoDetalle).filter(RequerimientoDetalle.id == rd_id).first()
    if not rd:
        raise HTTPException(status_code=404, detail="Detalle no encontrado")

    # Verificar que el requerimiento pertenece a la empresa del token
    req = db.query(Requerimiento).filter(
        Requerimiento.id         == rd.requerimiento_id,
        Requerimiento.empresa_id == empresa_id,
    ).first()
    if not req:
        raise HTTPException(status_code=403, detail="Acceso denegado")

    if req.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(req.proyecto_servicio_id))

    changed = False
    if body.cantidad is not None:
        rd.cantidad = body.cantidad
        changed = True
    if body.nombre is not None:
        rd.nombre_libre = body.nombre
        changed = True
    if body.especificacion is not None:
        rd.especificacion = body.especificacion
        changed = True
    if changed:
        db.commit()

    return {"ok": True}


# ── GET /operaciones/servicio/{id}/borrador ───────────────────────────────────

@router.get("/servicio/{servicio_id}/borrador")
def get_borrador(
    servicio_id: str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    try:
        empresa_id = payload["empresa_id"]

        borrador = db.query(Requerimiento).filter(
            Requerimiento.proyecto_servicio_id == servicio_id,
            Requerimiento.empresa_id           == empresa_id,
            Requerimiento.tipo                 == "material",
            Requerimiento.estado               == "borrador",
        ).first()

        if not borrador:
            return {"requerimiento_id": None, "items": []}

        detalles = (
            db.query(RequerimientoDetalle)
            .filter(RequerimientoDetalle.requerimiento_id == borrador.id)
            .all()
        )

        material_ids = [rd.material_id for rd in detalles if rd.material_id]
        mats_map: dict = {}
        if material_ids:
            mats_map = {
                m.id: m
                for m in db.query(Material).filter(Material.id.in_(material_ids)).all()
            }

        # Build a map of empleado_id → (nombre_completo, foto_url)
        emp_ids = list({getattr(rd, "agregado_por_id", None) for rd in detalles} - {None})
        emp_info: dict = {}
        if emp_ids:
            rows = (
                db.query(Empleado.id, Usuario.nombre, Usuario.apellido, Usuario.foto_url)
                .join(Usuario, Usuario.id == Empleado.usuario_id)
                .filter(Empleado.id.in_(emp_ids))
                .all()
            )
            for row in rows:
                emp_info[row[0]] = {
                    "nombre": f"{row[1]} {row[2]}".strip(),
                    "foto":   row[3] or "",
                }

        items = []
        for rd in detalles:
            mat              = mats_map.get(rd.material_id) if rd.material_id else None
            nombre_libre     = getattr(rd, "nombre_libre",     None)
            unidad_libre     = getattr(rd, "unidad_libre",     None)
            especificacion   = getattr(rd, "especificacion",   None)
            agregado_por_id  = getattr(rd, "agregado_por_id",  None)
            autor            = emp_info.get(agregado_por_id, {}) if agregado_por_id else {}
            items.append({
                "id":                  rd.id,
                "material_id":         rd.material_id,
                "nombre":              mat.nombre if mat else (nombre_libre or "Material Externo"),
                "unidad":              mat.unidad if mat else (unidad_libre or "Und"),
                "cantidad":            rd.cantidad,
                "es_nuevo":            rd.material_id is None,
                "especificacion":      especificacion,
                "agregado_por_nombre": autor.get("nombre", ""),
                "agregado_por_foto":   autor.get("foto",   ""),
            })

        return {"requerimiento_id": borrador.id, "items": items}

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error en GET /servicio/%s/borrador: %s", servicio_id, exc)
        raise HTTPException(status_code=500, detail=f"Error interno: {type(exc).__name__}: {exc}")


# ── POST /operaciones/servicio/{id}/borrador/item ─────────────────────────────

@router.post("/servicio/{servicio_id}/borrador/item", status_code=status.HTTP_201_CREATED)
async def agregar_item_borrador(
    servicio_id: str,
    body: AgregarBorradorBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    rol        = (payload.get("rol") or "").strip().lower()
    is_admin   = rol in {"administrador", "admin", "superadmin"}

    ps = _assert_servicio_abierto(servicio_id, db, empresa_id)

    # ── Lookup de empleado ────────────────────────────────────────────────────
    # Los administradores pueden no tener fila en 'empleado'.
    # Usamos _get_empleado_optional para no lanzar 403.
    empleado = _get_empleado_optional(db, usuario_id, empresa_id)

    if not empleado and not is_admin:
        raise HTTPException(
            status_code=403,
            detail="No eres empleado registrado en esta empresa. "
                   "Contacta al administrador para que vincule tu cuenta.",
        )

    # ── solicitante_id: nunca NULL (evita NotNullViolation sin migración) ─────
    # Si el usuario es admin sin empleado, usamos el jefe_operaciones del proyecto
    # como solicitante referencial. La columna sigue siendo NOT NULL en la BD.
    agregado_por_id = empleado.id if empleado else None   # requerimiento_detalle: ya nullable

    if empleado:
        solicitante_id: str = empleado.id
    else:
        # Admin sin empleado → buscamos al jefe del proyecto como fallback
        proyecto_obj = db.query(Proyecto).filter(Proyecto.id == ps.proyecto_id).first()
        jefe_emp_id  = proyecto_obj.jefe_operaciones_id if proyecto_obj else None

        if not jefe_emp_id:
            # Último recurso: primer empleado activo de la empresa
            primer_emp = db.query(Empleado).filter(
                Empleado.empresa_id == empresa_id,
                Empleado.activo     == True,
            ).first()
            jefe_emp_id = primer_emp.id if primer_emp else None

        if not jefe_emp_id:
            raise HTTPException(
                status_code=422,
                detail="La empresa no tiene empleados registrados. "
                       "Crea al menos un empleado antes de gestionar borradores.",
            )
        solicitante_id = jefe_emp_id

    # ── Borrador existente o nuevo ────────────────────────────────────────────
    borrador = db.query(Requerimiento).filter(
        Requerimiento.proyecto_servicio_id == servicio_id,
        Requerimiento.empresa_id           == empresa_id,
        Requerimiento.tipo                 == "material",
        Requerimiento.estado               == "borrador",
    ).first()

    if not borrador:
        borrador = Requerimiento(
            id                   = str(_uuid.uuid4()),
            proyecto_id          = ps.proyecto_id,
            proyecto_servicio_id = servicio_id,
            empresa_id           = empresa_id,
            solicitante_id       = solicitante_id,   # siempre un empleado.id válido
            tipo                 = "material",
            estado               = "borrador",
            fecha                = date.today(),
        )
        db.add(borrador)
        try:
            db.flush()
        except (IntegrityError, ProgrammingError) as exc:
            db.rollback()
            orig = str(getattr(exc, "orig", exc))
            raise HTTPException(
                status_code=500,
                detail=(
                    "No se pudo crear el borrador. "
                    "Verifica que la migración 'sync_schema_2026_05_20.sql' esté aplicada. "
                    f"Detalle BD: {orig}"
                ),
            )

    rd = RequerimientoDetalle(
        id               = str(_uuid.uuid4()),
        requerimiento_id = borrador.id,
        material_id      = body.material_id,
        cantidad         = body.cantidad,
    )
    if body.nombre:         rd.nombre_libre   = body.nombre
    if body.unidad:         rd.unidad_libre   = body.unidad
    if body.especificacion: rd.especificacion = body.especificacion
    rd.agregado_por_id = agregado_por_id   # None cuando admin sin empleado

    # Clasificación de la línea (material | herramienta):
    #  - Con material_id → se deriva del catálogo (material.tipo).
    #  - Texto libre     → se respeta lo que indique el usuario (body.tipo).
    if body.material_id:
        mat = db.query(Material).filter(Material.id == body.material_id).first()
        rd.tipo_item_compra = "herramienta" if (mat and mat.tipo == "herramienta") else "material"
    else:
        rd.tipo_item_compra = "herramienta" if (body.tipo or "").lower() == "herramienta" else "material"

    try:
        db.add(rd)
        db.commit()
    except (IntegrityError, ProgrammingError) as exc:
        db.rollback()
        orig = str(getattr(exc, "orig", exc))
        if "chk_req_estado" in orig or "borrador" in orig:
            raise HTTPException(
                status_code=500,
                detail=(
                    "La migración 'add_borrador_estado.sql' no fue ejecutada. "
                    "Ejecuta: psql -d <db> -f BACKEND/migrations/add_borrador_estado.sql"
                ),
            )
        if "nombre_libre" in orig or "unidad_libre" in orig or "especificacion" in orig:
            raise HTTPException(
                status_code=500,
                detail=(
                    "Columnas de compra externa no existen en la BD. "
                    "Ejecuta la migración 'add_borrador_estado.sql'."
                ),
            )
        raise HTTPException(status_code=500, detail=f"Error de BD: {orig}")

    try:
        from .chat_ws import manager as _ws_manager
        await _ws_manager.broadcast_servicio(
            servicio_id, {"tipo": "borrador_actualizado"}
        )
    except Exception:
        pass

    return {"ok": True, "requerimiento_id": borrador.id, "detalle_id": rd.id}


# ── DELETE /operaciones/borrador-detalle/{rd_id} ──────────────────────────────

@router.delete("/borrador-detalle/{rd_id}")
async def remover_item_borrador(
    rd_id:   str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    # Verificar ownership en una sola query con JOIN para evitar information disclosure
    rd = (
        db.query(RequerimientoDetalle)
        .join(Requerimiento, Requerimiento.id == RequerimientoDetalle.requerimiento_id)
        .filter(
            RequerimientoDetalle.id  == rd_id,
            Requerimiento.empresa_id == empresa_id,
            Requerimiento.estado     == "borrador",
        )
        .first()
    )
    if not rd:
        raise HTTPException(status_code=404, detail="Ítem no encontrado")

    req = db.query(Requerimiento).filter(
        Requerimiento.id == rd.requerimiento_id
    ).first()

    servicio_id = req.proyecto_servicio_id
    if servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(servicio_id))
    db.delete(rd)
    db.commit()

    try:
        from .chat_ws import manager as _ws_manager
        await _ws_manager.broadcast_servicio(
            servicio_id, {"tipo": "borrador_actualizado"}
        )
    except Exception:
        pass

    return {"ok": True}


# ── POST /operaciones/servicio/{id}/borrador/enviar ───────────────────────────

@router.post("/servicio/{servicio_id}/borrador/enviar")
async def enviar_borrador(
    servicio_id: str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
    firma_solicitante_url: str | None = Body(default=None, embed=True),
):
    empresa_id = payload["empresa_id"]

    _assert_servicio_abierto(servicio_id, db, empresa_id)

    borrador = db.query(Requerimiento).filter(
        Requerimiento.proyecto_servicio_id == servicio_id,
        Requerimiento.empresa_id           == empresa_id,
        Requerimiento.tipo                 == "material",
        Requerimiento.estado               == "borrador",
    ).first()
    if not borrador:
        raise HTTPException(status_code=404, detail="No hay borrador activo para este servicio")

    total_items = (
        db.query(RequerimientoDetalle)
        .filter(RequerimientoDetalle.requerimiento_id == borrador.id)
        .count()
    )
    if total_items == 0:
        raise HTTPException(status_code=422, detail="El borrador está vacío")

    borrador.estado     = "pendiente"
    borrador.fecha      = date.today()
    borrador.updated_at = datetime.utcnow()
    # Firma del solicitante al enviar el lote (la exige la app; el backend la
    # guarda si llega, para no romper builds antiguos en producción).
    if (firma_solicitante_url or "").strip():
        borrador.firma_solicitante_url   = firma_solicitante_url.strip()
        borrador.firma_solicitante_fecha = datetime.utcnow()
    db.commit()

    try:
        from .chat_ws import manager as _ws_manager
        await _ws_manager.broadcast_servicio(
            servicio_id, {"tipo": "borrador_actualizado"}
        )
    except Exception:
        pass

    return {"ok": True, "requerimiento_id": borrador.id}


# ── GET /operaciones/materiales/buscar ────────────────────────────────────────

@router.get("/materiales/buscar")
def buscar_materiales(
    q:       str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    stock_sq = (
        db.query(
            Stock.material_id,
            func.sum(Stock.cantidad).label("total"),
        )
        .filter(Stock.empresa_id == empresa_id)
        .group_by(Stock.material_id)
        .subquery()
    )

    rows = (
        db.query(
            Material.id,
            Material.nombre,
            Material.unidad,
            Material.tipo,
            func.coalesce(stock_sq.c.total, 0).label("stock"),
        )
        .outerjoin(stock_sq, stock_sq.c.material_id == Material.id)
        .filter(
            Material.empresa_id == empresa_id,
            Material.activo     == True,
            Material.nombre.ilike(f"%{q}%"),
        )
        .order_by(Material.nombre.asc())
        .limit(20)
        .all()
    )

    return [
        {
            "id": r.id, "nombre": r.nombre, "unidad": r.unidad,
            "stock": int(r.stock),
            # Clasificación del catálogo: consumible → 'material', herramienta → 'herramienta'
            "tipo": "herramienta" if r.tipo == "herramienta" else "material",
        }
        for r in rows
    ]


# ── GET /operaciones/proyecto/{proyecto_id}/equipos ───────────────────────────
# HU-18: Lista de equipos del proyecto con tipo y progreso

@router.get("/proyecto/{proyecto_id}/equipos", response_model=List[EquipoItemOut])
def get_equipos_proyecto(
    proyecto_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    rows = (
        db.query(Equipo, TipoEquipo.nombre.label("tipo_nombre"))
        .outerjoin(TipoEquipo, TipoEquipo.id == Equipo.tipo_equipo_id)
        .filter(
            Equipo.proyecto_id == proyecto_id,
            Equipo.empresa_id  == empresa_id,
        )
        .all()
    )

    return [
        EquipoItemOut(
            id=str(r.Equipo.id),
            nombre=r.Equipo.nombre,
            descripcion=r.Equipo.modelo,
            ubicacion=r.Equipo.ubicacion,
            estado=r.Equipo.estado,
            tipo=r.tipo_nombre,
            progreso_porcentaje=None,
        )
        for r in rows
    ]


# ── POST /operaciones/mantenimientos/{equipo_id}/finalizar ────────────────────
# HU-18: Cierra la orden activa, genera PDF y lo sube a Cloudinary

@router.post("/mantenimientos/{equipo_id}/finalizar", status_code=status.HTTP_200_OK)
def finalizar_mantenimiento(
    equipo_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    equipo = db.query(Equipo).filter(
        Equipo.id == equipo_id,
        Equipo.empresa_id == empresa_id,
    ).first()
    if not equipo:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    orden = (
        db.query(OrdenMantenimiento)
        .filter(
            OrdenMantenimiento.equipo_id  == equipo_id,
            OrdenMantenimiento.empresa_id == empresa_id,
            OrdenMantenimiento.estado.in_(["pendiente", "en_proceso"]),
        )
        .order_by(OrdenMantenimiento.created_at.desc())
        .first()
    )

    if not orden:
        orden = OrdenMantenimiento(
            id=str(_uuid.uuid4()),
            equipo_id=equipo_id,
            empresa_id=empresa_id,
            tecnico_id=empleado.id,
            tipo="preventivo",
            estado="completado",
            fecha=date.today(),
            fecha_inicio=datetime.utcnow(),
            fecha_fin=datetime.utcnow(),
        )
        db.add(orden)
        db.flush()
    else:
        orden.estado    = "completado"
        orden.fecha_fin = datetime.utcnow()
        if not orden.tecnico_id:
            orden.tecnico_id = empleado.id

    equipo.estado = "operativo"
    db.flush()

    evidencias = (
        db.query(EvidenciaMantenimiento)
        .filter(EvidenciaMantenimiento.orden_id == orden.id)
        .order_by(EvidenciaMantenimiento.fecha_captura.asc())
        .all()
    )

    # Empleado no tiene nombre/apellido — consultamos Usuario para el PDF
    tecnico_usr = db.query(Usuario).filter(Usuario.id == empleado.usuario_id).first()
    tecnico_nombre = (
        f"{tecnico_usr.nombre or ''} {tecnico_usr.apellido or ''}".strip()
        if tecnico_usr else "Técnico"
    )

    pdf_bytes = _generar_pdf_mantenimiento(
        equipo_nombre=equipo.nombre,
        orden_id=orden.id,
        fecha=orden.fecha_fin or datetime.utcnow(),
        tecnico_nombre=tecnico_nombre,
        evidencias=evidencias,
    )

    pdf_url = None
    pdf_public_id = f"e_zyro/{empresa_id}/informes/informe_{orden.id}"
    try:
        pdf_url = subir_pdf_bytes_cloudinary(pdf_bytes, pdf_public_id)
    except Exception:
        pass

    if pdf_url:
        informe = InformeTecnico(
            id=str(_uuid.uuid4()),
            orden_id=orden.id,
            empresa_id=empresa_id,
            titulo=f"Informe de Mantenimiento — {equipo.nombre}",
            contenido=f"Mantenimiento completado el {orden.fecha_fin.strftime('%d/%m/%Y')}",
            url_archivo=pdf_url,
            public_id_cloudinary=pdf_public_id,
            generado_por=empleado.id,
            fecha=date.today(),
        )
        db.add(informe)

    db.commit()
    return {
        "ok": True,
        "orden_id": orden.id,
        "pdf_url": pdf_url,
    }


def _generar_pdf_mantenimiento(
    equipo_nombre: str,
    orden_id: str,
    fecha: datetime,
    tecnico_nombre: str,
    evidencias: list,
) -> bytes:
    from reportlab.pdfgen import canvas as rl_canvas
    from reportlab.lib.pagesizes import A4

    buf = io.BytesIO()
    c = rl_canvas.Canvas(buf, pagesize=A4)
    w, h = A4

    c.setFont("Helvetica-Bold", 16)
    c.drawString(50, h - 60, "INFORME TÉCNICO DE MANTENIMIENTO")

    c.setFont("Helvetica", 11)
    c.drawString(50, h - 90,  f"Equipo:   {equipo_nombre}")
    c.drawString(50, h - 110, f"Técnico:  {tecnico_nombre}")
    c.drawString(50, h - 130, f"Fecha:    {fmt_lima(fecha, '%d/%m/%Y %H:%M')}")
    c.drawString(50, h - 150, f"Orden ID: {orden_id[:8]}...")

    c.setFont("Helvetica-Bold", 12)
    c.drawString(50, h - 190, "Evidencias fotográficas:")

    y = h - 215
    c.setFont("Helvetica", 10)
    for ev in evidencias:
        etapa    = ev.etapa.upper() if ev.etapa else ""
        fecha_ev = fmt_lima(ev.fecha_captura, "%d/%m/%Y %H:%M")
        c.drawString(60, y, f"• [{etapa}] {fecha_ev} — {ev.url_cloudinary[:60]}...")
        y -= 16
        if y < 80:
            c.showPage()
            y = h - 60

    c.setFont("Helvetica-Oblique", 9)
    c.drawString(50, 40, "Generado automáticamente por E-Zyro · Sistema de Gestión de Servicios")

    c.save()
    buf.seek(0)
    return buf.read()


# ── GET /operaciones/equipos/{equipo_id}/historial ────────────────────────────
# HU-19: Lista de mantenimientos previos del equipo

@router.get("/equipos/{equipo_id}/historial", response_model=List[MantenimientoHistorialOut])
def get_historial_equipo(
    equipo_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    equipo = db.query(Equipo).filter(
        Equipo.id == equipo_id,
        Equipo.empresa_id == empresa_id,
    ).first()
    if not equipo:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    ordenes = (
        db.query(OrdenMantenimiento)
        .filter(
            OrdenMantenimiento.equipo_id  == equipo_id,
            OrdenMantenimiento.empresa_id == empresa_id,
        )
        .order_by(OrdenMantenimiento.created_at.desc())
        .all()
    )

    if not ordenes:
        return []

    orden_ids   = [o.id for o in ordenes]
    tecnico_ids = list({o.tecnico_id for o in ordenes if o.tecnico_id})

    tecnicos_map: dict[str, str] = {}
    if tecnico_ids:
        # Empleado no tiene nombre/apellido — JOIN con Usuario es obligatorio
        tec_rows = (
            db.query(Empleado, Usuario)
            .join(Usuario, Usuario.id == Empleado.usuario_id)
            .filter(Empleado.id.in_(tecnico_ids))
            .all()
        )
        tecnicos_map = {
            str(emp.id): f"{usr.nombre or ''} {usr.apellido or ''}".strip() or "Técnico"
            for emp, usr in tec_rows
            if emp is not None
        }

    evidencias_rows = (
        db.query(EvidenciaMantenimiento)
        .filter(EvidenciaMantenimiento.orden_id.in_(orden_ids))
        .order_by(EvidenciaMantenimiento.fecha_captura.asc())
        .all()
    )
    evidencias_by_orden: dict[str, list] = {}
    for ev in evidencias_rows:
        evidencias_by_orden.setdefault(ev.orden_id, []).append(ev)

    informes_rows = (
        db.query(InformeTecnico)
        .filter(InformeTecnico.orden_id.in_(orden_ids))
        .all()
    )
    informes_map: dict[str, InformeTecnico] = {i.orden_id: i for i in informes_rows}

    proyecto_nombre = "Sin proyecto"
    if equipo.proyecto_id:
        proy = db.query(Proyecto).filter(Proyecto.id == equipo.proyecto_id).first()
        if proy:
            proyecto_nombre = proy.nombre_proyecto or proy.orden_trabajo or "Proyecto"

    result = []
    for orden in ordenes:
        fotos = [
            FotoEvidenciaOut(
                url=ev.url_cloudinary,
                tipo=ev.etapa or "antes",
                fecha=fmt_lima(ev.fecha_captura, "%d/%m/%Y %H:%M") or None,
            )
            for ev in evidencias_by_orden.get(orden.id, [])
        ]
        informe = informes_map.get(orden.id)
        result.append(MantenimientoHistorialOut(
            id=str(orden.id),
            fecha=orden.fecha.strftime("%d/%m/%Y") if orden.fecha else "",
            tecnico_nombre=tecnicos_map.get(orden.tecnico_id or "", "Sin técnico"),
            proyecto_nombre=proyecto_nombre,
            estado=orden.estado or "completado",
            fotos=fotos,
            informe_pdf_url=informe.url_archivo if informe else None,
            evidencias_zip_url=None,
        ))

    return result


# ── GET /operaciones/mantenimientos/{mantenimiento_id}/informe-pdf ─────────────
# HU-19: URL del PDF del informe técnico

@router.get("/mantenimientos/{mantenimiento_id}/informe-pdf")
def get_informe_pdf(
    mantenimiento_id: str,
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    informe = (
        db.query(InformeTecnico)
        .filter(
            InformeTecnico.orden_id   == mantenimiento_id,
            InformeTecnico.empresa_id == empresa_id,
        )
        .first()
    )

    if not informe or not informe.url_archivo:
        raise HTTPException(status_code=404, detail="Informe PDF no disponible")

    return {"url": informe.url_archivo}


# ── GET /operaciones/mantenimientos/{mantenimiento_id}/evidencias-zip ──────────
# HU-19: Genera un ZIP con todas las evidencias y sube a Cloudinary

@router.get("/mantenimientos/{mantenimiento_id}/evidencias-zip")
def get_evidencias_zip(
    mantenimiento_id: str,
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    import cloudinary.uploader

    empresa_id = payload["empresa_id"]

    orden = db.query(OrdenMantenimiento).filter(
        OrdenMantenimiento.id         == mantenimiento_id,
        OrdenMantenimiento.empresa_id == empresa_id,
    ).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden no encontrada")

    evidencias = (
        db.query(EvidenciaMantenimiento)
        .filter(EvidenciaMantenimiento.orden_id == mantenimiento_id)
        .all()
    )
    if not evidencias:
        raise HTTPException(status_code=404, detail="Sin evidencias para esta orden")

    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        for i, ev in enumerate(evidencias):
            try:
                resp = _requests.get(ev.url_cloudinary, timeout=10)
                if resp.status_code == 200:
                    ext = ev.url_cloudinary.rsplit(".", 1)[-1].split("?")[0] or "jpg"
                    zf.writestr(f"{ev.etapa or 'foto'}_{i+1:02d}.{ext}", resp.content)
            except Exception:
                continue

    zip_buf.seek(0)
    zip_bytes = zip_buf.read()

    if not zip_bytes:
        raise HTTPException(status_code=500, detail="No se pudo generar el ZIP")

    try:
        public_id = f"e_zyro/{empresa_id}/evidencias_zip/evidencias_{mantenimiento_id}.zip"
        resultado = cloudinary.uploader.upload(
            io.BytesIO(zip_bytes),
            public_id=public_id,
            resource_type="raw",
            overwrite=True,
            invalidate=True,
        )
        return {"url": resultado.get("secure_url")}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error al subir ZIP")


# ════════════════════════════════════════════════════════════════════════════
# HU-MANT: Checklist técnico por equipo, evidencias por paso, cierre.
# ════════════════════════════════════════════════════════════════════════════

# Pasos por defecto cuando el tipo_equipo no tiene procedimiento_tecnico definido.
_PASOS_POR_DEFECTO = [
    ("Inspección visual y diagnóstico inicial", "Revisión externa, identificación de fallas evidentes."),
    ("Medición de parámetros eléctricos / mecánicos", "Capturar lecturas de tensión, resistencia, presión u otros relevantes."),
    ("Aplicación del mantenimiento técnico", "Ejecutar el procedimiento correctivo o preventivo según corresponda."),
    ("Verificación post-mantenimiento", "Confirmar que el equipo opera dentro de los rangos esperados."),
]


def _parse_pasos_from_template(template: str | None) -> list[tuple[str, str]]:
    """Convierte un texto multilínea `tipo_equipo.procedimiento_tecnico` en pasos."""
    if not template:
        return list(_PASOS_POR_DEFECTO)
    pasos = []
    for raw in template.splitlines():
        line = raw.strip().lstrip("-•").strip()
        if not line:
            continue
        # Formato esperado opcional: "Nombre: descripción"
        if ":" in line:
            nombre, desc = line.split(":", 1)
            pasos.append((nombre.strip(), desc.strip()))
        else:
            pasos.append((line, ""))
    return pasos or list(_PASOS_POR_DEFECTO)


def _ensure_pasos_for_equipo(db: Session, equipo: Equipo) -> list[PasoMantenimiento]:
    """Devuelve los pasos del equipo. Si no existen, los crea desde la plantilla."""
    pasos = (
        db.query(PasoMantenimiento)
        .filter(
            PasoMantenimiento.equipo_id  == equipo.id,
            PasoMantenimiento.empresa_id == equipo.empresa_id,
        )
        .order_by(PasoMantenimiento.orden.asc())
        .all()
    )
    if pasos:
        return pasos

    tipo = db.query(TipoEquipo).filter(TipoEquipo.id == equipo.tipo_equipo_id).first()
    template = tipo.procedimiento_tecnico if tipo else None
    plantilla = _parse_pasos_from_template(template)
    for i, (nombre, desc) in enumerate(plantilla, start=1):
        db.add(PasoMantenimiento(
            id          = str(_uuid.uuid4()),
            equipo_id   = equipo.id,
            empresa_id  = equipo.empresa_id,
            nombre      = nombre[:200],
            descripcion = desc or None,
            orden       = i,
            estado      = "pendiente",
        ))
    db.commit()
    return (
        db.query(PasoMantenimiento)
        .filter(
            PasoMantenimiento.equipo_id  == equipo.id,
            PasoMantenimiento.empresa_id == equipo.empresa_id,
        )
        .order_by(PasoMantenimiento.orden.asc())
        .all()
    )


# ── GET /operaciones/equipo/{equipo_id}/checklist ─────────────────────────────

@router.get("/equipo/{equipo_id}/checklist", response_model=ChecklistEquipoOut)
def get_checklist_equipo(
    equipo_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    equipo = db.query(Equipo).filter(
        Equipo.id         == equipo_id,
        Equipo.empresa_id == empresa_id,
    ).first()
    if not equipo:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    pasos = _ensure_pasos_for_equipo(db, equipo)

    # Buscar las evidencias por paso (todas las que tengan paso_id en estos pasos)
    paso_ids = [p.id for p in pasos]
    evidencias_rows = []
    if paso_ids:
        evidencias_rows = (
            db.query(EvidenciaMantenimiento)
            .filter(
                EvidenciaMantenimiento.paso_id.in_(paso_ids),
                EvidenciaMantenimiento.empresa_id == empresa_id,
            )
            .order_by(EvidenciaMantenimiento.fecha_captura.asc())
            .all()
        )
    fotos_by_paso: dict[str, list[str]] = {}
    for ev in evidencias_rows:
        fotos_by_paso.setdefault(ev.paso_id, []).append(ev.url_cloudinary)

    return ChecklistEquipoOut(
        equipo_id=str(equipo.id),
        equipo_nombre=equipo.nombre or "",
        pasos=[
            PasoChecklistOut(
                id=str(p.id),
                nombre=p.nombre or "",
                descripcion=p.descripcion or "",
                orden=p.orden or 1,
                estado=p.estado or "pendiente",
                fotos_urls=fotos_by_paso.get(p.id, []),
            )
            for p in pasos
        ],
    )


# ── POST /operaciones/paso/{paso_id}/evidencia ────────────────────────────────

_ETAPAS_MANT_VALIDAS = {"antes", "durante", "despues"}


@router.post("/paso/{paso_id}/evidencia", status_code=status.HTTP_201_CREATED)
async def subir_evidencia_paso(
    paso_id:  str,
    foto:     UploadFile = File(...),
    tipo:     str        = Form(...),  # ANTES | DURANTE | DESPUES (mayúsculas, viene de Flutter)
    lat:      str        = Form(default=""),
    lng:      str        = Form(default=""),
    taken_at: str        = Form(default=""),
    payload:  dict       = Depends(verificar_token),
    db:       Session    = Depends(get_db),
):
    etapa = tipo.strip().lower()
    if etapa not in _ETAPAS_MANT_VALIDAS:
        raise HTTPException(
            status_code=422,
            detail=f"tipo debe ser uno de: ANTES, DURANTE, DESPUES (recibido: {tipo})",
        )

    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    paso = db.query(PasoMantenimiento).filter(
        PasoMantenimiento.id         == paso_id,
        PasoMantenimiento.empresa_id == empresa_id,
    ).first()
    if not paso:
        raise HTTPException(status_code=404, detail="Paso no encontrado")

    equipo = db.query(Equipo).filter(
        Equipo.id         == paso.equipo_id,
        Equipo.empresa_id == empresa_id,
    ).first()
    if not equipo:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    # Empleado opcional: si el usuario es admin sin empleado, dejamos None.
    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()

    # Buscar/crear OrdenMantenimiento activa para este equipo
    orden = (
        db.query(OrdenMantenimiento)
        .filter(
            OrdenMantenimiento.equipo_id  == equipo.id,
            OrdenMantenimiento.empresa_id == empresa_id,
            OrdenMantenimiento.estado.in_(["pendiente", "en_proceso"]),
        )
        .order_by(OrdenMantenimiento.created_at.desc())
        .first()
    )
    if not orden:
        orden = OrdenMantenimiento(
            id           = str(_uuid.uuid4()),
            equipo_id    = equipo.id,
            empresa_id   = empresa_id,
            tecnico_id   = empleado.id if empleado else None,
            tipo         = "preventivo",
            estado       = "en_proceso",
            fecha        = date.today(),
            fecha_inicio = datetime.utcnow(),
        )
        db.add(orden)
        db.flush()
    elif orden.estado == "pendiente":
        orden.estado       = "en_proceso"
        orden.fecha_inicio = orden.fecha_inicio or datetime.utcnow()

    # Subir a Cloudinary
    folder = f"e_zyro/{empresa_id}/mantenimiento/{equipo.id}"
    try:
        url = await subir_archivo_cloudinary(foto, folder)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Error subiendo a Cloudinary: {exc}")
    pub_id = _extract_public_id(url)

    # Sobre-escribir evidencia anterior de la misma etapa (si existe) — política simple
    db.query(EvidenciaMantenimiento).filter(
        EvidenciaMantenimiento.paso_id    == paso_id,
        EvidenciaMantenimiento.empresa_id == empresa_id,
        EvidenciaMantenimiento.etapa      == etapa,
    ).delete(synchronize_session=False)

    ev = EvidenciaMantenimiento(
        id                   = str(_uuid.uuid4()),
        orden_id             = orden.id,
        empresa_id           = empresa_id,
        paso_id              = paso_id,
        etapa                = etapa,
        url_cloudinary       = url,
        public_id_cloudinary = pub_id,
    )
    db.add(ev)

    # Si el paso ya tiene al menos una evidencia, lo marcamos en_proceso;
    # cuando tiene las 3 etapas, completado.
    etapas_existentes = {etapa}
    etapas_existentes.update({
        e.etapa for e in db.query(EvidenciaMantenimiento)
        .filter(EvidenciaMantenimiento.paso_id == paso_id)
        .all()
    })
    if _ETAPAS_MANT_VALIDAS.issubset(etapas_existentes):
        paso.estado = "completado"
    elif paso.estado == "pendiente":
        paso.estado = "en_proceso"
    paso.updated_at = datetime.utcnow()

    # Estado del equipo
    if equipo.estado == "operativo":
        equipo.estado = "en_mantenimiento"

    db.commit()

    return {
        "ok": True,
        "url": url,
        "etapa": etapa,
        "paso_id": paso_id,
        "paso_estado": paso.estado,
    }


# ── PATCH /operaciones/equipo/{id}/mantenimiento ──────────────────────────────

@router.patch("/equipo/{equipo_id}/mantenimiento")
def patch_mantenimiento_equipo(
    equipo_id: str,
    body:      PatchMantenimientoBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    estados_validos = {"pendiente", "en_proceso", "completado"}
    if body.status not in estados_validos:
        raise HTTPException(status_code=422, detail="status inválido")

    empresa_id = payload["empresa_id"]

    equipo = db.query(Equipo).filter(
        Equipo.id         == equipo_id,
        Equipo.empresa_id == empresa_id,
    ).first()
    if not equipo:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    # Mapear estado del checklist al estado del equipo + cerrar la orden si toca
    if body.status == "completado":
        equipo.estado = "operativo"
        orden = (
            db.query(OrdenMantenimiento)
            .filter(
                OrdenMantenimiento.equipo_id  == equipo_id,
                OrdenMantenimiento.empresa_id == empresa_id,
                OrdenMantenimiento.estado.in_(["pendiente", "en_proceso"]),
            )
            .order_by(OrdenMantenimiento.created_at.desc())
            .first()
        )
        if orden:
            orden.estado    = "completado"
            orden.fecha_fin = datetime.utcnow()
    elif body.status == "en_proceso":
        equipo.estado = "en_mantenimiento"
    else:  # pendiente
        equipo.estado = "operativo"

    equipo.updated_at = datetime.utcnow()
    db.commit()

    return {"ok": True, "equipo_id": equipo_id, "status": body.status}


# ════════════════════════════════════════════════════════════════════════════
# CRUD COMPLETO: Clientes · Catálogo · Personal · Proyectos · Servicios
# ════════════════════════════════════════════════════════════════════════════

def _parse_date(val: "str | None"):
    """Convierte 'YYYY-MM-DD' o 'YYYY-MM-DDTHH:MM:SS' a date. None si vacío."""
    if not val:
        return None
    try:
        return date.fromisoformat(val.split("T")[0])
    except (ValueError, AttributeError):
        return None


def _get_jefe_empleado(db: Session, usuario_id: str, empresa_id: str) -> "Empleado | None":
    """Devuelve el empleado del usuario logueado, o el primer empleado activo si no tiene."""
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    if emp:
        return emp
    # Fallback: primer empleado activo de la empresa (para admins sin fila empleado)
    return db.query(Empleado).filter(
        Empleado.empresa_id == empresa_id,
        Empleado.activo     == True,
    ).order_by(Empleado.created_at.asc()).first()


# ── Orden de trabajo auto-correlativa ─────────────────────────────────────────

def _siguiente_orden_trabajo(db: Session, empresa_id: str, anio: int | None = None) -> str:
    """
    Genera el siguiente N° de Orden de Trabajo en formato 'YYYY-NNN' (correlativo
    por año), RELLENANDO HUECOS: si se eliminó un proyecto, su número queda libre
    y el siguiente proyecto lo reutiliza. Así la secuencia nunca tiene huecos.
    """
    anio = anio or datetime.utcnow().year
    prefijo = f"{anio}-"
    filas = (
        db.query(Proyecto.orden_trabajo)
        .filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.orden_trabajo.like(f"{prefijo}%"),
        )
        .all()
    )
    patron = re.compile(rf"^{anio}-(\d+)$")
    usados: set[int] = set()
    for (ot,) in filas:
        if not ot:
            continue
        m = patron.match(ot.strip())
        if m:
            usados.add(int(m.group(1)))

    n = 1
    while n in usados:
        n += 1
    return f"{prefijo}{n:03d}"


# ── Liderazgo: roles que pueden liderar un servicio ───────────────────────────

def _norm_rol(nombre: str | None) -> str:
    """Normaliza un nombre de rol: minúsculas, sin acentos, sin separadores."""
    base = unicodedata.normalize("NFKD", nombre or "").encode("ascii", "ignore").decode()
    return re.sub(r"[\s_\-]+", " ", base).strip().lower()


# Estados terminales del servicio (comparación case-insensitive).
_ESTADOS_SERVICIO_TERMINADO = {"completado", "finalizado", "terminado"}


def _exigir_servicio_abierto(db: Session, empresa_id: str, servicio_id: str) -> "ProyectoServicio":
    """Verifica que el servicio exista y esté en un estado editable.
    Lanza HTTP 409 si ya está Completado/finalizado/terminado (o Cancelado).
    Devuelve el objeto ProyectoServicio para reuso en el endpoint.
    """
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")
    estado = (ps.estado or "").strip().lower()
    if estado in _ESTADOS_SERVICIO_TERMINADO:
        raise HTTPException(
            status_code=409,
            detail="El servicio está terminado: solo lectura",
        )
    if estado == "cancelado":
        raise HTTPException(
            status_code=409,
            detail="El servicio está cancelado y no acepta modificaciones.",
        )
    return ps


def _assert_servicio_abierto(ps_id: str, db: Session, empresa_id: str) -> "ProyectoServicio":
    """Alias legado de _exigir_servicio_abierto (firma antigua)."""
    return _exigir_servicio_abierto(db, empresa_id, ps_id)


def _rol_es_lider(nombre_rol: str | None) -> bool:
    """True si el rol habilita a liderar un servicio: Jefe de Operaciones/Proyecto o Admin."""
    n = _norm_rol(nombre_rol)
    if n in ("administrador", "admin", "superadmin"):
        return True
    return "jefe" in n and ("operac" in n or "proyect" in n)


def _lideres_elegibles(db: Session, empresa_id: str):
    """Empleados activos cuyo usuario tiene un rol que habilita liderar servicios."""
    rows = (
        db.query(
            Empleado.id.label("emp_id"),
            Usuario.nombre.label("nombre"),
            Usuario.apellido.label("apellido"),
            Empleado.cargo.label("cargo"),
            Usuario.foto_url.label("foto_url"),
            Rol.nombre.label("rol_nombre"),
        )
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .join(UsuarioRol, UsuarioRol.usuario_id == Usuario.id)
        .join(Rol, Rol.id == UsuarioRol.rol_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
        .order_by(Usuario.nombre.asc(), Usuario.apellido.asc())
        .all()
    )
    vistos: dict[str, object] = {}
    for r in rows:
        eid = str(r.emp_id)
        if eid not in vistos and _rol_es_lider(r.rol_nombre):
            vistos[eid] = r
    return list(vistos.values())


def _empleado_es_lider_elegible(db: Session, empleado_id: str, empresa_id: str) -> bool:
    """Valida que un empleado (por su rol de usuario) pueda ser Líder del Servicio."""
    rows = (
        db.query(Rol.nombre)
        .join(UsuarioRol, UsuarioRol.rol_id == Rol.id)
        .join(Empleado, Empleado.usuario_id == UsuarioRol.usuario_id)
        .filter(Empleado.id == empleado_id, Empleado.empresa_id == empresa_id)
        .all()
    )
    return any(_rol_es_lider(n) for (n,) in rows)


_ROLES_ADMIN_NORM = {"superadmin", "admin", "administrador"}


def _empleado_ids_admin(db: Session, empresa_id: str) -> set[str]:
    """IDs de empleado cuyo usuario tiene rol Admin/SuperAdmin en la empresa.

    Se usan para EXCLUIR al usuario administrador del sistema (p.ej. "Admin
    Sistema") de las listas de asignación de equipo de un servicio: el admin
    gestiona, no se asigna como técnico/responsable.
    """
    rows = (
        db.query(Empleado.id)
        .join(UsuarioRol, UsuarioRol.usuario_id == Empleado.usuario_id)
        .join(Rol, Rol.id == UsuarioRol.rol_id)
        .filter(
            Empleado.empresa_id == empresa_id,
            func.replace(func.lower(Rol.nombre), " ", "").in_(_ROLES_ADMIN_NORM),
        )
        .all()
    )
    return {str(r[0]) for r in rows}


def _notificar_servicio_pendiente_a_jefes(
    db: Session, empresa_id: str, ps: ProyectoServicio,
    exclude_usuario_id: str | None = None,
) -> None:
    """Notifica a TODOS los Jefes de Operaciones de la empresa que hay un
    servicio pendiente SIN líder (nadie lo acaparó todavía), para que puedan
    tomarlo. Se dispara al crear un servicio sin líder — es justo el caso en
    que todos los jefes deben verlo (ver filtro de visibilidad en
    `get_servicios_proyecto`). No bloquea la creación si la notificación falla.
    `exclude_usuario_id` evita auto-notificar a quien lo creó."""
    try:
        from ..services.fcm_service import notificar_usuario
        rows = (
            db.query(Usuario.id, Rol.nombre)
            .join(UsuarioRol, UsuarioRol.usuario_id == Usuario.id)
            .join(Rol, Rol.id == UsuarioRol.rol_id)
            .filter(Usuario.empresa_id == empresa_id, Usuario.activo == True)
            .all()
        )
        usuario_ids = {
            str(uid) for uid, rnombre in rows
            if "jefe" in _norm_rol(rnombre) and "operac" in _norm_rol(rnombre)
        }
        usuario_ids.discard(str(exclude_usuario_id) if exclude_usuario_id else None)
        if not usuario_ids:
            return
        nombre_srv = ps.nombre or "Un servicio"
        for uid in usuario_ids:
            notificar_usuario(
                db, empresa_id=empresa_id, usuario_id=uid,
                titulo="Nuevo servicio disponible",
                mensaje=f"{nombre_srv} está pendiente y sin líder asignado. Puedes tomarlo.",
                tipo="servicio", categoria="servicio",
                referencia_id=str(ps.id), referencia_tabla="proyecto_servicio",
            )
        db.commit()
    except Exception:
        # La notificación nunca debe romper la creación del servicio.
        db.rollback()


def _jefe_op_asignado_al_servicio(db: Session, payload: dict, empresa_id: str,
                                  servicio_id: str) -> bool:
    """True si el usuario está asignado al proyecto del servicio — como Jefe de
    Operaciones del proyecto o como miembro del equipo.

    Principio de Operaciones: lo que habilita gestionar un servicio NO es solo el
    rol, sino la **asignación por proyecto/servicio**. Un Jefe de Operaciones
    asignado al proyecto gestiona sus tareas sin justificación; la justificación
    solo se exige cuando toca un proyecto que NO es suyo (caso de auditoría).
    """
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == payload.get("id"),
        Empleado.empresa_id == empresa_id,
    ).first()
    if not emp:
        return False
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        return False
    proyecto = db.query(Proyecto).filter(Proyecto.id == ps.proyecto_id).first()
    if proyecto and proyecto.jefe_operaciones_id == emp.id:
        return True
    return db.query(ProyectoMiembro).filter(
        ProyectoMiembro.proyecto_id == ps.proyecto_id,
        ProyectoMiembro.empleado_id == emp.id,
    ).first() is not None


_TIPOS_DOC_OK = {"OC", "PROF", "SIN_OC"}


def _normalizar_documento(tipo: str | None, nro: str | None) -> tuple[str, str | None]:
    """Devuelve (tipo_doc, nro_doc) saneados. 'SIN_OC' fuerza nro a None."""
    t = (tipo or "SIN_OC").strip().upper()
    if t not in _TIPOS_DOC_OK:
        t = "SIN_OC"
    if t == "SIN_OC":
        return t, None
    n = (nro or "").strip()
    return t, (n or None)


# ── GET /operaciones/clientes ─────────────────────────────────────────────────

@router.get("/clientes", response_model=list[ClienteOut])
def get_clientes(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Lista de clientes activos de la empresa (para el modal de nuevo proyecto)."""
    empresa_id = payload["empresa_id"]
    clientes = (
        db.query(Cliente)
        .filter(Cliente.empresa_id == empresa_id, Cliente.activo == True)
        .order_by(Cliente.razon_social.asc())
        .all()
    )
    return [ClienteOut(id=str(c.id), razon_social=c.razon_social, ruc=c.ruc) for c in clientes]


# ── GET /operaciones/proyectos/siguiente-orden ────────────────────────────────

@router.get("/proyectos/siguiente-orden", response_model=SiguienteOrdenOut)
def get_siguiente_orden_trabajo(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Devuelve el próximo N° de Orden de Trabajo que asignaría el sistema (preview read-only)."""
    empresa_id = payload["empresa_id"]
    return SiguienteOrdenOut(orden_trabajo=_siguiente_orden_trabajo(db, empresa_id))


# ── GET /operaciones/lideres-servicio ─────────────────────────────────────────

@router.get("/lideres-servicio", response_model=list[PersonaServicioOut])
def get_lideres_servicio(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Empleados que pueden ser Líder del Servicio (Jefe de Operaciones / Jefe de Proyecto)."""
    empresa_id = payload["empresa_id"]
    return [
        PersonaServicioOut(
            id=str(r.emp_id),
            nombre=r.nombre or "",
            apellido=r.apellido or "",
            cargo=r.cargo or None,
            foto_url=r.foto_url or None,
        )
        for r in _lideres_elegibles(db, empresa_id)
    ]


# ── GET /operaciones/responsables-servicio ────────────────────────────────────

@router.get("/responsables-servicio", response_model=list[PersonaServicioOut])
def get_responsables_servicio(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Todos los empleados activos — candidatos a Técnico Líder del servicio (opcional)."""
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(
            Empleado.id.label("emp_id"),
            Usuario.nombre.label("nombre"),
            Usuario.apellido.label("apellido"),
            Empleado.cargo.label("cargo"),
            Usuario.foto_url.label("foto_url"),
        )
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
        .order_by(Usuario.nombre.asc(), Usuario.apellido.asc())
        .all()
    )
    admin_ids = _empleado_ids_admin(db, empresa_id)
    return [
        PersonaServicioOut(
            id=str(r.emp_id),
            nombre=r.nombre or "",
            apellido=r.apellido or "",
            cargo=r.cargo or None,
            foto_url=r.foto_url or None,
        )
        for r in rows
        if str(r.emp_id) not in admin_ids
    ]


# ── GET /operaciones/catalogo-servicios ───────────────────────────────────────

@router.get("/catalogo-servicios", response_model=list[CatalogoServicioOut])
def get_catalogo_servicios(
    incluir_inactivos: bool = Query(False, description="Incluye tipos de servicio desactivados (pantallas de gestión)"),
    payload:           dict    = Depends(verificar_token),
    db:                Session = Depends(get_db),
):
    """Lista del catálogo de servicios de la empresa. Por defecto solo activos
    (selectores de creación de servicio); `incluir_inactivos=true` para la
    pantalla de gestión del catálogo."""
    empresa_id = payload["empresa_id"]
    q = db.query(CatalogoServicio).filter(CatalogoServicio.empresa_id == empresa_id)
    if not incluir_inactivos:
        q = q.filter(CatalogoServicio.activo == True)
    items = q.order_by(CatalogoServicio.nombre.asc()).all()
    return [
        CatalogoServicioOut(
            id=str(c.id),
            nombre=c.nombre,
            tipo_trabajo=c.tipo_trabajo or "",
            descripcion=c.descripcion,
            activo=bool(c.activo),
        )
        for c in items
    ]


@router.post("/catalogo-servicios", response_model=CatalogoServicioOut)
def crear_catalogo_servicio(
    body:    CatalogoServicioIn,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Crea un tipo de servicio nuevo. Gestionable desde la app — antes era
    dato maestro que solo se insertaba directo en la BD."""
    exigir_permiso(db, payload, "catalogos", "editar")
    nombre = (body.nombre or "").strip()
    tipo   = (body.tipo_trabajo or "").strip()
    if not nombre or not tipo:
        raise HTTPException(status_code=422, detail="nombre y tipo_trabajo son obligatorios")

    c = CatalogoServicio(
        id           = str(_uuid.uuid4()),
        empresa_id   = payload["empresa_id"],
        nombre       = nombre[:150],
        tipo_trabajo = tipo[:50],
        descripcion  = (body.descripcion or None),
        activo       = True,
        created_at   = datetime.utcnow(),
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return CatalogoServicioOut(id=str(c.id), nombre=c.nombre, tipo_trabajo=c.tipo_trabajo, descripcion=c.descripcion)


@router.put("/catalogo-servicios/{catalogo_id}", response_model=CatalogoServicioOut)
def editar_catalogo_servicio(
    catalogo_id: str,
    body:        CatalogoServicioIn,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    exigir_permiso(db, payload, "catalogos", "editar")
    c = db.query(CatalogoServicio).filter(
        CatalogoServicio.id         == catalogo_id,
        CatalogoServicio.empresa_id == payload["empresa_id"],
    ).first()
    if not c:
        raise HTTPException(status_code=404, detail="Tipo de servicio no encontrado")

    nombre = (body.nombre or "").strip()
    tipo   = (body.tipo_trabajo or "").strip()
    if not nombre or not tipo:
        raise HTTPException(status_code=422, detail="nombre y tipo_trabajo son obligatorios")

    c.nombre       = nombre[:150]
    c.tipo_trabajo = tipo[:50]
    c.descripcion  = (body.descripcion or None)
    db.commit()
    db.refresh(c)
    return CatalogoServicioOut(id=str(c.id), nombre=c.nombre, tipo_trabajo=c.tipo_trabajo, descripcion=c.descripcion)


@router.patch("/catalogo-servicios/{catalogo_id}/estado")
def cambiar_estado_catalogo_servicio(
    catalogo_id: str,
    body:        CatalogoServicioEstadoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Activar/desactivar (soft-delete) un tipo de servicio. Desactivado =
    desaparece de los selectores de creación de servicio, sin borrar histórico."""
    exigir_permiso(db, payload, "catalogos", "editar")
    c = db.query(CatalogoServicio).filter(
        CatalogoServicio.id         == catalogo_id,
        CatalogoServicio.empresa_id == payload["empresa_id"],
    ).first()
    if not c:
        raise HTTPException(status_code=404, detail="Tipo de servicio no encontrado")
    c.activo = body.activo
    db.commit()
    return {"ok": True, "activo": c.activo}


# ── GET /operaciones/personal/tecnicos ────────────────────────────────────────

@router.get("/personal/tecnicos", response_model=PersonalTecnicosOut)
def get_personal_tecnicos(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Devuelve todos los empleados activos de la empresa con sus datos de usuario,
    más los grupos de trabajo con sus miembros (para asignación masiva).

    FIX 2026-05-25: Todas las PKs/FKs de la BD son UUID nativos de PostgreSQL.
    psycopg2 los devuelve como objetos uuid.UUID, no como str. Si los pasamos
    directamente a los schemas Pydantic (que esperan Optional[str]) se produce
    una ValidationError → HTTP 500. Solución: normalizar a str() en cuanto
    salen de la base de datos, ANTES de usarlos como clave de diccionario o
    valor de schema.
    """
    empresa_id = payload["empresa_id"]

    # ─────────────────────────────────────────────────────────────────────────
    # 1. Empleados activos JOIN Usuario — un solo round-trip
    #    Seleccionamos columnas explícitas para evitar ORM lazy-loading.
    # ─────────────────────────────────────────────────────────────────────────
    emp_rows = (
        db.query(
            Empleado.id.label("emp_id"),
            Empleado.cargo.label("cargo"),
            Empleado.usuario_id.label("usuario_id"),
            Usuario.nombre.label("nombre"),
            Usuario.apellido.label("apellido"),
            Usuario.foto_url.label("foto_url"),
        )
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(
            Empleado.empresa_id == empresa_id,
            Empleado.activo     == True,
        )
        .order_by(Usuario.nombre.asc(), Usuario.apellido.asc())
        .all()
    )

    # Excluir al usuario administrador del sistema ("Admin Sistema"): gestiona,
    # no se asigna como técnico/miembro de equipo de un servicio.
    _admin_ids = _empleado_ids_admin(db, empresa_id)
    if _admin_ids:
        emp_rows = [r for r in emp_rows if str(r.emp_id) not in _admin_ids]

    # ─────────────────────────────────────────────────────────────────────────
    # 2. Grupos de trabajo activos
    # ─────────────────────────────────────────────────────────────────────────
    grupos_db = (
        db.query(GrupoTrabajo)
        .filter(
            GrupoTrabajo.empresa_id == empresa_id,
            GrupoTrabajo.activo     == True,
        )
        .order_by(GrupoTrabajo.nombre.asc())
        .all()
    )
    # Normalizar IDs de grupos a str inmediatamente
    grupo_ids_str: list[str] = [str(g.id) for g in grupos_db]

    # grupo_id_str → nombre_str  (lookup O(1) garantizado)
    grupo_nombre_map: dict[str, str] = {
        str(g.id): (g.nombre or "") for g in grupos_db
    }

    # ─────────────────────────────────────────────────────────────────────────
    # 3. Miembros activos de esos grupos
    #    Usamos grupo_ids_str (strings) para el .in_() — PostgreSQL admite
    #    implicit cast de varchar → uuid.
    # ─────────────────────────────────────────────────────────────────────────
    miembros_db = []
    if grupo_ids_str:
        miembros_db = (
            db.query(GrupoMiembro)
            .filter(
                GrupoMiembro.grupo_id.in_(grupo_ids_str),
                GrupoMiembro.activo == True,
            )
            .all()
        )

    # empleado_id_str → grupo_id_str  (primer grupo ganador)
    emp_a_grupo: dict[str, str] = {}
    for m in miembros_db:
        eid = str(m.empleado_id)
        if eid not in emp_a_grupo:
            emp_a_grupo[eid] = str(m.grupo_id)

    # ─────────────────────────────────────────────────────────────────────────
    # 3b. Ocupación REAL por servicio (regla de negocio): el grupo de trabajo
    #     se forma al asignar el equipo de un servicio y se libera cuando el
    #     servicio finaliza. Un técnico está "en un grupo" si es responsable
    #     de tareas de un servicio AÚN ACTIVO (Pendiente / En_Proceso).
    #     Esto alimenta `grupo_actual` → alerta HU-13 al re-asignarlo.
    # ─────────────────────────────────────────────────────────────────────────
    ocupacion_rows = (
        db.query(Tarea.responsable_id, ProyectoServicio.nombre)
        .join(ProyectoServicio, ProyectoServicio.id == Tarea.proyecto_servicio_id)
        .filter(
            ProyectoServicio.empresa_id == empresa_id,
            ProyectoServicio.estado.in_(["Pendiente", "En_Proceso"]),
            Tarea.responsable_id.isnot(None),
        )
        .all()
    )
    emp_a_servicio: dict[str, str] = {}
    for resp_id, svc_nombre in ocupacion_rows:
        rid = str(resp_id)
        if rid not in emp_a_servicio:
            emp_a_servicio[rid] = svc_nombre or "un servicio activo"

    # grupo_id_str → [empleado_id_str, ...]
    miembros_by_grupo: dict[str, list[str]] = {}
    for m in miembros_db:
        miembros_by_grupo.setdefault(str(m.grupo_id), []).append(str(m.empleado_id))

    # ─────────────────────────────────────────────────────────────────────────
    # 4. Construir TecnicoOut — todas las conversiones UUID→str aquí
    # ─────────────────────────────────────────────────────────────────────────
    tecnicos:  list[TecnicoOut]       = []
    emp_map:   dict[str, TecnicoOut]  = {}   # emp_id_str → TecnicoOut

    for row in emp_rows:
        emp_id_str  = str(row.emp_id)
        grupo_id_s  = emp_a_grupo.get(emp_id_str)          # str | None

        _grupo_nombre = grupo_nombre_map.get(grupo_id_s) if grupo_id_s else None
        tec = TecnicoOut(
            id           = emp_id_str,
            usuario_id   = str(row.usuario_id) if row.usuario_id else "",
            nombre       = str(row.nombre   or ""),
            apellido     = str(row.apellido or ""),
            cargo        = str(row.cargo    or "Técnico"),
            foto_url     = row.foto_url,          # str | None — OK
            grupo_id     = grupo_id_s,            # str | None — ya es str
            grupo_nombre = _grupo_nombre,
            # HU-13 — alerta de conflicto: prioriza la ocupación real (servicio
            # activo donde tiene tareas); cae al grupo manual si no hay ninguna.
            grupo_actual = emp_a_servicio.get(emp_id_str) or _grupo_nombre,
        )
        tecnicos.append(tec)
        emp_map[emp_id_str] = tec

    # ─────────────────────────────────────────────────────────────────────────
    # 5. Construir GrupoConMiembrosOut
    # ─────────────────────────────────────────────────────────────────────────
    # Nombres de jefes — un único JOIN para todos los grupos
    jefe_ids_str: list[str] = list({
        str(g.jefe_id) for g in grupos_db if g.jefe_id
    })
    jefe_map: dict[str, str] = {}
    if jefe_ids_str:
        jefe_rows = (
            db.query(
                Empleado.id.label("emp_id"),
                Usuario.nombre.label("nombre"),
                Usuario.apellido.label("apellido"),
            )
            .join(Usuario, Usuario.id == Empleado.usuario_id)
            .filter(Empleado.id.in_(jefe_ids_str))
            .all()
        )
        jefe_map = {
            str(r.emp_id): f"{r.nombre or ''} {r.apellido or ''}".strip() or "Sin nombre"
            for r in jefe_rows
        }

    grupos_out: list[GrupoConMiembrosOut] = []
    for g in grupos_db:
        g_id_str      = str(g.id)
        jefe_id_str   = str(g.jefe_id) if g.jefe_id else ""
        miembro_tecs  = [
            emp_map[eid]
            for eid in miembros_by_grupo.get(g_id_str, [])
            if eid in emp_map
        ]
        grupos_out.append(GrupoConMiembrosOut(
            id          = g_id_str,
            nombre      = str(g.nombre or ""),
            descripcion = g.descripcion,
            jefe_nombre = jefe_map.get(jefe_id_str, "Sin asignar"),
            miembros    = miembro_tecs,
        ))

    return PersonalTecnicosOut(tecnicos=tecnicos, grupos=grupos_out)


# ── POST /operaciones/personal/validar-horario ────────────────────────────────
# HU-13: Detecta si un técnico ya tiene tareas solapadas con el rango pedido.

@router.post("/personal/validar-horario")
def validar_horario_tecnico(
    body:    ValidarHorarioBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Verifica si un empleado tiene procedimientos en estado 'pendiente' o
    'en_proceso' que se solapen con [fecha_inicio, fecha_fin].

    Solapamiento entre (A_ini, A_fin) y (B_ini, B_fin):
        A_ini <= B_fin  AND  A_fin >= B_ini

    Retorna:
        {"conflicto": false}
        {"conflicto": true, "detalle": {...}}
    """
    from datetime import date as _date

    empresa_id = payload["empresa_id"]

    # Validar que el empleado pertenece a la empresa
    emp = db.query(Empleado).filter(
        Empleado.id         == body.empleado_id,
        Empleado.empresa_id == empresa_id,
        Empleado.activo     == True,
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    # Parsear fechas — el cliente manda YYYY-MM-DD
    try:
        fecha_ini_dt = _date.fromisoformat(body.fecha_inicio)
        fecha_fin_dt = _date.fromisoformat(body.fecha_fin)
    except ValueError:
        raise HTTPException(status_code=422, detail="Fechas inválidas. Use formato YYYY-MM-DD.")

    if fecha_fin_dt < fecha_ini_dt:
        raise HTTPException(status_code=422, detail="fecha_fin no puede ser anterior a fecha_inicio.")

    # Construir la query base (el cronograma vive en Tarea: responsable + fechas).
    # Solo cuentan tareas de servicios AÚN ACTIVOS: al finalizar/cancelar un
    # servicio sus técnicos quedan liberados y no generan conflicto de fechas.
    q = (
        db.query(Tarea)
        .join(ProyectoServicio, ProyectoServicio.id == Tarea.proyecto_servicio_id)
        .filter(
            Tarea.responsable_id     == body.empleado_id,
            Tarea.estado.in_(["pendiente", "en_proceso"]),
            ProyectoServicio.estado.in_(["Pendiente", "En_Proceso"]),
            Tarea.fecha_inicio_tarea != None,
            Tarea.fecha_limite       != None,
            # Condición de solapamiento
            Tarea.fecha_inicio_tarea <= fecha_fin_dt,
            Tarea.fecha_limite       >= fecha_ini_dt,
        )
    )

    # Excluir tareas del mismo servicio (para modo editar)
    if body.excluir_servicio_id:
        q = q.filter(
            Tarea.proyecto_servicio_id != body.excluir_servicio_id
        )

    conflicto = q.first()

    if not conflicto:
        return {"conflicto": False}

    # Recuperar nombre del servicio para el mensaje
    ps_nombre = "otro servicio"
    try:
        ps_obj = db.query(ProyectoServicio).filter(
            ProyectoServicio.id == conflicto.proyecto_servicio_id
        ).first()
        if ps_obj:
            ps_nombre = ps_obj.nombre or "otro servicio"
    except Exception:
        pass

    return {
        "conflicto": True,
        "detalle": {
            "tarea":           conflicto.nombre,
            "servicio_nombre": ps_nombre,
            "servicio_id":     str(conflicto.proyecto_servicio_id),
            "fecha_inicio":    str(conflicto.fecha_inicio_tarea),
            "fecha_fin":       str(conflicto.fecha_limite),
            "estado":          conflicto.estado,
        },
    }


# ── GET /operaciones/proyecto/{proyecto_id} ───────────────────────────────────

@router.get("/proyecto/{proyecto_id}", response_model=ProyectoEditOut)
def get_detalle_proyecto(
    proyecto_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Devuelve los datos de un proyecto para el modal de edición."""
    empresa_id = payload["empresa_id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    detalle = db.query(ProyectoDetalle).filter(
        ProyectoDetalle.proyecto_id == proyecto_id
    ).first()

    # Nombre del jefe de operaciones
    jefe_nombre = None
    if proyecto.jefe_operaciones_id:
        jefe_emp = db.query(Empleado).filter(Empleado.id == proyecto.jefe_operaciones_id).first()
        if jefe_emp:
            jefe_usr = db.query(Usuario).filter(Usuario.id == jefe_emp.usuario_id).first()
            if jefe_usr:
                jefe_nombre = f"{jefe_usr.nombre} {jefe_usr.apellido}".strip()

    return ProyectoEditOut(
        id=str(proyecto.id),
        nombre_proyecto=proyecto.nombre_proyecto or "",
        cliente_id=str(proyecto.cliente_id) if proyecto.cliente_id else "",
        orden_trabajo=proyecto.orden_trabajo or "",
        estado=proyecto.estado or "Pendiente",
        fecha_inicio=proyecto.fecha_inicio.isoformat() if proyecto.fecha_inicio else None,
        fecha_fin_estimada=proyecto.fecha_fin_estimada.isoformat() if proyecto.fecha_fin_estimada else None,
        orden_compra_cliente=detalle.orden_compra_cliente if detalle else None,
        jefe_nombre=jefe_nombre,
    )


# ── POST /operaciones/proyectos ───────────────────────────────────────────────

@router.post("/proyectos", status_code=status.HTTP_201_CREATED)
def crear_proyecto(
    body:    CrearProyectoBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Crea un nuevo proyecto y su detalle."""
    exigir_solo_admin(payload, "Solo Administradores pueden crear proyectos")
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    # Verificar que el cliente pertenece a la empresa
    cliente = db.query(Cliente).filter(
        Cliente.id         == body.cliente_id,
        Cliente.empresa_id == empresa_id,
    ).first()
    if not cliente:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")

    # Determinar jefe de operaciones (empleado logueado o primer empleado disponible)
    jefe = _get_jefe_empleado(db, usuario_id, empresa_id)
    if not jefe:
        raise HTTPException(
            status_code=422,
            detail="No hay empleados registrados en la empresa. "
                   "Crea al menos un empleado antes de crear proyectos.",
        )

    # El N° de Orden de Trabajo lo asigna el sistema (correlativo por año, rellena
    # huecos). Ignoramos cualquier valor enviado por el cliente.
    orden_trabajo = _siguiente_orden_trabajo(db, empresa_id)

    proyecto_id = str(_uuid.uuid4())
    ahora = datetime.utcnow()

    nuevo = Proyecto(
        id                  = proyecto_id,
        empresa_id          = empresa_id,
        cliente_id          = body.cliente_id,
        orden_trabajo       = orden_trabajo,
        jefe_operaciones_id = jefe.id,
        nombre_proyecto     = body.nombre_proyecto,
        estado              = body.estado or "Pendiente",
        fecha_inicio        = _parse_date(body.fecha_inicio),
        fecha_fin_estimada  = _parse_date(body.fecha_fin_estimada),
        created_at          = ahora,
    )
    db.add(nuevo)
    db.flush()

    # Detalle del proyecto: solo el OC "marco" (alcance/zona/doc viven por servicio)
    if body.orden_compra_cliente:
        db.add(ProyectoDetalle(
            proyecto_id          = proyecto_id,
            empresa_id           = empresa_id,
            orden_compra_cliente = body.orden_compra_cliente or None,
        ))

    # Agregar al jefe como miembro del proyecto
    db.add(ProyectoMiembro(
        id               = str(_uuid.uuid4()),
        proyecto_id      = proyecto_id,
        empleado_id      = jefe.id,
        rol_proyecto     = "Jefe de Operaciones",
        fecha_asignacion = ahora.date(),
        activo           = True,
    ))

    # Controlling: cada proyecto nace con su centro de costo, para poder
    # imputar gastos y que Rentabilidad calcule margen sin pasos manuales.
    from app.services.controlling_service import asegurar_centro_proyecto
    asegurar_centro_proyecto(db, empresa_id, proyecto_id,
                             codigo=f"PRY-{orden_trabajo}",
                             nombre=body.nombre_proyecto)

    db.commit()
    return {"ok": True, "id": proyecto_id, "orden_trabajo": orden_trabajo}


# ── PATCH /operaciones/proyecto/{proyecto_id} ─────────────────────────────────

@router.patch("/proyecto/{proyecto_id}")
def actualizar_proyecto(
    proyecto_id: str,
    body:        ActualizarProyectoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Actualiza los campos de un proyecto y su detalle."""
    exigir_no_tecnico(payload, "Técnico no puede editar proyectos")
    empresa_id = payload["empresa_id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    # El N° de Orden de Trabajo lo gestiona el sistema y NO es editable.

    # Verificar cliente si cambió
    if body.cliente_id and body.cliente_id != str(proyecto.cliente_id):
        cliente = db.query(Cliente).filter(
            Cliente.id         == body.cliente_id,
            Cliente.empresa_id == empresa_id,
        ).first()
        if not cliente:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")

    # Actualizar campos del proyecto
    if body.nombre_proyecto is not None:
        proyecto.nombre_proyecto = body.nombre_proyecto
    if body.cliente_id is not None:
        proyecto.cliente_id = body.cliente_id
    if body.estado is not None:
        proyecto.estado = body.estado
    if body.fecha_inicio is not None:
        proyecto.fecha_inicio = _parse_date(body.fecha_inicio)
    if body.fecha_fin_estimada is not None:
        proyecto.fecha_fin_estimada = _parse_date(body.fecha_fin_estimada)
    proyecto.updated_at = datetime.utcnow()

    # Actualizar o crear ProyectoDetalle (solo OC "marco")
    if body.orden_compra_cliente is not None:
        det = db.query(ProyectoDetalle).filter(
            ProyectoDetalle.proyecto_id == proyecto_id
        ).first()
        if det:
            det.orden_compra_cliente = body.orden_compra_cliente or None
            det.updated_at = datetime.utcnow()
        else:
            db.add(ProyectoDetalle(
                proyecto_id          = proyecto_id,
                empresa_id           = empresa_id,
                orden_compra_cliente = body.orden_compra_cliente or None,
            ))

    db.commit()
    return {"ok": True}


# ── Helper: vincular equipos de una ubicación/zona a su servicio ─────────────

def _vincular_equipos_al_servicio(
    db: Session,
    ps: "ProyectoServicio",
    empresa_id: str,
    proyecto: "Proyecto",
) -> int:
    """Auto-vincula todos los equipos de la ubicación/zona del servicio a ese servicio.

    Reglas:
    - Solo actúa cuando tiene_equipos_intervenidos=True y ubicacion_id está definido.
    - Filtra por zona exacta si hay zona_id; si no, por ubicacion completa.
    - Resetea estado_intervencion='pendiente' excepto en equipos que ya están
      'en_proceso' para ESTE mismo servicio (no interrumpe inspecciones activas).
    - Propaga proyecto_id y cliente_id a todos los equipos vinculados.
    """
    if not getattr(ps, "tiene_equipos_intervenidos", False):
        return 0
    if not ps.ubicacion_id:
        return 0

    ps_id      = str(ps.id)
    proy_id    = str(proyecto.id)
    cliente_id = str(proyecto.cliente_id) if proyecto.cliente_id else None

    filtros = [
        EquipoIntervenido.empresa_id   == empresa_id,
        EquipoIntervenido.activo       == True,
        EquipoIntervenido.ubicacion_id == str(ps.ubicacion_id),
    ]
    if ps.zona_id:
        filtros.append(EquipoIntervenido.zona_id == str(ps.zona_id))

    equipos = db.query(EquipoIntervenido).filter(*filtros).all()

    now   = datetime.utcnow()
    count = 0
    for ei in equipos:
        old_ps_id = str(ei.proyecto_servicio_id) if ei.proyecto_servicio_id else None
        already_active = (
            ei.estado_intervencion == "en_proceso"
            and old_ps_id == ps_id
        )

        # Congelar el registro histórico anterior si el equipo cambia de servicio
        if old_ps_id and old_ps_id != ps_id:
            old_hm = db.query(HistorialMantenimiento).filter(
                HistorialMantenimiento.equipo_id   == str(ei.id),
                HistorialMantenimiento.servicio_id == old_ps_id,
            ).first()
            if old_hm and old_hm.estado not in ("completado", "cancelado"):
                old_hm.estado = ei.estado_intervencion or "pendiente"

        ei.proyecto_servicio_id = ps_id
        ei.proyecto_id          = proy_id
        if cliente_id:
            ei.cliente_id = cliente_id
        if not already_active:
            ei.estado_intervencion = "pendiente"
        ei.updated_at = now

        # Crear registro en historial_mantenimiento para este servicio
        existing_hm = db.query(HistorialMantenimiento).filter(
            HistorialMantenimiento.equipo_id   == str(ei.id),
            HistorialMantenimiento.servicio_id == ps_id,
        ).first()
        if not existing_hm:
            db.add(HistorialMantenimiento(
                id          = str(_uuid.uuid4()),
                empresa_id  = empresa_id,
                equipo_id   = str(ei.id),
                servicio_id = ps_id,
                estado      = "pendiente",
            ))

        count += 1

    return count


# ── POST /operaciones/proyecto/{proyecto_id}/servicios ────────────────────────

@router.post("/proyecto/{proyecto_id}/servicios", status_code=status.HTTP_201_CREATED)
def crear_servicio(
    proyecto_id: str,
    body:        CrearServicioBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Agrega un nuevo servicio a un proyecto existente."""
    exigir_no_tecnico(payload, "Técnico no puede crear servicios")
    empresa_id = payload["empresa_id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    # Verificar que el catálogo pertenece a la empresa
    catalogo = db.query(CatalogoServicio).filter(
        CatalogoServicio.id         == body.catalogo_servicio_id,
        CatalogoServicio.empresa_id == empresa_id,
    ).first()
    if not catalogo:
        raise HTTPException(status_code=404, detail="Catálogo de servicio no encontrado")

    # ── Líder del Servicio (OPCIONAL): si se omite, el Jefe de Operaciones que
    # tome el servicio quedará como líder al configurarlo. Si se envía, debe
    # ser un Jefe de Operaciones / Proyecto válido. ──
    lider_id = (body.lider_id or "").strip() or None
    if lider_id:
        lider = db.query(Empleado).filter(
            Empleado.id == lider_id, Empleado.empresa_id == empresa_id
        ).first()
        if not lider:
            raise HTTPException(status_code=404, detail="Líder del servicio no encontrado.")
        if not _empleado_es_lider_elegible(db, lider_id, empresa_id):
            raise HTTPException(
                status_code=422,
                detail="Solo un Jefe de Operaciones o Jefe de Proyecto puede ser Líder del Servicio.",
            )

    # ── Técnico Líder (opcional): cualquier empleado activo de la empresa ──
    responsable_id = (body.responsable_id or "").strip() or None
    if responsable_id:
        tecnico = db.query(Empleado).filter(
            Empleado.id == responsable_id, Empleado.empresa_id == empresa_id
        ).first()
        if not tecnico:
            raise HTTPException(status_code=404, detail="Técnico líder no encontrado.")

    tipo_doc, nro_doc = _normalizar_documento(body.tipo_documento_cliente, body.nro_documento)

    # Calcular el siguiente número de orden
    max_orden = (
        db.query(func.max(ProyectoServicio.orden))
        .filter(
            ProyectoServicio.proyecto_id == proyecto_id,
            ProyectoServicio.empresa_id  == empresa_id,
        )
        .scalar()
    ) or 0

    servicio_id = str(_uuid.uuid4())
    nuevo = ProyectoServicio(
        id                     = servicio_id,
        proyecto_id            = proyecto_id,
        empresa_id             = empresa_id,
        catalogo_servicio_id   = body.catalogo_servicio_id,
        nombre                 = body.nombre,
        descripcion            = body.descripcion or None,
        estado                 = body.estado or "Pendiente",
        orden                  = max_orden + 1,
        lider_id               = lider_id,
        responsable_id         = responsable_id,
        ubicacion_id               = body.ubicacion_id or None,
        zona_id                    = body.zona_id or None,
        zona_ejecucion             = body.zona_ejecucion or None,
        alcance                    = body.alcance or None,
        tipo_documento_cliente     = tipo_doc,
        nro_documento              = nro_doc,
        tiene_equipos_intervenidos = bool(body.tiene_equipos_intervenidos),
        fecha_programada           = _parse_date(body.fecha_programada),
        fecha_inicio           = _parse_date(body.fecha_inicio),
        fecha_fin              = _parse_date(body.fecha_fin),
        created_at             = datetime.utcnow(),
    )
    db.add(nuevo)
    db.flush()
    # Auto-vincular equipos de la ubicación/zona a este servicio.
    _vincular_equipos_al_servicio(db, nuevo, empresa_id, proyecto)
    db.commit()
    # Servicio sin líder = pendiente/disponible: avisar a todos los Jefes de
    # Operaciones para que puedan tomarlo (los servicios ya con líder solo los
    # ve su dueño, así que la notificación no aplica a ese caso).
    if lider_id is None:
        _notificar_servicio_pendiente_a_jefes(
            db, empresa_id, nuevo, exclude_usuario_id=payload.get("id"))
    # Replanteo 2026-07-08: los procedimientos viven en el tipo de EQUIPO
    # (checklist de inspección); ya no se instancian por tipo de servicio.
    # El flag queda en False para no romper a los clientes que lo leen.
    return {"ok": True, "id": servicio_id, "sin_procedimientos_estandar": False}


# ── PATCH /operaciones/servicio/{servicio_id} ─────────────────────────────────

@router.patch("/servicio/{servicio_id}")
def actualizar_servicio(
    servicio_id: str,
    body:        ActualizarServicioBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
    x_justificacion: str | None = Header(default=None, alias="X-Justificacion"),
):
    """Actualiza los metadatos de un servicio (nombre, catálogo, fechas, estado, descripción)."""
    exigir_no_tecnico(payload, "Técnico no puede editar servicios")
    empresa_id = payload["empresa_id"]
    if es_jefe_operaciones(payload):
        if not _jefe_op_asignado_al_servicio(db, payload, empresa_id, servicio_id):
            if not (x_justificacion or "").strip():
                raise HTTPException(
                    status_code=422,
                    detail="Se requiere justificación (X-Justificacion) para modificar un servicio que no tienes asignado",
                )
        if (x_justificacion or "").strip():
            set_justificacion(x_justificacion)

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    # Servicio terminado: solo se permite si el body cambia el estado (reapertura);
    # cualquier edición de metadatos sin cambio de estado queda bloqueada.
    if (ps.estado or "").strip().lower() in _ESTADOS_SERVICIO_TERMINADO and body.estado is None:
        raise HTTPException(status_code=409, detail="El servicio está terminado: solo lectura")

    # Verificar catálogo si cambió
    if body.catalogo_servicio_id and body.catalogo_servicio_id != str(ps.catalogo_servicio_id):
        catalogo = db.query(CatalogoServicio).filter(
            CatalogoServicio.id         == body.catalogo_servicio_id,
            CatalogoServicio.empresa_id == empresa_id,
        ).first()
        if not catalogo:
            raise HTTPException(status_code=404, detail="Catálogo de servicio no encontrado")
        ps.catalogo_servicio_id = body.catalogo_servicio_id

    if body.nombre is not None:
        ps.nombre = body.nombre
    if body.descripcion is not None:
        ps.descripcion = body.descripcion or None
    if body.estado is not None:
        ps.estado = body.estado
    if body.fecha_programada is not None:
        ps.fecha_programada = _parse_date(body.fecha_programada)
    if body.fecha_inicio is not None:
        ps.fecha_inicio = _parse_date(body.fecha_inicio)
    if body.fecha_fin is not None:
        ps.fecha_fin = _parse_date(body.fecha_fin)

    # Líder del Servicio (OPCIONAL): '' = quitar líder; si se envía uno, validar elegibilidad
    if body.lider_id is not None:
        lider_id = (body.lider_id or "").strip() or None
        if lider_id:
            lider = db.query(Empleado).filter(
                Empleado.id == lider_id, Empleado.empresa_id == empresa_id
            ).first()
            if not lider:
                raise HTTPException(status_code=404, detail="Líder del servicio no encontrado.")
            if not _empleado_es_lider_elegible(db, lider_id, empresa_id):
                raise HTTPException(
                    status_code=422,
                    detail="Solo un Jefe de Operaciones o Jefe de Proyecto puede ser Líder del Servicio.",
                )
        ps.lider_id = lider_id

    # Técnico Líder (opcional)
    _resp_anterior = ps.responsable_id
    _resp_nuevo = None
    if body.responsable_id is not None:
        responsable_id = (body.responsable_id or "").strip() or None
        if responsable_id:
            tecnico = db.query(Empleado).filter(
                Empleado.id == responsable_id, Empleado.empresa_id == empresa_id
            ).first()
            if not tecnico:
                raise HTTPException(status_code=404, detail="Técnico líder no encontrado.")
        ps.responsable_id = responsable_id
        # Notificar solo si cambia y se asigna a alguien (no al desasignar).
        if responsable_id and str(responsable_id) != str(_resp_anterior or ""):
            _resp_nuevo = responsable_id

    # Detectar si cambian campos que afectan la vinculación de equipos
    _relink_trigger = any([
        body.tiene_equipos_intervenidos is not None,
        body.ubicacion_id               is not None,
        body.zona_id                    is not None,
    ])

    if body.ubicacion_id is not None:
        ps.ubicacion_id = body.ubicacion_id or None
    if body.zona_id is not None:
        ps.zona_id = body.zona_id or None
    if body.zona_ejecucion is not None:
        ps.zona_ejecucion = body.zona_ejecucion or None
    if body.alcance is not None:
        ps.alcance = body.alcance or None
    if body.tiene_equipos_intervenidos is not None:
        ps.tiene_equipos_intervenidos = bool(body.tiene_equipos_intervenidos)
    if body.tipo_documento_cliente is not None:
        tipo_doc, nro_doc = _normalizar_documento(body.tipo_documento_cliente, body.nro_documento)
        ps.tipo_documento_cliente = tipo_doc
        ps.nro_documento = nro_doc
    elif body.nro_documento is not None:
        _, nro_doc = _normalizar_documento(ps.tipo_documento_cliente, body.nro_documento)
        ps.nro_documento = nro_doc

    ps.updated_at = datetime.utcnow()

    # Re-vincular equipos si cambió ubicacion, zona o flag de equipos intervenidos
    if _relink_trigger:
        _proyecto_upd = db.query(Proyecto).filter(Proyecto.id == ps.proyecto_id).first()
        if _proyecto_upd:
            _vincular_equipos_al_servicio(db, ps, empresa_id, _proyecto_upd)

    db.commit()

    # Avisar al técnico recién asignado como responsable del servicio.
    if _resp_nuevo:
        try:
            from ..services.fcm_service import notificar_usuario
            emp = db.query(Empleado.usuario_id).filter(Empleado.id == _resp_nuevo).first()
            if emp and emp.usuario_id:
                notificar_usuario(
                    db, empresa_id=empresa_id, usuario_id=emp.usuario_id,
                    titulo="Te asignaron un servicio",
                    mensaje=f"Eres el responsable del servicio '{ps.nombre or 'servicio'}'.",
                    tipo="servicio", categoria="servicio",
                    referencia_id=str(ps.id), referencia_tabla="proyecto_servicio",
                )
                db.commit()
        except Exception:
            db.rollback()

    return {"ok": True}


# ── POST /operaciones/servicio/{servicio_id}/configurar ───────────────────────

@router.post("/servicio/{servicio_id}/configurar")
def configurar_servicio(
    servicio_id: str,
    body:        ConfigurarServicioBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
    x_justificacion: str | None = Header(default=None, alias="X-Justificacion"),
):
    """
    Configura un servicio:
    - Asigna / actualiza el equipo técnico (ProyectoMiembro).
    - Reemplaza el cronograma de Tareas (responsable + fechas). El body llega
      como `procedimientos` por compatibilidad con el frontend Angular.
    """
    exigir_no_tecnico(payload, "Técnico no puede configurar servicios ni asignar miembros")
    empresa_id = payload["empresa_id"]
    # Jefe de Operaciones: si está asignado al proyecto/servicio, gestiona libre;
    # solo se exige justificación cuando configura un proyecto que NO es suyo.
    if es_jefe_operaciones(payload):
        if not _jefe_op_asignado_al_servicio(db, payload, empresa_id, servicio_id):
            if not (x_justificacion or "").strip():
                raise HTTPException(
                    status_code=422,
                    detail="Se requiere justificación (X-Justificacion) para configurar un servicio que no tienes asignado",
                )
        if (x_justificacion or "").strip():
            set_justificacion(x_justificacion)

    ps = _exigir_servicio_abierto(db, empresa_id, servicio_id)

    proyecto_id = ps.proyecto_id

    # ── 1. Equipo técnico ─────────────────────────────────────────────────────
    equipo_ids = list(set(body.equipo))  # deduplicar

    # Validar que todos los empleados existen y pertenecen a la empresa
    if equipo_ids:
        count = db.query(func.count(Empleado.id)).filter(
            Empleado.id.in_(equipo_ids),
            Empleado.empresa_id == empresa_id,
        ).scalar()
        if count != len(equipo_ids):
            raise HTTPException(
                status_code=422,
                detail="Uno o más empleados no existen o no pertenecen a esta empresa.",
            )

    # Desactivar miembros que ya no están en la lista (excepto el jefe de operaciones)
    proyecto = db.query(Proyecto).filter(Proyecto.id == proyecto_id).first()
    jefe_id  = proyecto.jefe_operaciones_id if proyecto else None

    (
        db.query(ProyectoMiembro)
        .filter(
            ProyectoMiembro.proyecto_id == proyecto_id,
            ProyectoMiembro.empleado_id.notin_(equipo_ids) if equipo_ids else True,
            ProyectoMiembro.empleado_id != jefe_id,  # nunca desactivar al jefe
        )
        .update({"activo": False}, synchronize_session=False)
    )

    # Insertar / reactivar miembros nuevos
    for emp_id in equipo_ids:
        existing = db.query(ProyectoMiembro).filter(
            ProyectoMiembro.proyecto_id == proyecto_id,
            ProyectoMiembro.empleado_id == emp_id,
        ).first()
        if existing:
            existing.activo = True
        else:
            db.add(ProyectoMiembro(
                id               = str(_uuid.uuid4()),
                proyecto_id      = proyecto_id,
                empleado_id      = emp_id,
                rol_proyecto     = "Técnico",
                fecha_asignacion = date.today(),
                activo           = True,
            ))

    db.flush()

    # ── 2. Tareas / Cronograma ────────────────────────────────────────────────
    # (El body llega como `procedimientos` por compat con Angular, pero esto es
    # el cronograma → se persiste en la tabla `tarea`.)
    # Eliminar tareas existentes del servicio y recrearlas.
    db.query(Tarea).filter(
        Tarea.proyecto_servicio_id == servicio_id
    ).delete(synchronize_session=False)

    for i, proc in enumerate(body.procedimientos, start=1):
        # Verificar que el responsable está en el equipo o es el jefe
        if proc.responsable_id not in equipo_ids and proc.responsable_id != (jefe_id or ""):
            # Permisivo: si no está en la lista exacta, lo aceptamos de todas formas
            # (puede ser el jefe que no figura en equipo_ids)
            pass

        db.add(Tarea(
            id                   = str(_uuid.uuid4()),
            proyecto_servicio_id = servicio_id,
            empresa_id           = empresa_id,
            responsable_id       = proc.responsable_id or None,
            nombre               = proc.nombre[:200],
            orden                = i,
            estado               = "pendiente",
            fecha_inicio_tarea   = _parse_date(proc.fecha_inicio),
            fecha_limite         = _parse_date(proc.fecha_fin),
            created_at           = datetime.utcnow(),
        ))

    # ── 3. Auto-liderazgo (HU-13) ─────────────────────────────────────────────
    # Determinar el LÍDER DEL SERVICIO (ps.lider_id — nunca el técnico líder):
    #   a) Usar body.lider_id si el frontend lo envía explícitamente, O
    #   b) Si el servicio aún no tiene líder, el Jefe de Operaciones que lo está
    #      configurando (JWT) lo reclama automáticamente.
    # Si el líder fue definido al CREAR el servicio, se respeta salvo override
    # explícito (escenarios A y B coexisten).
    lider_empleado_id: str | None = str(ps.lider_id) if ps.lider_id else None

    if body.lider_id:
        # Override explícito: verificar que pertenece a la empresa
        emp_lider = db.query(Empleado).filter(
            Empleado.id         == body.lider_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if emp_lider:
            lider_empleado_id = str(emp_lider.id)
    elif not lider_empleado_id:
        # Reclamo automático: el empleado del usuario autenticado toma el liderazgo
        usuario_id = payload.get("id", "")
        emp_lider = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
            Empleado.activo     == True,
        ).first()
        if emp_lider:
            lider_empleado_id = str(emp_lider.id)

    if lider_empleado_id:
        # Asignar como LÍDER del servicio (el técnico líder es independiente)
        ps.lider_id = lider_empleado_id
        # Asignar como jefe de operaciones del proyecto si no tenía uno
        if proyecto and not proyecto.jefe_operaciones_id:
            proyecto.jefe_operaciones_id = lider_empleado_id

    # ── 3b. Técnico Líder (OPCIONAL): '' = quitar; None = no tocar ────────────
    if body.responsable_id is not None:
        responsable_id = (body.responsable_id or "").strip() or None
        if responsable_id:
            tecnico = db.query(Empleado).filter(
                Empleado.id         == responsable_id,
                Empleado.empresa_id == empresa_id,
            ).first()
            if not tecnico:
                raise HTTPException(status_code=404, detail="Técnico líder no encontrado.")
        ps.responsable_id = responsable_id

    # Si el servicio estaba en Pendiente y se le asigna equipo, pasarlo a En_Proceso
    if ps.estado == "Pendiente" and equipo_ids:
        ps.estado = "En_Proceso"

    ps.updated_at = datetime.utcnow()
    db.commit()

    return {
        "ok":              True,
        "miembros_equipo": len(equipo_ids),
        "procedimientos":  len(body.procedimientos),
        "estado_servicio": ps.estado,
        "lider_id":        lider_empleado_id,
    }


# ── POST /operaciones/servicio/{servicio_id}/nota ─────────────────────────────

@router.post("/servicio/{servicio_id}/nota", status_code=status.HTTP_201_CREATED)
def agregar_nota_servicio(
    servicio_id: str,
    body:        AgregarNotaBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Agrega una nota/seguimiento al proyecto del servicio."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    ps = _assert_servicio_abierto(servicio_id, db, empresa_id)

    registrador = _get_jefe_empleado(db, usuario_id, empresa_id)
    if not registrador:
        raise HTTPException(
            status_code=422,
            detail="No hay empleados registrados en la empresa.",
        )

    # Calcular el progreso actual del servicio (solo procedimientos generales;
    # las copias por equipo se instancian tarde y distorsionarían el %).
    total_procs  = db.query(func.count(Procedimiento.id)).filter(
        Procedimiento.proyecto_servicio_id  == servicio_id,
        Procedimiento.equipo_intervenido_id.is_(None),
    ).scalar() or 0
    completos    = db.query(func.count(Procedimiento.id)).filter(
        Procedimiento.proyecto_servicio_id  == servicio_id,
        Procedimiento.equipo_intervenido_id.is_(None),
        Procedimiento.estado                == "completado",
    ).scalar() or 0
    pct = round(completos / total_procs * 100, 2) if total_procs else 0.0

    nota = SeguimientoProyecto(
        id                   = str(_uuid.uuid4()),
        proyecto_id          = ps.proyecto_id,
        proyecto_servicio_id = servicio_id,
        empresa_id           = empresa_id,
        porcentaje_avance    = pct,
        descripcion          = body.descripcion,
        fecha                = date.today(),
        registrado_por       = registrador.id,
        created_at           = datetime.utcnow(),
    )
    db.add(nota)
    db.commit()

    return {"ok": True, "nota_id": nota.id}


# ── Helpers de Notas ──────────────────────────────────────────────────────────

def _nota_autor_nombre(db: Session, registrado_por) -> tuple[str, str | None]:
    """Devuelve (nombre_completo, empleado_id) del autor de una nota."""
    if not registrado_por:
        return ("Sistema", None)
    row = (
        db.query(Empleado.id, Usuario.nombre, Usuario.apellido)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.id == registrado_por)
        .first()
    )
    if not row:
        return ("Usuario", str(registrado_por))
    nombre = f"{row.nombre or ''} {row.apellido or ''}".strip() or "Usuario"
    return (nombre, str(row.id))


def _puede_gestionar_nota(db: Session, nota: SeguimientoProyecto, payload: dict) -> bool:
    """El autor, un admin/superadmin o el jefe del proyecto pueden editar/eliminar."""
    if es_superadmin(payload):
        return True
    emp = _get_empleado_optional(db, payload["id"], payload["empresa_id"])
    if not emp:
        return False
    if str(nota.registrado_por) == str(emp.id):
        return True
    proyecto = db.query(Proyecto).filter(Proyecto.id == nota.proyecto_id).first()
    return bool(proyecto and str(proyecto.jefe_operaciones_id) == str(emp.id))


# ── GET /operaciones/servicio/{servicio_id}/notas ─────────────────────────────

@router.get("/servicio/{servicio_id}/notas", response_model=List[NotaOut])
def listar_notas_servicio(
    servicio_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Lista las notas/observaciones de un servicio (más recientes primero)."""
    empresa_id = payload["empresa_id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    notas = (
        db.query(SeguimientoProyecto)
        .filter(
            SeguimientoProyecto.proyecto_servicio_id == servicio_id,
            SeguimientoProyecto.empresa_id           == empresa_id,
        )
        .order_by(SeguimientoProyecto.created_at.desc())
        .all()
    )

    salida: list[NotaOut] = []
    for n in notas:
        autor, autor_id = _nota_autor_nombre(db, n.registrado_por)
        try:
            fecha_str = fmt_lima(n.created_at) or "—"
        except Exception:
            fecha_str = "—"
        salida.append(NotaOut(
            id=str(n.id),
            descripcion=n.descripcion or "",
            autor=autor,
            autor_id=autor_id,
            fecha=fecha_str,
            puede_editar=_puede_gestionar_nota(db, n, payload),
        ))
    return salida


# ── PUT /operaciones/nota/{nota_id} ───────────────────────────────────────────

@router.put("/nota/{nota_id}")
def actualizar_nota(
    nota_id: str,
    body:    ActualizarNotaBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Edita el texto de una nota. Solo autor / jefe / admin."""
    empresa_id = payload["empresa_id"]
    nota = db.query(SeguimientoProyecto).filter(
        SeguimientoProyecto.id         == nota_id,
        SeguimientoProyecto.empresa_id == empresa_id,
    ).first()
    if not nota:
        raise HTTPException(status_code=404, detail="Nota no encontrada")
    if not _puede_gestionar_nota(db, nota, payload):
        raise HTTPException(status_code=403, detail="No puedes editar esta nota")

    if nota.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(nota.proyecto_servicio_id))

    texto = (body.descripcion or "").strip()
    if not texto:
        raise HTTPException(status_code=422, detail="La nota no puede estar vacía")

    nota.descripcion = texto
    db.commit()
    return {"ok": True, "id": str(nota.id)}


# ── DELETE /operaciones/nota/{nota_id} ────────────────────────────────────────

@router.delete("/nota/{nota_id}")
def eliminar_nota(
    nota_id: str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Elimina una nota. Solo autor / jefe / admin."""
    empresa_id = payload["empresa_id"]
    nota = db.query(SeguimientoProyecto).filter(
        SeguimientoProyecto.id         == nota_id,
        SeguimientoProyecto.empresa_id == empresa_id,
    ).first()
    if not nota:
        raise HTTPException(status_code=404, detail="Nota no encontrada")
    if not _puede_gestionar_nota(db, nota, payload):
        raise HTTPException(status_code=403, detail="No puedes eliminar esta nota")

    if nota.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(nota.proyecto_servicio_id))

    db.delete(nota)
    db.commit()
    return {"ok": True}


# ════════════════════════════════════════════════════════════════════════════
# MOTOR DE INSPECCIÓN — Equipos Intervenidos + Historial
# ════════════════════════════════════════════════════════════════════════════

def _map_ei(ei: EquipoIntervenido, tipo_nombre: str | None) -> dict:
    """Serializa un registro equipo_intervenido (activo de cliente) para el frontend."""
    return {
        "id":                  str(ei.id),
        "nombre":              ei.nombre or "",
        "codigo":              ei.codigo or None,
        "tipo_nombre":         tipo_nombre or None,
        "tipo_equipo_id":      str(ei.tipo_equipo_id) if ei.tipo_equipo_id else None,
        "marca":               ei.marca or None,
        "modelo":              ei.modelo or None,
        "numero_serie":        ei.numero_serie or None,
        "estado_intervencion": ei.estado_intervencion or "pendiente",
        "estado":              ei.estado or "operativo",
        "observaciones":       ei.observaciones or None,
    }


def _get_plantilla_jsonb(tipo: "TipoEquipo | None") -> list[dict]:
    """Lee procedimientos_template (JSONB) del tipo de equipo.
    Devuelve lista vacía si el tipo no existe o no tiene plantilla cargada."""
    if tipo is None:
        return []
    jsonb = getattr(tipo, "procedimientos_template", None)
    if jsonb and isinstance(jsonb, list):
        return sorted(jsonb, key=lambda x: x.get("orden", 0))
    return []


def _resultado_inicial(plantilla: list[dict]) -> list[dict]:
    """Crea el resultado vacío para una nueva sesión."""
    return [
        {
            "orden":         item.get("orden"),
            "nombre":        item.get("nombre", ""),
            "descripcion":   item.get("descripcion", ""),
            "completado":    False,
            "foto_url":      None,
            "foto_public_id": None,
        }
        for item in plantilla
    ]


def _map_hi(hi: HistorialInspeccion) -> dict:
    return {
        "id":                           str(hi.id),
        "estado":                       hi.estado,
        "resultado":                    hi.resultado or [],
        "observaciones":                hi.observaciones or None,
        "proxima_fecha_mantenimiento":  hi.proxima_fecha_mantenimiento.isoformat() if hi.proxima_fecha_mantenimiento else None,
        "fecha_inicio":                 hi.fecha_inicio.isoformat() if hi.fecha_inicio else None,
        "fecha_fin":                    hi.fecha_fin.isoformat() if hi.fecha_fin else None,
        "inspeccion_padre_id":          str(hi.inspeccion_padre_id) if hi.inspeccion_padre_id else None,
    }


def _resumen_vinculo(db: Session, hi: "HistorialInspeccion | None") -> "dict | None":
    """Resumen ligero de una inspección para mostrar el vínculo en la app."""
    if hi is None:
        return None
    serv_nombre = None
    if hi.proyecto_servicio_id:
        _ps = db.query(ProyectoServicio).filter(
            ProyectoServicio.id == str(hi.proyecto_servicio_id)
        ).first()
        if _ps:
            serv_nombre = _ps.nombre
    return {
        "id":              str(hi.id),
        "estado":          hi.estado,
        "fecha_fin":       hi.fecha_fin.isoformat() if hi.fecha_fin else None,
        "servicio_nombre": serv_nombre,
    }


def _ultima_inspeccion_previa(
    db: Session, empresa_id: str, ei_id: str, excluir_id: str,
) -> "HistorialInspeccion | None":
    """Última inspección COMPLETADA del mismo equipo (candidata a 'anterior')."""
    return (
        db.query(HistorialInspeccion)
        .filter(
            HistorialInspeccion.equipo_intervenido_id == ei_id,
            HistorialInspeccion.empresa_id            == empresa_id,
            HistorialInspeccion.estado                == "completado",
            HistorialInspeccion.id                    != excluir_id,
        )
        .order_by(HistorialInspeccion.fecha_fin.desc())
        .first()
    )


# ── GET /servicio/{id}/equipos-intervenidos ───────────────────────────────────
# Devuelve los activos de la empresa filtrados por la ubicacion/zona del servicio.
# Si el servicio no tiene zona, muestra todos los de la ubicacion.
# Si tampoco tiene ubicacion, muestra todos los de la empresa.

@router.get("/servicio/{servicio_id}/equipos-intervenidos")
def list_equipos_intervenidos(
    servicio_id: str,
    ubicacion_id: Optional[str] = Query(None),
    zona_id:      Optional[str] = Query(None),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    # Obtener el servicio para validar acceso y obtener su ubicacion/zona
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    # Prioridad: query params (override desde el app) → campos del servicio
    filtro_ubicacion_id = ubicacion_id or (str(ps.ubicacion_id) if ps.ubicacion_id else None)
    filtro_zona_id      = zona_id      or (str(ps.zona_id)      if ps.zona_id      else None)

    # Subquery: última inspección de cada equipo en este servicio
    historial_sq = (
        db.query(
            HistorialInspeccion.equipo_intervenido_id,
            func.max(HistorialInspeccion.created_at).label("ultima"),
        )
        .filter(HistorialInspeccion.proyecto_servicio_id == servicio_id)
        .group_by(HistorialInspeccion.equipo_intervenido_id)
        .subquery()
    )

    q = (
        db.query(
            EquipoIntervenido,
            TipoEquipo.nombre.label("tipo_nombre"),
            Ubicacion.nombre.label("ubicacion_nombre"),
            Zona.nombre.label("zona_nombre"),
            HistorialInspeccion.estado.label("estado_inspeccion"),
        )
        .outerjoin(TipoEquipo,  TipoEquipo.id  == EquipoIntervenido.tipo_equipo_id)
        .outerjoin(Ubicacion,   cast(Ubicacion.id, SAText)  == cast(EquipoIntervenido.ubicacion_id, SAText))
        .outerjoin(Zona,        cast(Zona.id,      SAText)  == cast(EquipoIntervenido.zona_id,     SAText))
        .outerjoin(historial_sq, historial_sq.c.equipo_intervenido_id == EquipoIntervenido.id)
        .outerjoin(
            HistorialInspeccion,
            (HistorialInspeccion.equipo_intervenido_id == EquipoIntervenido.id) &
            (HistorialInspeccion.created_at            == historial_sq.c.ultima),
        )
        .filter(
            EquipoIntervenido.empresa_id == empresa_id,
            EquipoIntervenido.activo     == True,
        )
    )

    # Filtro geográfico inteligente:
    # 1. Zona exacta → 2. Fallback a ubicación → 3. Sin criterio: lista vacía
    # (ya no se devuelven todos los equipos de la empresa cuando no hay filtro)
    orden = (TipoEquipo.nombre.asc(), EquipoIntervenido.nombre.asc())

    rows = []
    if filtro_zona_id:
        rows = q.filter(EquipoIntervenido.zona_id == filtro_zona_id).order_by(*orden).all()
    if not rows and filtro_ubicacion_id:
        rows = q.filter(EquipoIntervenido.ubicacion_id == filtro_ubicacion_id).order_by(*orden).all()
    # Si no hay ningún criterio geográfico no devolvemos todos: lista vacía con mensaje claro.

    # Garantizar que SIEMPRE aparezcan los equipos del SERVICIO ACTUAL
    # (proyecto_servicio_id == servicio_id), aunque el filtro por zona exacta los
    # dejara fuera. Es el caso más común: entrar a inspeccionar/marcar lo que se
    # está interviniendo ahora, esté terminado o no.
    presentes = {str(ei.id) for ei, *_ in rows}
    delServicio = (
        q.filter(EquipoIntervenido.proyecto_servicio_id == servicio_id)
        .order_by(*orden)
        .all()
    )
    for tup in delServicio:
        if str(tup[0].id) not in presentes:
            rows.append(tup)
            presentes.add(str(tup[0].id))

    return [
        {
            "id":                    str(ei.id),
            "nombre":                ei.nombre or "",
            "codigo":                ei.codigo or None,
            "ubicacion_referencia":  ei.ubicacion_referencia or None,
            "tipo_nombre":           tipo_nombre or None,
            "tipo_equipo_id":        str(ei.tipo_equipo_id) if ei.tipo_equipo_id else None,
            "marca":                 ei.marca or None,
            "modelo":                ei.modelo or None,
            "numero_serie":          ei.numero_serie or None,
            "estado":                ei.estado or "operativo",
            "ubicacion":             ubicacion_nombre or None,
            "zona":                  zona_nombre or None,
            "ultimo_mantenimiento":  ei.ultimo_mantenimiento.isoformat() if ei.ultimo_mantenimiento else None,
            "proximo_mantenimiento": ei.proximo_mantenimiento.isoformat() if ei.proximo_mantenimiento else None,
            "estado_intervencion":   estado_inspeccion or "sin_inspeccion",
            "observaciones":         ei.observaciones or None,
            # True si el equipo está atado al servicio que se está viendo
            # (se interviene ahora aquí) vs. solo pertenece a la misma sede.
            "del_servicio_actual":   str(ei.proyecto_servicio_id or "") == servicio_id,
        }
        for ei, tipo_nombre, ubicacion_nombre, zona_nombre, estado_inspeccion in rows
    ]


# ── POST /servicio/{id}/equipos-intervenidos ──────────────────────────────────
# Crea un NUEVO activo en el catálogo de la empresa.

@router.post("/servicio/{servicio_id}/equipos-intervenidos", status_code=status.HTTP_201_CREATED)
def crear_equipo_catalogo(
    servicio_id: str,
    body: dict,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    nombre     = (body or {}).get("nombre", "").strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="nombre requerido")

    # El tipo es obligatorio: define la plantilla de procedimientos del
    # mantenimiento. Sin tipo la inspección saldría con checklist vacío.
    tipo_id  = (body or {}).get("tipo_equipo_id")
    if not tipo_id:
        raise HTTPException(status_code=422, detail="tipo_equipo_id requerido")
    ubic_id  = (body or {}).get("ubicacion_id")
    zona_id  = (body or {}).get("zona_id")
    desc     = (body or {}).get("descripcion") or None
    cliente_id = (body or {}).get("cliente_id") or None
    # Campos libres del formulario (independientes de ubicacion/zona)
    marca        = (body or {}).get("marca") or None
    modelo       = (body or {}).get("modelo") or None
    numero_serie = (body or {}).get("numero_serie") or None
    estado_in    = (body or {}).get("estado") or "operativo"
    # "Referencia" = SOLO indicaciones fisicas de donde esta el equipo.
    # Ya no se arma con "ubicacion / zona": esos viven en sus propias columnas.
    referencia   = ((body or {}).get("ubicacion_referencia") or "").strip() or None
    # Proximo mantenimiento (ISO YYYY-MM-DD) opcional
    prox_mtto = None
    _prox_raw = (body or {}).get("proximo_mantenimiento")
    if _prox_raw:
        try:
            prox_mtto = date.fromisoformat(str(_prox_raw)[:10])
        except ValueError:
            prox_mtto = None
    # Frecuencia del ciclo preventivo en meses (opcional, default 6)
    try:
        frec_meses = int((body or {}).get("frecuencia_meses") or 6)
    except (TypeError, ValueError):
        frec_meses = 6
    frec_meses = min(max(frec_meses, 1), 60)

    # Heredar ubicacion/zona/cliente del servicio si no vienen en el body.
    # Asi el equipo nuevo queda ligado a la misma ubicacion+zona del servicio.
    ps = _assert_servicio_abierto(servicio_id, db, empresa_id)
    ubic_id    = ubic_id    or (str(ps.ubicacion_id) if ps.ubicacion_id else None)
    zona_id    = zona_id    or (str(ps.zona_id)      if ps.zona_id      else None)
    cliente_id = cliente_id or (str(ps.cliente_id)   if getattr(ps, "cliente_id", None) else None)

    # Anti-duplicado: no recrear un equipo ya existente en la misma ubicacion+zona+tipo.
    dup = (
        db.query(EquipoIntervenido)
        .filter(
            EquipoIntervenido.empresa_id == empresa_id,
            EquipoIntervenido.activo == True,
            func.lower(func.trim(EquipoIntervenido.nombre)) == nombre.lower(),
            EquipoIntervenido.ubicacion_id == ubic_id if ubic_id else EquipoIntervenido.ubicacion_id.is_(None),
            EquipoIntervenido.zona_id == zona_id if zona_id else EquipoIntervenido.zona_id.is_(None),
        )
        .first()
    )
    if dup and (not tipo_id or str(dup.tipo_equipo_id) == str(tipo_id)):
        raise HTTPException(
            status_code=409,
            detail=f"Ya existe '{dup.nombre}' (codigo {dup.codigo}) en esta ubicacion y zona. "
                   f"Registra el mantenimiento sobre el equipo existente.",
        )

    tipo = db.query(TipoEquipo).filter(
        TipoEquipo.id == tipo_id,
        TipoEquipo.empresa_id == empresa_id,
    ).first()
    if not tipo:
        raise HTTPException(status_code=404, detail="Tipo de equipo no encontrado")

    # Codigo unico {PROV}-{TIPO}-{NNN}. El prefijo PROV se deriva de la ubicacion,
    # pero NO se mezcla con "Referencia": la ubicacion y la zona viven en sus
    # propias FKs (ubicacion_id / zona_id) y se muestran en columnas separadas.
    prov3 = "GEN"
    if ubic_id:
        u = db.query(Ubicacion).filter(Ubicacion.id == ubic_id).first()
        if u and u.nombre:
            prov3 = "".join(ch for ch in u.nombre.upper() if ch.isalnum())[:3] or "GEN"
    _PREF = {"POZOS": "POZ", "POZO A TIERRA": "POZ", "TABLEROS": "TAB", "TABLERO ELECTRICO": "TAB",
             "UPS": "UPS", "TRANS. AISLAMIENTO": "TRA", "PARARRAYOS": "PAR",
             "LUMINARIAS": "LUM", "TOMACORRIENTES": "TOM"}
    tname = (tipo.nombre.strip().upper() if tipo and tipo.nombre else "")
    t3 = _PREF.get(tname, (tname[:3] or "EQ"))
    pref = f"{prov3}-{t3}-"
    maxn = 0
    for (cod,) in db.query(EquipoIntervenido.codigo).filter(
            EquipoIntervenido.empresa_id == empresa_id,
            EquipoIntervenido.codigo.like(f"{pref}%")).all():
        try:
            maxn = max(maxn, int((cod or "").rsplit("-", 1)[-1]))
        except (ValueError, IndexError):
            continue
    codigo = f"{pref}{maxn + 1:03d}"

    proyecto_id_new = str(ps.proyecto_id) if ps and ps.proyecto_id else None

    nid = str(_uuid.uuid4())
    ei  = EquipoIntervenido(
        id                   = nid,
        empresa_id           = empresa_id,
        cliente_id           = cliente_id,
        proyecto_id          = proyecto_id_new,
        proyecto_servicio_id = servicio_id,
        nombre               = nombre,
        codigo               = codigo,
        ubicacion_referencia = referencia,
        tipo_equipo_id       = tipo_id or None,
        ubicacion_id         = ubic_id or None,
        zona_id              = zona_id or None,
        marca                = marca,
        modelo               = modelo,
        numero_serie         = numero_serie,
        proximo_mantenimiento = prox_mtto,
        frecuencia_meses     = frec_meses,
        observaciones        = desc,
        estado               = estado_in,
        activo               = True,
    )
    db.add(ei)
    db.commit()

    return {
        "id":           nid,
        "nombre":       nombre,
        "codigo":       codigo,
        "ubicacion_referencia": referencia,
        "tipo_nombre":  tipo.nombre if tipo else None,
        "estado_intervencion": "sin_inspeccion",
    }


def _equipo_info_dict(db: Session, ei, tipo=None) -> dict:
    """Datos del equipo intervenido para la vista de inspeccion.
    Reemplaza marca/modelo/serie (vacios en la data) por campos utiles:
    ubicacion, cliente, descripcion e historial de mantenimiento."""
    if tipo is None and ei.tipo_equipo_id:
        tipo = db.query(TipoEquipo).filter(TipoEquipo.id == ei.tipo_equipo_id).first()
    cliente = db.query(Cliente).filter(Cliente.id == ei.cliente_id).first() if ei.cliente_id else None

    ubic_ref = ei.ubicacion_referencia
    if not ubic_ref and ei.ubicacion_id:
        u = db.query(Ubicacion).filter(Ubicacion.id == ei.ubicacion_id).first()
        z = db.query(Zona).filter(Zona.id == ei.zona_id).first() if ei.zona_id else None
        if u:
            ubic_ref = f"{u.nombre} / {z.nombre}" if z else u.nombre

    ficha = ei.ficha_tecnica if isinstance(ei.ficha_tecnica, dict) else {}
    return {
        "id":           str(ei.id),
        "nombre":       ei.nombre or "",
        "codigo":       ei.codigo or None,
        "tipo_nombre":  tipo.nombre if tipo else None,
        "ubicacion_referencia": ubic_ref or None,
        "cliente_nombre": cliente.razon_social if cliente else None,
        "descripcion":  ei.observaciones or None,
        "n_mantenimientos": ficha.get("n_mantenimientos"),
        "ultimo_mantenimiento":  ei.ultimo_mantenimiento.isoformat() if ei.ultimo_mantenimiento else None,
        "proximo_mantenimiento": ei.proximo_mantenimiento.isoformat() if ei.proximo_mantenimiento else None,
        "estado":       ei.estado or "operativo",
        "estado_intervencion": ei.estado_intervencion or "en_proceso",
    }


# ── GET /servicio/{id}/equipos-intervenidos/{eiId}/detalle ────────────────────

@router.get("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/detalle")
def detalle_equipo_intervenido(
    servicio_id: str,
    ei_id:       str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id         == ei_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not ei:
        raise HTTPException(status_code=404, detail="EquipoIntervenido no encontrado")

    tipo = db.query(TipoEquipo).filter(TipoEquipo.id == ei.tipo_equipo_id).first()
    cliente = db.query(Cliente).filter(Cliente.id == ei.cliente_id).first() if ei.cliente_id else None

    # Referencia de ubicacion: usa la columna; si no, la arma desde ubicacion/zona
    ubic_ref = ei.ubicacion_referencia
    if not ubic_ref and ei.ubicacion_id:
        u = db.query(Ubicacion).filter(Ubicacion.id == ei.ubicacion_id).first()
        z = db.query(Zona).filter(Zona.id == ei.zona_id).first() if ei.zona_id else None
        if u:
            ubic_ref = f"{u.nombre} / {z.nombre}" if z else u.nombre

    ficha = ei.ficha_tecnica or {}
    n_mtto = ficha.get("n_mantenimientos") if isinstance(ficha, dict) else None

    return {
        "id":           str(ei.id),
        "nombre":       ei.nombre or "",
        "codigo":       ei.codigo or None,
        "tipo_nombre":  tipo.nombre if tipo else None,
        "ubicacion_referencia": ubic_ref or None,
        "cliente_nombre": cliente.razon_social if cliente else None,
        "descripcion":  ei.observaciones or None,
        "n_mantenimientos": n_mtto,
        "ultimo_mantenimiento":  ei.ultimo_mantenimiento.isoformat() if ei.ultimo_mantenimiento else None,
        "proximo_mantenimiento": ei.proximo_mantenimiento.isoformat() if ei.proximo_mantenimiento else None,
        "estado":       ei.estado or "operativo",
        "observaciones": ei.observaciones or None,
    }


# ── GET /servicio/{sid}/equipos-intervenidos/{eiId}/inspeccion ────────────────
# Devuelve la sesión activa (en_proceso). Si no hay ninguna, crea una nueva
# con los procedimientos de la plantilla del tipo de equipo.

@router.get("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/inspeccion")
def get_inspeccion_activa(
    servicio_id: str,
    ei_id:       str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id         == ei_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not ei:
        raise HTTPException(status_code=404, detail="EquipoIntervenido no encontrado")

    # Desde el arranque en limpio (2026-07) todo equipo se crea con tipo
    # obligatorio; ya no se infiere por nombre (muleta de la data legacy).
    tipo = db.query(TipoEquipo).filter(TipoEquipo.id == ei.tipo_equipo_id).first() if ei.tipo_equipo_id else None

    plantilla = _get_plantilla_jsonb(tipo)

    # ── Si el equipo está completado PARA ESTE servicio, devolver read-only ──
    # Si fue completado bajo un servicio anterior, `_vincular_equipos_al_servicio`
    # ya habrá reseteado estado_intervencion='pendiente', así que no llegamos aquí.
    if ei.estado_intervencion == "completado" and str(ei.proyecto_servicio_id or "") == servicio_id:
        hi = (
            db.query(HistorialInspeccion)
            .filter(
                HistorialInspeccion.equipo_intervenido_id == ei_id,
                HistorialInspeccion.proyecto_servicio_id  == servicio_id,
            )
            .order_by(HistorialInspeccion.created_at.desc())
            .first()
        )
        resultado = sorted(hi.resultado or [], key=lambda x: x["orden"]) if hi else []
        return {
            "inspeccion_id": str(hi.id) if hi else "",
            "estado":        "completado",
            "resultado":     resultado,
            "observaciones": hi.observaciones or None if hi else None,
            "proxima_fecha": hi.proxima_fecha_mantenimiento.isoformat() if hi and hi.proxima_fecha_mantenimiento else None,
            "equipo":        _equipo_info_dict(db, ei, tipo),
            "inspeccion_padre_id": str(hi.inspeccion_padre_id) if hi and hi.inspeccion_padre_id else None,
            "padre": _resumen_vinculo(
                db,
                db.query(HistorialInspeccion).filter(
                    HistorialInspeccion.id == str(hi.inspeccion_padre_id)
                ).first(),
            ) if hi and hi.inspeccion_padre_id else None,
            "intervencion_anterior": _resumen_vinculo(
                db, _ultima_inspeccion_previa(db, empresa_id, ei_id, str(hi.id) if hi else "")
            ),
        }

    # Buscar sesión activa (en_proceso) para ESTE servicio — cada ciclo de
    # mantenimiento tiene su propia sesión ligada al proyecto_servicio_id.
    hi = (
        db.query(HistorialInspeccion)
        .filter(
            HistorialInspeccion.equipo_intervenido_id == ei_id,
            HistorialInspeccion.estado                == "en_proceso",
            HistorialInspeccion.proyecto_servicio_id  == servicio_id,
        )
        .order_by(HistorialInspeccion.created_at.desc())
        .first()
    )

    if not hi:
        # Primera vez o nueva sesión — no se puede iniciar sobre un servicio terminado
        _exigir_servicio_abierto(db, empresa_id, servicio_id)
        # crear con resultado vacío
        hi = HistorialInspeccion(
            id                    = str(_uuid.uuid4()),
            equipo_intervenido_id = ei_id,
            proyecto_servicio_id  = servicio_id,
            empresa_id            = empresa_id,
            estado                = "en_proceso",
            resultado             = _resultado_inicial(plantilla),
        )
        db.add(hi)
        ei.estado_intervencion  = "en_proceso"
        ei.proyecto_servicio_id = servicio_id
        # Propagar proyecto_id y cliente_id desde el servicio si aún son NULL
        _ps_link = db.query(ProyectoServicio).filter(ProyectoServicio.id == servicio_id).first()
        if _ps_link and _ps_link.proyecto_id:
            if not ei.proyecto_id:
                ei.proyecto_id = str(_ps_link.proyecto_id)
            if not ei.cliente_id:
                _proy = db.query(Proyecto).filter(Proyecto.id == _ps_link.proyecto_id).first()
                if _proy and _proy.cliente_id:
                    ei.cliente_id = str(_proy.cliente_id)
        ei.updated_at = datetime.utcnow()
        db.commit()

    # Mezclar resultado guardado con plantilla (para añadir nuevos procs si la plantilla creció)
    resultado = hi.resultado or []
    ordenes_guardados = {r["orden"] for r in resultado}
    for item in plantilla:
        if item["orden"] not in ordenes_guardados:
            resultado.append({
                "orden": item["orden"], "nombre": item["nombre"],
                "descripcion": item.get("descripcion", ""),
                "completado": False, "foto_url": None, "foto_public_id": None,
            })
    resultado.sort(key=lambda x: x["orden"])

    return {
        "inspeccion_id":       str(hi.id),
        "estado":              hi.estado,
        "resultado":           resultado,
        "observaciones":       hi.observaciones or None,
        "proxima_fecha":       hi.proxima_fecha_mantenimiento.isoformat() if hi.proxima_fecha_mantenimiento else None,
        "equipo": _equipo_info_dict(db, ei, tipo),
        "inspeccion_padre_id": str(hi.inspeccion_padre_id) if hi.inspeccion_padre_id else None,
        "padre": _resumen_vinculo(
            db,
            db.query(HistorialInspeccion).filter(
                HistorialInspeccion.id == str(hi.inspeccion_padre_id)
            ).first(),
        ) if hi.inspeccion_padre_id else None,
        "intervencion_anterior": _resumen_vinculo(
            db, _ultima_inspeccion_previa(db, empresa_id, ei_id, str(hi.id))
        ),
    }


# ── POST /inspeccion/{id}/foto/{orden} ────────────────────────────────────────
# Sube o reemplaza la foto del procedimiento N en la sesión activa.
# Misma sesión → reemplaza el recurso en Cloudinary (mismo public_id).

@router.post(
    "/inspeccion/{inspeccion_id}/foto/{orden}",
    status_code=status.HTTP_200_OK,
)
async def subir_foto_inspeccion(
    inspeccion_id: str,
    orden:         int,
    archivo:       UploadFile = File(...),
    payload:       dict       = Depends(verificar_token),
    db:            Session    = Depends(get_db),
):
    import cloudinary.uploader as cl_up

    empresa_id = payload["empresa_id"]

    hi = db.query(HistorialInspeccion).filter(
        HistorialInspeccion.id         == inspeccion_id,
        HistorialInspeccion.empresa_id == empresa_id,
        HistorialInspeccion.estado     == "en_proceso",
    ).first()
    if not hi:
        raise HTTPException(status_code=404, detail="Sesión de inspección no encontrada o ya finalizada")

    if hi.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(hi.proyecto_servicio_id))

    resultado = list(hi.resultado or [])
    paso = next((r for r in resultado if r["orden"] == orden), None)
    if paso is None:
        raise HTTPException(status_code=404, detail=f"Procedimiento {orden} no encontrado")

    # Si ya tiene foto en esta sesión → usar mismo public_id para reemplazar en Cloudinary
    old_pub_id = paso.get("foto_public_id")
    ei_id      = str(hi.equipo_intervenido_id)

    if old_pub_id:
        # Reemplazar: subir con mismo public_id (overwrite=True)
        try:
            contenido = await archivo.read()
            result    = cl_up.upload(
                contenido,
                public_id  = old_pub_id,
                overwrite  = True,
                invalidate = True,
                resource_type = "image",
            )
            url    = result.get("secure_url", "")
            pub_id = old_pub_id
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Error Cloudinary: {exc}")
    else:
        # Foto nueva para este procedimiento en esta sesión
        folder = f"e_zyro/{empresa_id}/mantenimiento/{ei_id}/{inspeccion_id}"
        try:
            url    = await subir_archivo_cloudinary(archivo, folder)
            pub_id = _extract_public_id(url)
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Error Cloudinary: {exc}")

    paso["foto_url"]      = url
    paso["foto_public_id"] = pub_id

    # Persistir JSONB actualizado
    from sqlalchemy import text as _text
    db.execute(
        _text("UPDATE historial_inspeccion SET resultado = :r WHERE id = :id"),
        {"r": __import__("json").dumps(resultado), "id": inspeccion_id},
    )
    db.commit()

    return {"ok": True, "url": url, "public_id": pub_id, "orden": orden}


# ── DELETE /inspeccion/{id}/foto/{orden} ──────────────────────────────────────

@router.delete("/inspeccion/{inspeccion_id}/foto/{orden}", status_code=status.HTTP_200_OK)
def quitar_foto_inspeccion(
    inspeccion_id: str,
    orden:         int,
    payload:       dict    = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    import cloudinary.uploader as cl_up

    empresa_id = payload["empresa_id"]

    hi = db.query(HistorialInspeccion).filter(
        HistorialInspeccion.id         == inspeccion_id,
        HistorialInspeccion.empresa_id == empresa_id,
        HistorialInspeccion.estado     == "en_proceso",
    ).first()
    if not hi:
        raise HTTPException(status_code=404, detail="Sesión no encontrada o ya finalizada")

    if hi.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(hi.proyecto_servicio_id))

    resultado = list(hi.resultado or [])
    paso = next((r for r in resultado if r["orden"] == orden), None)
    if paso is None:
        raise HTTPException(status_code=404, detail=f"Procedimiento {orden} no encontrado")

    if paso.get("foto_public_id"):
        try:
            cl_up.destroy(paso["foto_public_id"])
        except Exception:
            pass

    paso["foto_url"]       = None
    paso["foto_public_id"] = None

    from sqlalchemy import text as _text
    db.execute(
        _text("UPDATE historial_inspeccion SET resultado = :r WHERE id = :id"),
        {"r": __import__("json").dumps(resultado), "id": inspeccion_id},
    )
    db.commit()
    return {"ok": True}


# ── POST /inspeccion/{id}/guardar ─────────────────────────────────────────────
# Guarda el estado del checklist sin finalizar la sesión.

@router.post("/inspeccion/{inspeccion_id}/guardar")
def guardar_inspeccion(
    inspeccion_id: str,
    body:          dict,
    payload:       dict    = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    hi = db.query(HistorialInspeccion).filter(
        HistorialInspeccion.id         == inspeccion_id,
        HistorialInspeccion.empresa_id == empresa_id,
        HistorialInspeccion.estado     == "en_proceso",
    ).first()
    if not hi:
        raise HTTPException(status_code=404, detail="Sesión no encontrada o ya finalizada")

    if hi.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(hi.proyecto_servicio_id))

    resultado     = list(hi.resultado or [])
    nuevo_estado  = {r["orden"]: r for r in body.get("resultado", [])}
    observaciones = body.get("observaciones") or None

    for paso in resultado:
        upd = nuevo_estado.get(paso["orden"])
        if upd:
            paso["completado"] = bool(upd.get("completado", False))
            # No sobreescribir foto_url desde aquí — eso lo hace /foto/{orden}

    from sqlalchemy import text as _text
    db.execute(
        _text("UPDATE historial_inspeccion SET resultado = :r, observaciones = :o WHERE id = :id"),
        {"r": __import__("json").dumps(resultado), "o": observaciones, "id": inspeccion_id},
    )
    db.commit()

    todos = all(p.get("completado") for p in resultado)
    return {"ok": True, "todos_completados": todos}


# ── POST /inspeccion/{id}/finalizar ───────────────────────────────────────────
# Cierra la sesión, registra la próxima fecha y preserva el historial.

@router.post("/inspeccion/{inspeccion_id}/finalizar")
def finalizar_inspeccion(
    inspeccion_id: str,
    body:          dict,
    payload:       dict    = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    from datetime import date as _date

    empresa_id = payload["empresa_id"]

    hi = db.query(HistorialInspeccion).filter(
        HistorialInspeccion.id         == inspeccion_id,
        HistorialInspeccion.empresa_id == empresa_id,
        HistorialInspeccion.estado     == "en_proceso",
    ).first()
    if not hi:
        raise HTTPException(status_code=404, detail="Sesión no encontrada o ya finalizada")

    if hi.proyecto_servicio_id:
        _exigir_servicio_abierto(db, empresa_id, str(hi.proyecto_servicio_id))

    # Guardar resultado final
    resultado     = list(hi.resultado or [])
    nuevo_estado  = {r["orden"]: r for r in body.get("resultado", [])}
    observaciones = body.get("observaciones") or hi.observaciones

    for paso in resultado:
        upd = nuevo_estado.get(paso["orden"])
        if upd:
            paso["completado"] = bool(upd.get("completado", False))

    proxima_str = body.get("proxima_fecha_mantenimiento")
    proxima_fecha = None
    if proxima_str:
        try:
            proxima_fecha = _date.fromisoformat(proxima_str)
        except ValueError:
            pass
    if proxima_fecha is None:
        # Default preventivo: hoy + frecuencia del equipo. El técnico puede
        # sobreescribirla enviando proxima_fecha_mantenimiento explícita.
        from .equipos_intervenidos import _sumar_meses
        _ei_frec = db.query(EquipoIntervenido.frecuencia_meses).filter(
            EquipoIntervenido.id == hi.equipo_intervenido_id
        ).scalar()
        proxima_fecha = _sumar_meses(_date.today(), int(_ei_frec or 6))

    hi.estado                       = "completado"
    hi.resultado                    = resultado
    hi.observaciones                = observaciones
    hi.proxima_fecha_mantenimiento  = proxima_fecha
    hi.fecha_fin                    = datetime.utcnow()

    # Actualizar estado y plan de mantenimiento del activo
    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == hi.equipo_intervenido_id
    ).first()
    if ei:
        ei.estado_intervencion  = "completado"
        ei.ultimo_mantenimiento = _date.today()
        if proxima_fecha:
            ei.proximo_mantenimiento = proxima_fecha
        # Asegurar que el equipo queda vinculado al servicio donde se realizó la inspección
        ei.proyecto_servicio_id = hi.proyecto_servicio_id
        if hi.proyecto_servicio_id and (not ei.proyecto_id or not ei.cliente_id):
            _ps_fin = db.query(ProyectoServicio).filter(
                ProyectoServicio.id == hi.proyecto_servicio_id
            ).first()
            if _ps_fin and _ps_fin.proyecto_id:
                if not ei.proyecto_id:
                    ei.proyecto_id = str(_ps_fin.proyecto_id)
                if not ei.cliente_id:
                    _proy_fin = db.query(Proyecto).filter(Proyecto.id == _ps_fin.proyecto_id).first()
                    if _proy_fin and _proy_fin.cliente_id:
                        ei.cliente_id = str(_proy_fin.cliente_id)
        ei.updated_at = datetime.utcnow()

    # Sincronizar estado completado en historial_mantenimiento
    if hi.proyecto_servicio_id:
        _hm_fin = db.query(HistorialMantenimiento).filter(
            HistorialMantenimiento.equipo_id   == str(hi.equipo_intervenido_id),
            HistorialMantenimiento.servicio_id == str(hi.proyecto_servicio_id),
        ).first()
        if _hm_fin:
            _hm_fin.estado          = "completado"
            _hm_fin.fecha_ejecucion = datetime.utcnow()

    db.commit()

    return {
        "ok":            True,
        "inspeccion_id": inspeccion_id,
        "proxima_fecha": proxima_fecha.isoformat() if proxima_fecha else None,
    }


# ── POST /inspeccion/{id}/vincular ────────────────────────────────────────────
# Encadena la inspección actual con una anterior del MISMO equipo (o la desvincula).

@router.post("/inspeccion/{inspeccion_id}/vincular")
def vincular_inspeccion(
    inspeccion_id: str,
    body:          dict,
    payload:       dict    = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    """body: {"inspeccion_padre_id": "<id>" | null}. Valida que el padre exista,
    sea de la misma empresa y del mismo equipo, y no sea la propia inspección."""
    empresa_id = payload["empresa_id"]

    hi = db.query(HistorialInspeccion).filter(
        HistorialInspeccion.id         == inspeccion_id,
        HistorialInspeccion.empresa_id == empresa_id,
    ).first()
    if not hi:
        raise HTTPException(status_code=404, detail="Inspección no encontrada")

    padre_id = body.get("inspeccion_padre_id")
    if padre_id:
        padre_id = str(padre_id)
        if padre_id == inspeccion_id:
            raise HTTPException(status_code=400, detail="Una inspección no puede vincularse a sí misma")
        padre = db.query(HistorialInspeccion).filter(
            HistorialInspeccion.id         == padre_id,
            HistorialInspeccion.empresa_id == empresa_id,
        ).first()
        if not padre:
            raise HTTPException(status_code=404, detail="Intervención anterior no encontrada")
        if str(padre.equipo_intervenido_id) != str(hi.equipo_intervenido_id):
            raise HTTPException(status_code=400, detail="La intervención anterior pertenece a otro equipo")
        hi.inspeccion_padre_id = padre_id
    else:
        hi.inspeccion_padre_id = None

    db.commit()

    padre_row = None
    if hi.inspeccion_padre_id:
        padre_row = db.query(HistorialInspeccion).filter(
            HistorialInspeccion.id == str(hi.inspeccion_padre_id)
        ).first()
    return {
        "ok": True,
        "inspeccion_padre_id": str(hi.inspeccion_padre_id) if hi.inspeccion_padre_id else None,
        "padre": _resumen_vinculo(db, padre_row),
    }


# ── GET /servicio/{sid}/equipos-intervenidos/{eiId}/intervenciones-previas ────
# Lista de intervenciones COMPLETADAS del equipo (de otros servicios) para que
# el usuario elija a cuál vincular la inspección actual.

@router.get("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/intervenciones-previas")
def intervenciones_previas(
    servicio_id: str,
    ei_id:       str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    # Inspección activa de ESTE servicio (para no ofrecerla como su propio padre).
    actual = (
        db.query(HistorialInspeccion)
        .filter(
            HistorialInspeccion.equipo_intervenido_id == ei_id,
            HistorialInspeccion.empresa_id            == empresa_id,
            HistorialInspeccion.proyecto_servicio_id  == servicio_id,
        )
        .order_by(HistorialInspeccion.created_at.desc())
        .first()
    )
    actual_id = str(actual.id) if actual else ""

    registros = (
        db.query(HistorialInspeccion)
        .filter(
            HistorialInspeccion.equipo_intervenido_id == ei_id,
            HistorialInspeccion.empresa_id            == empresa_id,
            HistorialInspeccion.estado                == "completado",
        )
        .order_by(HistorialInspeccion.fecha_fin.desc())
        .all()
    )
    return [
        _resumen_vinculo(db, r) for r in registros if str(r.id) != actual_id
    ]


# ── GET /servicio/{sid}/equipos-intervenidos/{eiId}/historial ─────────────────

@router.get("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/historial")
def get_historial_ei(
    servicio_id: str,
    ei_id:       str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    registros = (
        db.query(HistorialInspeccion)
        .filter(
            HistorialInspeccion.equipo_intervenido_id == ei_id,
            HistorialInspeccion.empresa_id            == empresa_id,
            HistorialInspeccion.estado                == "completado",
        )
        .order_by(HistorialInspeccion.fecha_fin.desc())
        .all()
    )

    return [_map_hi(r) for r in registros]


# ── PATCH /servicio/{sid}/equipos-intervenidos/{eiId} — actualizar estado ─────

@router.post("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/completar")
def completar_intervencion_legacy(
    servicio_id: str,
    ei_id:       str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Compatibilidad con el frontend anterior."""
    empresa_id = payload["empresa_id"]
    _exigir_servicio_abierto(db, empresa_id, servicio_id)
    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id                   == ei_id,
        EquipoIntervenido.proyecto_servicio_id == servicio_id,
        EquipoIntervenido.empresa_id           == empresa_id,
    ).first()
    if not ei:
        raise HTTPException(status_code=404, detail="EquipoIntervenido no encontrado")
    ei.estado_intervencion = "completado"
    ei.updated_at          = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado_intervencion": "completado"}


# ── PATCH /servicio/{sid}/equipos-intervenidos/{eiId} ─────────────────────────
# Actualiza campos editables de un equipo intervenido. Lo usa:
#   - el motor de inspeccion (estado_intervencion / observaciones), y
#   - la vista del tecnico para EDITAR la "Referencia" (ubicacion_referencia),
#     que son solo las indicaciones fisicas de donde se encuentra el equipo.
# Nota: ubicacion_id / zona_id NO se tocan aqui; son datos heredados de la sede.

@router.patch("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}")
def actualizar_equipo_intervenido(
    servicio_id: str,
    ei_id:       str,
    body:        dict,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id         == ei_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not ei:
        raise HTTPException(status_code=404, detail="EquipoIntervenido no encontrado")

    _assert_servicio_abierto(servicio_id, db, empresa_id)

    body = body or {}

    # Referencia: el tecnico puede modificar las indicaciones o dejarlas igual.
    # Se permite vaciarla (cadena vacia -> None).
    if "ubicacion_referencia" in body:
        ref = (body.get("ubicacion_referencia") or "").strip()
        ei.ubicacion_referencia = ref or None

    if "estado_intervencion" in body and body.get("estado_intervencion"):
        ei.estado_intervencion = body["estado_intervencion"]

    if "observaciones" in body:
        ei.observaciones = (body.get("observaciones") or "").strip() or None

    # Campos libres opcionales
    for campo in ("marca", "modelo", "numero_serie"):
        if campo in body:
            setattr(ei, campo, (body.get(campo) or "").strip() or None)

    if "estado" in body and body.get("estado"):
        ei.estado = body["estado"]

    # Frecuencia del ciclo preventivo (meses). Recalcula el próximo
    # mantenimiento desde el último realizado, si existe.
    if "frecuencia_meses" in body:
        try:
            frec = int(body.get("frecuencia_meses"))
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="frecuencia_meses inválida")
        if not 1 <= frec <= 60:
            raise HTTPException(status_code=422, detail="frecuencia_meses debe estar entre 1 y 60")
        ei.frecuencia_meses = frec
        if ei.ultimo_mantenimiento:
            from .equipos_intervenidos import _sumar_meses
            ei.proximo_mantenimiento = _sumar_meses(ei.ultimo_mantenimiento, frec)

    ei.updated_at = datetime.utcnow()
    db.commit()

    return {
        "ok":                   True,
        "id":                   str(ei.id),
        "ubicacion_referencia": ei.ubicacion_referencia or None,
        "estado_intervencion":  ei.estado_intervencion or "sin_inspeccion",
        "estado":               ei.estado or "operativo",
        "marca":                ei.marca or None,
        "modelo":               ei.modelo or None,
        "numero_serie":         ei.numero_serie or None,
        "observaciones":        ei.observaciones or None,
        "frecuencia_meses":     ei.frecuencia_meses,
        "proximo_mantenimiento": ei.proximo_mantenimiento.isoformat() if ei.proximo_mantenimiento else None,
    }


# ════════════════════════════════════════════════════════════════════════════
# INFORME GENERAL — datos para el modal "Generar Informe"
# ════════════════════════════════════════════════════════════════════════════
# Los DEFAULTS por tipo de equipo (EPP / materiales / herramientas) viven en el
# frontend (diccionarios migrados del PHP). El backend solo aporta lo REAL del
# servicio: materiales solicitados, herramientas retiradas y el personal del
# proyecto. El frontend hace el MERGE (defaults + servicio, sin duplicados).

@router.get("/servicio/{servicio_id}/informe/precarga")
def precarga_informe_general(
    servicio_id: str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    proyecto = db.query(Proyecto).filter(Proyecto.id == ps.proyecto_id).first()

    # ── Materiales SOLICITADOS para el servicio (requerimiento + detalle) ──
    mat_rows = (
        db.query(RequerimientoDetalle, Material)
        .join(Requerimiento, Requerimiento.id == RequerimientoDetalle.requerimiento_id)
        .outerjoin(Material, Material.id == RequerimientoDetalle.material_id)
        .filter(
            Requerimiento.proyecto_servicio_id == servicio_id,
            Requerimiento.empresa_id           == empresa_id,
        )
        .all()
    )
    materiales, vistos_mat = [], set()
    for det, mat in mat_rows:
        nombre = ((mat.nombre if mat else det.nombre_libre) or "").strip()
        if not nombre or nombre.upper() in vistos_mat:
            continue
        vistos_mat.add(nombre.upper())
        materiales.append({
            "nombre":          nombre,
            "unidad":          (mat.unidad if mat else det.unidad_libre) or "UND.",
            "caracteristicas": det.especificacion or (mat.descripcion if mat else None) or "-",
        })

    # ── Herramientas RETIRADAS/prestadas para el servicio (prestamo + item) ──
    herr_rows = (
        db.query(PrestamoItem, Equipo)
        .join(Prestamo, Prestamo.id == PrestamoItem.prestamo_id)
        .join(Equipo,   Equipo.id   == PrestamoItem.equipo_id)
        .filter(
            Prestamo.proyecto_servicio_id == servicio_id,
            Prestamo.empresa_id           == empresa_id,
        )
        .all()
    )
    herramientas, vistos_herr = [], set()
    for _item, eq in herr_rows:
        nombre = (eq.nombre or "").strip()
        if not nombre or nombre.upper() in vistos_herr:
            continue
        vistos_herr.add(nombre.upper())
        herramientas.append({
            "serie":  eq.numero_serie or "-",
            "nombre": nombre,
            "marca":  eq.marca or "-",
        })

    # ── Personal del PROYECTO del servicio (equipo de trabajo mapeado) ──
    pers_rows = (
        db.query(
            Empleado.id.label("empleado_id"),
            Usuario.nombre, Usuario.apellido,
            Empleado.cargo, ProyectoMiembro.rol_proyecto,
        )
        .join(Usuario,         Usuario.id == Empleado.usuario_id)
        .join(ProyectoMiembro, ProyectoMiembro.empleado_id == Empleado.id)
        .filter(
            ProyectoMiembro.proyecto_id == ps.proyecto_id,
            ProyectoMiembro.activo      == True,
        )
        .all()
    )
    personal, vistos_pers = [], set()
    for r in pers_rows:
        if r.empleado_id in vistos_pers:
            continue
        vistos_pers.add(r.empleado_id)
        nom = f"{r.nombre or ''} {r.apellido or ''}".strip() or "Sin nombre"
        personal.append({
            "id":           str(r.empleado_id),
            "nombre":       nom,
            "cargo":        r.cargo or "",
            "rol_sugerido": r.rol_proyecto or "Técnico",
        })

    cliente_nombre = None
    if proyecto and proyecto.cliente_id:
        cli = db.query(Cliente).filter(Cliente.id == proyecto.cliente_id).first()
        cliente_nombre = cli.razon_social if cli else None

    return {
        "servicio": {
            "id":              str(ps.id),
            "nombre":          ps.nombre or "",
            "proyecto_id":     str(ps.proyecto_id),
            "proyecto_nombre": (proyecto.nombre_proyecto if proyecto else None),
            "tipo_documento":  ps.tipo_documento_cliente or "",
            "nro_documento":   ps.nro_documento or "",
            "cliente_nombre":  cliente_nombre,
        },
        "materiales_solicitados":  materiales,
        "herramientas_solicitadas": herramientas,
        "personal":                personal,
    }


def _exigir_equipos_completados(db: Session, empresa_id: str, ei_ids: list) -> None:
    """Candado de entregables al cliente: todos los equipos seleccionados deben
    tener su inspección completada (mismo criterio que los certificados)."""
    if not ei_ids:
        return
    pendientes = (
        db.query(EquipoIntervenido.nombre)
        .filter(
            EquipoIntervenido.id.in_([str(i) for i in ei_ids]),
            EquipoIntervenido.empresa_id == empresa_id,
            EquipoIntervenido.estado_intervencion != "completado",
        )
        .all()
    )
    if pendientes:
        nombres = ", ".join(n for (n,) in pendientes[:5])
        if len(pendientes) > 5:
            nombres += f" y {len(pendientes) - 5} más"
        raise HTTPException(
            status_code=400,
            detail=(f"Hay equipos con inspección sin completar: {nombres}. "
                    f"Completa sus procedimientos antes de generar el documento."),
        )


@router.post("/servicio/{servicio_id}/informe/generar")
def generar_informe_general(
    servicio_id: str,
    body:        dict,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Genera el Informe General de Pozos a Tierra (.docx) y lo devuelve
    como blob descargable. Convierte imágenes WebP de evidencias a JPEG."""
    from ..services.word_informe_pozos import generar_word_pozos
    from ..services.report_templates import get_config

    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    body = body or {}

    # ── Validar y extraer payload ──────────────────────────────────────────────
    equipos_payload     = body.get("equipos", []) or []

    # Técnico: solo puede generar pre-informe de sus propias tareas/equipos intervenidos
    if es_tecnico(payload):
        emp_tec = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if emp_tec:
            mis_tareas = db.query(Tarea).filter(
                Tarea.proyecto_servicio_id == servicio_id,
                Tarea.responsable_id       == emp_tec.id,
            ).all()
            if not mis_tareas:
                raise HTTPException(
                    status_code=403,
                    detail="No tienes tareas asignadas en este servicio para generar el pre-informe",
                )
        else:
            raise HTTPException(status_code=403, detail="No eres empleado registrado")

    # Jefe de Operaciones: solo genera pre-informe si tiene tareas asignadas a su nombre
    if es_jefe_operaciones(payload):
        emp_jefe = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if emp_jefe:
            tiene_tareas = db.query(Tarea).filter(
                Tarea.proyecto_servicio_id == servicio_id,
                Tarea.responsable_id       == emp_jefe.id,
            ).first() is not None
            if not tiene_tareas:
                raise HTTPException(
                    status_code=403,
                    detail="Como Jefe de Operaciones, solo puedes generar el pre-informe si tienes tareas asignadas a tu nombre en este servicio",
                )

    # Informe FINAL (no pre-informe de técnico/jefe): todos los equipos
    # seleccionados deben tener su inspección completada. Los procedimientos
    # completos son el sustento del documento que se entrega al cliente.
    if not es_tecnico(payload) and not es_jefe_operaciones(payload):
        _exigir_equipos_completados(
            db, empresa_id, [eq.get("id") for eq in equipos_payload if eq.get("id")]
        )

    epps_payload        = body.get("epps", []) or []
    herramientas_payload= body.get("herramientas", []) or []
    materiales_payload  = body.get("materiales", []) or []
    personal_payload    = body.get("personal", []) or []
    oc                  = str(body.get("oc", "") or "")

    # ── Ubicación: provincias únicas de los equipos ────────────────────────────
    provincias = []
    vistas: set[str] = set()
    for eq in equipos_payload:
        prov = (eq.get("provincia") or eq.get("ubicacion") or "").strip()
        if prov and prov.upper() not in vistas:
            vistas.add(prov.upper())
            provincias.append(prov)
    ubicacion_str = ", ".join(provincias) if provincias else (ps.zona_ejecucion or "")

    # ── Evidencias fotográficas agrupadas por equipo intervenido ──────────────
    ei_ids = [eq["id"] for eq in equipos_payload if eq.get("id")]

    evidencias_por_equipo: list[dict] = []

    if ei_ids:
        # Cargar todos los HistorialInspeccion de los equipos solicitados
        historials = (
            db.query(HistorialInspeccion)
            .filter(
                HistorialInspeccion.equipo_intervenido_id.in_(ei_ids),
                HistorialInspeccion.empresa_id == empresa_id,
            )
            .order_by(HistorialInspeccion.fecha_inicio)
            .all()
        )

        # Agrupar fotos por equipo_intervenido_id (tomar la sesión más reciente completada, o cualquiera)
        fotos_map: dict[str, list[dict]] = {}
        for hi in historials:
            eid = str(hi.equipo_intervenido_id)
            resultado = hi.resultado or []
            for paso in resultado:
                foto_url = paso.get("foto_url") or paso.get("url")
                if not foto_url:
                    continue
                obs = paso.get("nombre") or paso.get("descripcion") or ""
                if eid not in fotos_map:
                    fotos_map[eid] = []
                fotos_map[eid].append({"url": foto_url, "obs": obs})

        # Construir lista en el orden de los equipos del payload
        nombre_map = {eq["id"]: eq.get("nombre", "") for eq in equipos_payload}
        for eid in ei_ids:
            evidencias_por_equipo.append({
                "nombre": nombre_map.get(eid, eid),
                "fotos":  fotos_map.get(eid, []),
            })

    # ── Seleccionar config según tipo de equipo ───────────────────────────────
    tipo_base    = str(body.get("tipo_base", "") or "")
    razon_social = str(body.get("razon_social", "") or "")
    cfg = get_config(equipos_payload, tipo_base)

    # ── Generar documento Word ─────────────────────────────────────────────────
    try:
        docx_bytes = generar_word_pozos(
            cfg=cfg,
            oc=oc,
            ubicacion=ubicacion_str,
            equipos=equipos_payload,
            epps=epps_payload,
            herramientas=herramientas_payload,
            materiales=materiales_payload,
            personal=personal_payload,
            evidencias_por_equipo=evidencias_por_equipo,
            razon_social=razon_social,
        )
    except Exception as exc:
        logger.exception("[informe-pozos] Error generando Word: %s", exc)
        raise HTTPException(status_code=500, detail=f"Error generando el informe: {exc}")

    oc_safe = re.sub(r"[^A-Za-z0-9_\-]", "_", oc) if oc else "SIN_OC"
    tipo_label = cfg.get("tipo_label", tipo_base.upper() if tipo_base else "POZOS")
    filename = f"INFORME_MTTO_{tipo_label}_OC_{oc_safe}.docx"

    # ── Persistir como informe INTERNO (no va al portal del cliente) ──────────
    # Se sube el .docx a Cloudinary y se enlaza a la carta de garantía más
    # reciente del mismo servicio (vínculo informe ↔ garantía).
    try:
        from ..models.informe_servicio import InformeServicio
        from ..models.carta_garantia import CartaGarantia as _CG
        inf_id = str(_uuid.uuid4())
        pid = f"e-zyro/{empresa_id}/informes-internos/{servicio_id}/general_{inf_id}"
        url = subir_bytes_raw_cloudinary(docx_bytes, pid, ext="docx")
        gar = (
            db.query(_CG)
            .filter(_CG.empresa_id == empresa_id, _CG.servicio_id == servicio_id)
            .order_by(_CG.created_at.desc())
            .first()
        )
        db.add(InformeServicio(
            id=inf_id, empresa_id=empresa_id, servicio_id=servicio_id,
            tipo="general", ambito="interno",
            titulo=f"Informe general — {ps.nombre}",
            url=url, public_id=pid + ".docx",
            generado_por_id=usuario_id,
            garantia_id=(str(gar.id) if gar else None),
        ))
        db.commit()
    except Exception as exc_db:
        db.rollback()
        logger.warning("[informe-general] No se pudo persistir el informe interno: %s", exc_db)

    return StreamingResponse(
        io.BytesIO(docx_bytes),
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ── POST /servicio/{id}/carta-garantia/generar ────────────────────────────────

@router.post("/servicio/{servicio_id}/carta-garantia/generar")
def generar_carta_garantia(
    servicio_id: str,
    body:        dict,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Genera la Carta de Garantía de Tableros Eléctricos (.docx) y la devuelve como blob."""
    from ..services.word_carta_garantia import generar_carta_garantia as _gen_carta
    from ..models.carta_garantia import CartaGarantia

    empresa_id = payload["empresa_id"]
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    body = body or {}
    equipos               = body.get("equipos", []) or []
    # La carta de garantía es entregable al cliente: exige inspecciones completas.
    _exigir_equipos_completados(
        db, empresa_id, [eq.get("id") for eq in equipos if isinstance(eq, dict) and eq.get("id")]
    )
    fecha_operatividad    = str(body.get("fechaOperatividad", "") or "")
    vigencia_garantia     = str(body.get("vigenciaGarantia", "") or "")
    lugar                 = str(body.get("lugar", "") or "")
    direccion             = str(body.get("direccion", "") or "")
    firma_verificador_b64 = str(body.get("firmaVerificadorBase64", "") or "")
    firma_gerente_b64     = str(body.get("firmaGerenteBase64", "") or "")

    # ── Razón Social ──────────────────────────────────────────────────────────
    # Prioridad 1: equipo_intervenido.cliente_id → cliente.razon_social
    #   (solo por id, sin filtrar empresa_id para evitar fallos en entornos mixtos;
    #    la seguridad ya está garantizada por el check de ProyectoServicio de arriba)
    # Prioridad 2: lo que el usuario escribió/aprobó en el modal (frontend payload)
    razon_social    = str(body.get("razonSocial", "") or "")
    razon_social_bd: str | None = None

    if equipos:
        first_ei_id = (equipos[0].get("id") or "").strip()
        if first_ei_id:
            ei_obj = db.query(EquipoIntervenido).filter(
                EquipoIntervenido.id == first_ei_id,
            ).first()
            if ei_obj and ei_obj.cliente_id:
                cli_obj = db.query(Cliente).filter(
                    Cliente.id == ei_obj.cliente_id,
                ).first()
                if cli_obj and cli_obj.razon_social:
                    razon_social_bd = cli_obj.razon_social.strip()

    if razon_social_bd:
        razon_social = razon_social_bd

    # ── Strip data-URI prefix de firmas (data:image/png;base64,...) ───────────
    def _strip_prefix(s: str) -> str:
        return s.split(",", 1)[1] if "," in s else s

    firma_verificador_b64 = _strip_prefix(firma_verificador_b64)
    firma_gerente_b64     = _strip_prefix(firma_gerente_b64)

    # ── Subir firmas a Cloudinary y obtener URLs seguras ──────────────────────
    from ..services.cloudinary_service import subir_imagen_cloudinary
    import uuid as _uuid_mod

    firma_verificador_url: str | None = None
    firma_gerente_url:     str | None = None
    _uid = str(_uuid_mod.uuid4())[:8]

    if firma_verificador_b64:
        try:
            firma_verificador_url = subir_imagen_cloudinary(
                base64_data=firma_verificador_b64,
                folder="e-zyro/firmas/garantia",
                public_id=f"firma_verificador_{servicio_id}_{_uid}",
            )
        except Exception as exc_cl:
            logger.warning("[carta-garantia] No se pudo subir firma verificador a Cloudinary: %s", exc_cl)

    if firma_gerente_b64:
        try:
            firma_gerente_url = subir_imagen_cloudinary(
                base64_data=firma_gerente_b64,
                folder="e-zyro/firmas/garantia",
                public_id=f"firma_gerente_{servicio_id}_{_uid}",
            )
        except Exception as exc_cl:
            logger.warning("[carta-garantia] No se pudo subir firma gerente a Cloudinary: %s", exc_cl)

    # ── Persistir registro en carta_garantia ANTES de generar ─────────────────
    registro = None
    try:
        from datetime import date as _date
        def _parse_date(s: str):
            try: return _date.fromisoformat(s)
            except Exception: return None

        equipo_ids_list = [e.get("id") for e in equipos if e.get("id")]
        registro = CartaGarantia(
            empresa_id            = empresa_id,
            servicio_id           = servicio_id,
            equipo_ids            = equipo_ids_list,
            razon_social          = razon_social,
            lugar                 = lugar or None,
            direccion             = direccion or None,
            fecha_operatividad    = _parse_date(fecha_operatividad),
            vigencia_garantia     = _parse_date(vigencia_garantia),
            firma_verificador_url = firma_verificador_url,
            firma_gerente_url     = firma_gerente_url,
        )
        db.add(registro)
        db.commit()
    except Exception as exc_db:
        db.rollback()
        logger.warning("[carta-garantia] No se pudo persistir el registro: %s", exc_db)

    try:
        docx_bytes = _gen_carta(
            equipos=equipos,
            razon_social=razon_social,
            fecha_operatividad=fecha_operatividad,
            vigencia_garantia=vigencia_garantia,
            lugar=lugar,
            direccion=direccion,
            firma_verificador_b64=firma_verificador_b64,
            firma_gerente_b64=firma_gerente_b64,
        )
    except Exception as exc:
        logger.exception("[carta-garantia] Error generando Word: %s", exc)
        raise HTTPException(status_code=500, detail=f"Error generando la carta de garantía: {exc}")

    # ── Subir el .docx a Cloudinary y enlazarlo al registro (portal cliente) ──
    if registro is not None:
        try:
            pid = f"e-zyro/{empresa_id}/garantias/{servicio_id}/{registro.id}"
            url = subir_bytes_raw_cloudinary(docx_bytes, pid, ext="docx")
            registro.documento_pdf_url = url
            db.commit()
        except Exception as exc_up:
            db.rollback()
            logger.warning("[carta-garantia] No se pudo subir el documento: %s", exc_up)

    lugar_safe = re.sub(r"[^A-Za-z0-9_\-]", "_", lugar.upper()) if lugar else "LUGAR"
    filename   = f"CARTA_GARANTIA_{lugar_safe}.docx"

    return StreamingResponse(
        io.BytesIO(docx_bytes),
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ── POST /servicio/{id}/equipos-intervenidos/{eiId}/certificado/pozo ──────────

@router.post("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/certificado/pozo")
def generar_certificado_pozo(
    servicio_id: str,
    ei_id:       str,
    body:        dict            = Body(default={}),
    payload:     dict            = Depends(verificar_token),
    db:          Session         = Depends(get_db),
):
    """
    Genera el Protocolo de Medición de Resistencia del Pozo a Tierra en PDF.
    Inyecta textos y las fotos de los procedimientos 1, 4 y 7 sobre la plantilla.
    Requiere que la inspección esté finalizada (estado_intervencion = 'completado').
    """
    from ..services.pdf_certificados import generar_protocolo_pozo

    empresa_id = payload["empresa_id"]
    logger.info("[cert-pozo] ei_id=%s empresa_id=%s body_keys=%s", ei_id, empresa_id, list((body or {}).keys()))

    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id         == ei_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not ei:
        raise HTTPException(status_code=404, detail=f"Equipo intervenido no encontrado (ei_id={ei_id})")
    if ei.estado_intervencion != "completado":
        raise HTTPException(
            status_code=400,
            detail=(
                f"El certificado solo puede generarse cuando la inspección esté completada al 100%. "
                f"Estado actual: '{ei.estado_intervencion}'."
            ),
        )

    from datetime import date as _date_today
    body = body or {}

    ubicacion            = str(body.get("ubicacion",            ei.ubicacion_referencia or "") or "")
    nombre_pozo          = ei.nombre or ""
    numero_pozo          = str(body.get("numero_pozo",          "") or "") or (ei.nombre or "")
    fecha_actualizacion  = str(body.get("fecha_actualizacion",  _date_today.today().strftime("%d/%m/%Y")) or "")
    fecha_ejecucion      = str(body.get("fecha_ejecucion",      "") or "")
    fecha_hora_medicion  = str(body.get("fecha_hora_medicion",  "") or "")
    resultado_medicion   = str(body.get("resultado_medicion",   "") or "")
    hora_inicio          = str(body.get("hora_inicio",          "") or "")
    hora_termino         = str(body.get("hora_termino",         "") or "")
    nombre_tecnico       = str(body.get("nombre_tecnico",       "") or "")
    firma_tecnico        = body.get("firma_tecnico")  or None
    fotos                = body.get("fotos_procedimientos") or []

    logger.info(
        "[cert-pozo] nombre_pozo=%r numero_pozo=%r tecnico=%r firma_ok=%s fotos=%d",
        nombre_pozo, numero_pozo, nombre_tecnico, bool(firma_tecnico), len(fotos),
    )

    try:
        pdf_bytes = generar_protocolo_pozo(
            nombre_pozo=nombre_pozo,
            ubicacion=ubicacion,
            numero_pozo=numero_pozo,
            fecha_actualizacion=fecha_actualizacion,
            fecha_ejecucion=fecha_ejecucion,
            fecha_hora_medicion=fecha_hora_medicion,
            resultado_medicion=resultado_medicion,
            hora_inicio=hora_inicio,
            hora_termino=hora_termino,
            nombre_tecnico=nombre_tecnico,
            firma_tecnico=firma_tecnico,
            fotos_procedimientos=fotos,
        )
    except Exception as exc:
        logger.exception("[cert-pozo] Error generando PDF: %s", exc)
        raise HTTPException(status_code=500, detail=f"Error generando el certificado: {exc}")

    filename = f"PROTOCOLO_POZO_{re.sub(r'[^A-Za-z0-9]', '_', nombre_pozo or numero_pozo or 'XX')}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


# ── POST /servicio/{id}/equipos-intervenidos/{eiId}/certificado/operatividad ──

@router.post("/servicio/{servicio_id}/equipos-intervenidos/{ei_id}/certificado/operatividad")
def generar_certificado_operatividad(
    servicio_id: str,
    ei_id:       str,
    body:        dict            = Body(default={}),
    payload:     dict            = Depends(verificar_token),
    db:          Session         = Depends(get_db),
):
    """
    Genera el Certificado de Operatividad de Tablero Eléctrico en PDF.
    Inyecta textos y firmas sobre la plantilla.
    Requiere que la inspección esté finalizada (estado_intervencion = 'completado').
    """
    from ..services.pdf_certificados import generar_certificado_operatividad as _gen_cert

    empresa_id = payload["empresa_id"]
    body = body or {}
    logger.info(
        "[cert-ope] ei_id=%s empresa_id=%s body_keys=%s firma_ver_ok=%s firma_ger_ok=%s",
        ei_id, empresa_id, list(body.keys()),
        bool(body.get("firma_verificador")), bool(body.get("firma_gerente")),
    )

    ei = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id         == ei_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not ei:
        raise HTTPException(status_code=404, detail=f"Equipo intervenido no encontrado (ei_id={ei_id})")
    if ei.estado_intervencion != "completado":
        raise HTTPException(
            status_code=400,
            detail=(
                f"El certificado solo puede generarse cuando la inspección esté completada al 100%. "
                f"Estado actual: '{ei.estado_intervencion}'."
            ),
        )

    nombre_tablero   = str(body.get("nombre_tablero",   ei.nombre or "") or "")
    fecha            = str(body.get("fecha",             "") or "")
    razon_social     = str(body.get("razon_social",      "") or "")
    ubicacion        = str(body.get("ubicacion",         "") or "")
    personal_tecnico = str(body.get("personal_tecnico",  "") or "")
    firma_verificador = body.get("firma_verificador") or None
    firma_gerente     = body.get("firma_gerente")     or None

    # Auto-completar razón social desde BD si no viene en el payload
    if not razon_social and ei.cliente_id:
        cli = db.query(Cliente).filter(Cliente.id == ei.cliente_id).first()
        if cli and cli.razon_social:
            razon_social = cli.razon_social

    logger.info(
        "[cert-ope] nombre_tablero=%r fecha=%r razon_social=%r ubicacion=%r personal=%r",
        nombre_tablero, fecha, razon_social, ubicacion, personal_tecnico,
    )

    try:
        pdf_bytes = _gen_cert(
            nombre_tablero=nombre_tablero, fecha=fecha,
            razon_social=razon_social, ubicacion=ubicacion,
            personal_tecnico=personal_tecnico,
            firma_verificador=firma_verificador,
            firma_gerente=firma_gerente,
        )
    except Exception as exc:
        logger.exception("[cert-operatividad] Error generando PDF: %s", exc)
        raise HTTPException(status_code=500, detail=f"Error generando el certificado: {exc}")

    safe = re.sub(r"[^A-Za-z0-9]", "_", nombre_tablero or "TABLERO")
    filename = f"CERT_OPERATIVIDAD_{safe}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )
