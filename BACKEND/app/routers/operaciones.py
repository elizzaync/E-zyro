"""
Router: /operaciones
Gestión completa del módulo de Operaciones / Detalle de Servicio.
"""
from __future__ import annotations

import io
import logging
import re
import uuid as _uuid
import zipfile
from datetime import date, datetime

logger = logging.getLogger(__name__)

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from typing import List

from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError, ProgrammingError
from sqlalchemy.orm import Session, aliased

from ..core.security import verificar_token
from ..db.database import get_db
import requests as _requests
from ..services.cloudinary_service import subir_archivo_cloudinary, subir_pdf_bytes_cloudinary

# Modelos ORM
from ..models.proyecto_servicio import ProyectoServicio
from ..models.proyecto import Proyecto
from ..models.proyecto_detalle import ProyectoDetalle
from ..models.proyecto_miembro import ProyectoMiembro
from ..models.cliente import Cliente
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.procedimiento import Procedimiento
from ..models.evidencia_procedimiento import EvidenciaProcedimiento
from ..models.requerimiento import Requerimiento, RequerimientoDetalle
from ..models.material import Material, Stock
from ..models.equipo import Equipo
from ..models.tipo_equipo import TipoEquipo
from ..models.orden_mantenimiento import OrdenMantenimiento
from ..models.evidencia_mantenimiento import EvidenciaMantenimiento
from ..models.informe_tecnico import InformeTecnico
from ..models.paso_mantenimiento import PasoMantenimiento
from ..models.catalogo_servicio import CatalogoServicio
from ..models.grupo_trabajo import GrupoTrabajo, GrupoMiembro
from ..models.seguimiento_proyecto import SeguimientoProyecto

# Schemas Pydantic
from ..schemas.operaciones import (
    ServicioDetalleOut,
    MiembroEquipoOut,
    ProcedimientoOut,
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
    EquipoItemOut,
    MantenimientoHistorialOut,
    FotoEvidenciaOut,
    ChecklistEquipoOut,
    PasoChecklistOut,
    PatchMantenimientoBody,
    # CRUD nuevos
    ClienteOut,
    CatalogoServicioOut,
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
    ValidarHorarioBody,
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


# ── GET /operaciones/proyectos ────────────────────────────────────────────────

@router.get("/proyectos", response_model=ProyectosConKpisOut)
def get_proyectos(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
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

    if rol == "Administrador":
        # Admin ve todos los proyectos de la empresa sin restricción de membresía
        rows = base_q.order_by(Proyecto.created_at.desc()).all()
    else:
        empleado = _get_empleado_or_403(db, usuario_id, empresa_id)
        miembro_sq = (
            db.query(ProyectoMiembro.proyecto_id)
            .filter(ProyectoMiembro.empleado_id == empleado.id)
            .subquery()
        )
        rows = (
            base_q
            .filter(
                or_(
                    Proyecto.jefe_operaciones_id == empleado.id,
                    Proyecto.id.in_(miembro_sq),
                )
            )
            .order_by(Proyecto.created_at.desc())
            .all()
        )

    proyectos = [
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

    total_svc  = sum(p.total_servicios for p in proyectos)
    total_comp = sum(p.servicios_completados for p in proyectos)

    return ProyectosConKpisOut(
        kpis=KpisProyectosOut(
            total_proyectos=len(proyectos),
            servicios_completados=total_comp,
            servicios_pendientes=total_svc - total_comp,
            tasa_avance=round(total_comp / total_svc * 100) if total_svc else 0,
        ),
        proyectos=proyectos,
    )


# ── GET /operaciones/proyecto/{proyecto_id}/servicios ─────────────────────────

@router.get("/proyecto/{proyecto_id}/servicios", response_model=List[ProyectoServicioListOut])
def get_servicios_proyecto(
    proyecto_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
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

    if rol != "Administrador":
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

    hoy = date.today()
    result = []
    for ps in servicios:
        if ps.estado == "Completado":
            estado_color = "verde"
        elif ps.fecha_programada is not None and ps.fecha_programada < hoy:
            estado_color = "rojo"
        else:
            estado_color = "amarillo"

        result.append(ProyectoServicioListOut(
            id=str(ps.id),
            nombre=ps.nombre or "",
            descripcion=ps.descripcion,
            estado=ps.estado or "Pendiente",
            orden=ps.orden or 1,
            fecha_programada=ps.fecha_programada.strftime("%d %b %Y") if ps.fecha_programada else None,
            fecha_fin=ps.fecha_fin.strftime("%d %b %Y") if ps.fecha_fin else None,
            estado_color=estado_color,
        ))

    return result


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
            func.coalesce(ProyectoDetalle.zona_ejecucion, Proyecto.nombre_proyecto).label("ubicacion"),
        )
        .join(Proyecto, Proyecto.id == ProyectoServicio.proyecto_id)
        .join(Cliente,  Cliente.id  == Proyecto.cliente_id)
        .outerjoin(ProyectoDetalle, ProyectoDetalle.proyecto_id == Proyecto.id)
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
    detalle  = db.query(ProyectoDetalle).filter(ProyectoDetalle.proyecto_id == ps.proyecto_id).first()
    ubicacion = (detalle.zona_ejecucion if detalle and detalle.zona_ejecucion else proyecto.nombre_proyecto) or ""

    # 2. Verificar acceso: miembro del proyecto O jefe de operaciones (admin: bypass)
    if payload.get("rol", "") != "Administrador":
        empleado_actual = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if not empleado_actual:
            raise HTTPException(status_code=403, detail="No eres empleado registrado")

        es_jefe    = proyecto.jefe_operaciones_id == empleado_actual.id
        es_miembro = db.query(ProyectoMiembro).filter(
            ProyectoMiembro.proyecto_id == ps.proyecto_id,
            ProyectoMiembro.empleado_id == empleado_actual.id,
        ).first() is not None

        if not es_jefe and not es_miembro:
            raise HTTPException(status_code=403, detail="No tienes acceso a este servicio")

    fp        = ps.fecha_programada
    fecha_str = fp.strftime("%d %b %Y") if fp else "Sin fecha"
    hora_str  = fp.strftime("%I:%M %p") if fp else "--:--"

    # 3. Equipo de trabajo
    equipo_rows = (
        db.query(
            Usuario,
            Empleado.cargo,
            Empleado.id.label("empleado_id"),
            ProyectoMiembro.rol_proyecto,
        )
        .join(Empleado, Empleado.id == ProyectoMiembro.empleado_id)
        .join(Usuario,  Usuario.id  == Empleado.usuario_id)
        .filter(
            ProyectoMiembro.proyecto_id == ps.proyecto_id,
            ProyectoMiembro.activo      == True,
        )
        .all()
    )

    miembro_empleado_ids = {r.empleado_id for r in equipo_rows}

    equipo = [
        MiembroEquipoOut(
            id=str(r.empleado_id),   # empleado.id — requerido por el modal de configurar
            nombre=r.Usuario.nombre or "",
            apellido=r.Usuario.apellido or "",
            foto_url=r.Usuario.foto_url or "",
            cargo=r.cargo or "Sin Cargo",
            rol_proyecto=r.rol_proyecto or "Técnico",
        )
        for r in equipo_rows
    ]

    # Añadir jefe de operaciones si no está ya en ProyectoMiembro
    if proyecto.jefe_operaciones_id not in miembro_empleado_ids:
        jefe_emp = db.query(Empleado).filter(Empleado.id == proyecto.jefe_operaciones_id).first()
        if jefe_emp:
            jefe_usr = db.query(Usuario).filter(Usuario.id == jefe_emp.usuario_id).first()
            if jefe_usr:
                equipo.insert(0, MiembroEquipoOut(
                    id=str(jefe_emp.id),  # empleado.id
                    nombre=jefe_usr.nombre or "",
                    apellido=jefe_usr.apellido or "",
                    foto_url=jefe_usr.foto_url or "",
                    cargo=jefe_emp.cargo or "Sin Cargo",
                    rol_proyecto="Jefe de Operaciones",
                ))

    # 4. Procedimientos + Evidencias
    procs = (
        db.query(Procedimiento)
        .filter(Procedimiento.proyecto_servicio_id == servicio_id)
        .order_by(Procedimiento.orden.asc())
        .all()
    )
    evidencias = (
        db.query(EvidenciaProcedimiento)
        .filter(EvidenciaProcedimiento.proyecto_servicio_id == servicio_id)
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
                fecha_captura=ev.fecha_captura.strftime("%I:%M %p") if ev.fecha_captura else "",
            )
        )

    # 🔥 FIX PYDANTIC: Blindaje en Procedimientos
    procedimientos = [
        ProcedimientoOut(
            id=str(p.id),
            nombre=p.nombre or "",
            descripcion=p.descripcion or "",
            orden=p.orden or 0,
            estado=p.estado or "pendiente",
            evidencias=ev_by_proc.get(p.id, []),
            responsable_id=str(p.responsable_id) if p.responsable_id else None,
            fecha_inicio_tarea=p.fecha_inicio_tarea.isoformat() if getattr(p, 'fecha_inicio_tarea', None) else None,
            fecha_limite=p.fecha_limite.isoformat() if p.fecha_limite else None,
        )
        for p in procs
    ]

    total     = len(procedimientos)
    completos = sum(1 for p in procedimientos if p.estado == "completado")
    progreso  = round(completos / total * 100, 1) if total else 0.0

    # 5. Materiales (excluye borradores; soporta compras externas con material_id=NULL)
    mat_rows = (
        db.query(
            RequerimientoDetalle,
            Requerimiento.id.label("req_id"),
            Requerimiento.estado.label("req_estado"),
            func.coalesce(
                Material.nombre,
                RequerimientoDetalle.nombre_libre,
            ).label("mat_nombre"),
            func.coalesce(
                Material.unidad,
                RequerimientoDetalle.unidad_libre,
            ).label("mat_unidad"),
        )
        .join(Requerimiento, Requerimiento.id == RequerimientoDetalle.requerimiento_id)
        .outerjoin(Material, Material.id      == RequerimientoDetalle.material_id)
        .filter(
            Requerimiento.proyecto_servicio_id == servicio_id,
            Requerimiento.empresa_id           == empresa_id,
            Requerimiento.tipo                 == "material",
            Requerimiento.estado               != "borrador",
        )
        .order_by(Requerimiento.created_at.asc())
        .all()
    )

    mat_asignados: list[ItemMaterialOut]   = []
    mat_solicitados: list[ItemMaterialOut] = []

    for m in mat_rows:
        rd = m.RequerimientoDetalle
        item = ItemMaterialOut(
            id=str(rd.id),
            requerimiento_id=str(m.req_id),
            nombre=m.mat_nombre or "Material Sin Nombre",
            unidad=m.mat_unidad or "Und",
            cantidad=rd.cantidad or 0,
            estado_req=m.req_estado or "pendiente",
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
        materiales_asignados=mat_asignados,
        materiales_solicitados=mat_solicitados,
        # Campos extra para modal de edición
        catalogo_servicio_id=str(ps.catalogo_servicio_id) if ps.catalogo_servicio_id else None,
        fecha_programada=ps.fecha_programada.isoformat() if ps.fecha_programada else None,
        fecha_inicio=ps.fecha_inicio.isoformat() if ps.fecha_inicio else None,
        fecha_fin=ps.fecha_fin.isoformat() if ps.fecha_fin else None,
    )

# ── PATCH /operaciones/servicio/{id}/estado ───────────────────────────────────

@router.patch("/servicio/{servicio_id}/estado")
def actualizar_estado_servicio(
    servicio_id: str,
    body: ActualizarEstadoBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    estados_validos = {"Pendiente", "En_Proceso", "Completado", "Cancelado"}
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail="Estado inválido")

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == payload["empresa_id"],
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    ps.estado     = body.estado
    ps.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado": body.estado}


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

    proc.estado     = body.estado
    proc.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado": body.estado}


# ── POST /operaciones/procedimiento/{id}/evidencia ────────────────────────────

_ETAPAS_VALIDAS = {"antes", "durante", "despues"}


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

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == proc.proyecto_servicio_id
    ).first()

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
        url_cloudinary       = url,
        public_id_cloudinary = pub_id,
        etapa                = etapa,
        descripcion          = descripcion,
    )
    db.add(ev)

    proc.estado     = "completado"
    proc.updated_at = datetime.utcnow()
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

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

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

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

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
):
    empresa_id = payload["empresa_id"]

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

    return [{"id": r.id, "nombre": r.nombre, "unidad": r.unidad, "stock": int(r.stock)} for r in rows]


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
    c.drawString(50, h - 130, f"Fecha:    {fecha.strftime('%d/%m/%Y %H:%M')}")
    c.drawString(50, h - 150, f"Orden ID: {orden_id[:8]}...")

    c.setFont("Helvetica-Bold", 12)
    c.drawString(50, h - 190, "Evidencias fotográficas:")

    y = h - 215
    c.setFont("Helvetica", 10)
    for ev in evidencias:
        etapa    = ev.etapa.upper() if ev.etapa else ""
        fecha_ev = ev.fecha_captura.strftime("%d/%m/%Y %H:%M") if ev.fecha_captura else ""
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
                fecha=ev.fecha_captura.strftime("%d/%m/%Y %H:%M") if ev.fecha_captura else None,
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


# ── GET /operaciones/catalogo-servicios ───────────────────────────────────────

@router.get("/catalogo-servicios", response_model=list[CatalogoServicioOut])
def get_catalogo_servicios(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Lista de servicios activos del catálogo de la empresa."""
    empresa_id = payload["empresa_id"]
    items = (
        db.query(CatalogoServicio)
        .filter(CatalogoServicio.empresa_id == empresa_id, CatalogoServicio.activo == True)
        .order_by(CatalogoServicio.nombre.asc())
        .all()
    )
    return [
        CatalogoServicioOut(
            id=str(c.id),
            nombre=c.nombre,
            tipo_trabajo=c.tipo_trabajo or "",
            descripcion=c.descripcion,
        )
        for c in items
    ]


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
            grupo_actual = _grupo_nombre,         # HU-13: usado en alerta de conflicto de grupo
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

    # Construir la query base
    q = (
        db.query(Procedimiento)
        .filter(
            Procedimiento.responsable_id     == body.empleado_id,
            Procedimiento.estado.in_(["pendiente", "en_proceso"]),
            Procedimiento.fecha_inicio_tarea != None,
            Procedimiento.fecha_limite       != None,
            # Condición de solapamiento
            Procedimiento.fecha_inicio_tarea <= fecha_fin_dt,
            Procedimiento.fecha_limite       >= fecha_ini_dt,
        )
    )

    # Excluir procedimientos del mismo servicio (para modo editar)
    if body.excluir_servicio_id:
        q = q.filter(
            Procedimiento.proyecto_servicio_id != body.excluir_servicio_id
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
        zona_ejecucion=detalle.zona_ejecucion if detalle else None,
        alcance=detalle.alcance if detalle else None,
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

    # Verificar orden de trabajo único dentro de la empresa
    existe = db.query(Proyecto).filter(
        Proyecto.empresa_id    == empresa_id,
        Proyecto.orden_trabajo == body.orden_trabajo,
    ).first()
    if existe:
        raise HTTPException(
            status_code=409,
            detail=f"Ya existe un proyecto con la orden de trabajo '{body.orden_trabajo}'.",
        )

    proyecto_id = str(_uuid.uuid4())
    ahora = datetime.utcnow()

    nuevo = Proyecto(
        id                  = proyecto_id,
        empresa_id          = empresa_id,
        cliente_id          = body.cliente_id,
        orden_trabajo       = body.orden_trabajo,
        jefe_operaciones_id = jefe.id,
        nombre_proyecto     = body.nombre_proyecto,
        estado              = body.estado or "Pendiente",
        fecha_inicio        = _parse_date(body.fecha_inicio),
        fecha_fin_estimada  = _parse_date(body.fecha_fin_estimada),
        created_at          = ahora,
    )
    db.add(nuevo)
    db.flush()

    # Detalle del proyecto (zona + alcance)
    if body.zona_ejecucion or body.alcance:
        det = ProyectoDetalle(
            proyecto_id    = proyecto_id,
            empresa_id     = empresa_id,
            zona_ejecucion = body.zona_ejecucion or None,
            alcance        = body.alcance or "",
        )
        db.add(det)

    # Agregar al jefe como miembro del proyecto
    db.add(ProyectoMiembro(
        id               = str(_uuid.uuid4()),
        proyecto_id      = proyecto_id,
        empleado_id      = jefe.id,
        rol_proyecto     = "Jefe de Operaciones",
        fecha_asignacion = ahora.date(),
        activo           = True,
    ))

    db.commit()
    return {"ok": True, "id": proyecto_id}


# ── PATCH /operaciones/proyecto/{proyecto_id} ─────────────────────────────────

@router.patch("/proyecto/{proyecto_id}")
def actualizar_proyecto(
    proyecto_id: str,
    body:        ActualizarProyectoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Actualiza los campos de un proyecto y su detalle."""
    empresa_id = payload["empresa_id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    # Verificar unicidad de orden_trabajo si cambió
    if body.orden_trabajo and body.orden_trabajo != proyecto.orden_trabajo:
        existe = db.query(Proyecto).filter(
            Proyecto.empresa_id    == empresa_id,
            Proyecto.orden_trabajo == body.orden_trabajo,
            Proyecto.id            != proyecto_id,
        ).first()
        if existe:
            raise HTTPException(
                status_code=409,
                detail=f"Ya existe un proyecto con la orden de trabajo '{body.orden_trabajo}'.",
            )

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
    if body.orden_trabajo is not None:
        proyecto.orden_trabajo = body.orden_trabajo
    if body.estado is not None:
        proyecto.estado = body.estado
    if body.fecha_inicio is not None:
        proyecto.fecha_inicio = _parse_date(body.fecha_inicio)
    if body.fecha_fin_estimada is not None:
        proyecto.fecha_fin_estimada = _parse_date(body.fecha_fin_estimada)
    proyecto.updated_at = datetime.utcnow()

    # Actualizar o crear ProyectoDetalle
    if body.zona_ejecucion is not None or body.alcance is not None:
        det = db.query(ProyectoDetalle).filter(
            ProyectoDetalle.proyecto_id == proyecto_id
        ).first()
        if det:
            if body.zona_ejecucion is not None:
                det.zona_ejecucion = body.zona_ejecucion or None
            if body.alcance is not None:
                det.alcance = body.alcance or ""
            det.updated_at = datetime.utcnow()
        else:
            db.add(ProyectoDetalle(
                proyecto_id    = proyecto_id,
                empresa_id     = empresa_id,
                zona_ejecucion = body.zona_ejecucion or None,
                alcance        = body.alcance or "",
            ))

    db.commit()
    return {"ok": True}


# ── POST /operaciones/proyecto/{proyecto_id}/servicios ────────────────────────

@router.post("/proyecto/{proyecto_id}/servicios", status_code=status.HTTP_201_CREATED)
def crear_servicio(
    proyecto_id: str,
    body:        CrearServicioBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Agrega un nuevo servicio a un proyecto existente."""
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
        id                   = servicio_id,
        proyecto_id          = proyecto_id,
        empresa_id           = empresa_id,
        catalogo_servicio_id = body.catalogo_servicio_id,
        nombre               = body.nombre,
        descripcion          = body.descripcion or None,
        estado               = body.estado or "Pendiente",
        orden                = max_orden + 1,
        fecha_programada     = _parse_date(body.fecha_programada),
        fecha_inicio         = _parse_date(body.fecha_inicio),
        fecha_fin            = _parse_date(body.fecha_fin),
        created_at           = datetime.utcnow(),
    )
    db.add(nuevo)
    db.commit()
    return {"ok": True, "id": servicio_id}


# ── PATCH /operaciones/servicio/{servicio_id} ─────────────────────────────────

@router.patch("/servicio/{servicio_id}")
def actualizar_servicio(
    servicio_id: str,
    body:        ActualizarServicioBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Actualiza los metadatos de un servicio (nombre, catálogo, fechas, estado, descripción)."""
    empresa_id = payload["empresa_id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

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

    ps.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True}


# ── POST /operaciones/servicio/{servicio_id}/configurar ───────────────────────

@router.post("/servicio/{servicio_id}/configurar")
def configurar_servicio(
    servicio_id: str,
    body:        ConfigurarServicioBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """
    Configura un servicio:
    - Asigna / actualiza el equipo técnico (ProyectoMiembro).
    - Reemplaza el cronograma de procedimientos (Procedimiento).
    """
    empresa_id = payload["empresa_id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

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

    # ── 2. Procedimientos / Cronograma ────────────────────────────────────────
    # Eliminar procedimientos existentes del servicio y recrèarlos
    db.query(Procedimiento).filter(
        Procedimiento.proyecto_servicio_id == servicio_id
    ).delete(synchronize_session=False)

    for i, proc in enumerate(body.procedimientos, start=1):
        # Verificar que el responsable está en el equipo o es el jefe
        if proc.responsable_id not in equipo_ids and proc.responsable_id != (jefe_id or ""):
            # Permisivo: si no está en la lista exacta, lo aceptamos de todas formas
            # (puede ser el jefe que no figura en equipo_ids)
            pass

        db.add(Procedimiento(
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
    # Determinar el responsable del servicio:
    #   a) Usar body.lider_id si el frontend lo envía explícitamente, O
    #   b) Derivar desde el JWT (usuario que está configurando el servicio)
    lider_empleado_id: str | None = None

    if body.lider_id:
        # Verificar que pertenece a la empresa
        emp_lider = db.query(Empleado).filter(
            Empleado.id         == body.lider_id,
            Empleado.empresa_id == empresa_id,
        ).first()
        if emp_lider:
            lider_empleado_id = str(emp_lider.id)
    else:
        # Fallback: buscar el empleado del usuario autenticado
        usuario_id = payload.get("id", "")
        emp_lider = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id,
            Empleado.empresa_id == empresa_id,
            Empleado.activo     == True,
        ).first()
        if emp_lider:
            lider_empleado_id = str(emp_lider.id)

    if lider_empleado_id:
        # Asignar como responsable del servicio
        ps.responsable_id = lider_empleado_id
        # Asignar como jefe de operaciones del proyecto si no tenía uno
        if proyecto and not proyecto.jefe_operaciones_id:
            proyecto.jefe_operaciones_id = lider_empleado_id

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

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id         == servicio_id,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    registrador = _get_jefe_empleado(db, usuario_id, empresa_id)
    if not registrador:
        raise HTTPException(
            status_code=422,
            detail="No hay empleados registrados en la empresa.",
        )

    # Calcular el progreso actual del servicio
    total_procs  = db.query(func.count(Procedimiento.id)).filter(
        Procedimiento.proyecto_servicio_id == servicio_id
    ).scalar() or 0
    completos    = db.query(func.count(Procedimiento.id)).filter(
        Procedimiento.proyecto_servicio_id == servicio_id,
        Procedimiento.estado               == "completado",
    ).scalar() or 0
    pct = round(completos / total_procs * 100, 2) if total_procs else 0.0

    nota = SeguimientoProyecto(
        id                = str(_uuid.uuid4()),
        proyecto_id       = ps.proyecto_id,
        empresa_id        = empresa_id,
        porcentaje_avance = pct,
        descripcion       = body.descripcion,
        fecha             = date.today(),
        registrado_por    = registrador.id,
        created_at        = datetime.utcnow(),
    )
    db.add(nota)
    db.commit()

    return {"ok": True, "nota_id": nota.id}
