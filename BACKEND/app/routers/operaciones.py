"""
Router: /operaciones
Gestión completa del módulo de Operaciones / Detalle de Servicio.
"""
from __future__ import annotations

import re
import uuid as _uuid
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..services.cloudinary_service import subir_archivo_cloudinary

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
from ..models.seguimiento_proyecto import SeguimientoProyecto

# Schemas Pydantic
from ..schemas.operaciones import (
    ServicioDetalleOut,
    MiembroEquipoOut,
    ProcedimientoOut,
    EvidenciaOut,
    ItemMaterialOut,
    NotaOut,
    ActualizarEstadoBody,
    ActualizarProcedimientoBody,
    SolicitarMaterialBody,
    ActualizarReqDetalleBody,
    AgregarNotaBody,
)

router = APIRouter(prefix="/operaciones", tags=["operaciones"])


# ── Helpers ───────────────────────────────────────────────────────────────────

def _parse_fecha(fecha_str: Optional[str]) -> date:
    if not fecha_str:
        return date.today()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M:%S.%f"):
        try:
            return datetime.strptime(fecha_str, fmt).date()
        except ValueError:
            continue
    raise HTTPException(status_code=400, detail="Formato de fecha inválido. Use YYYY-MM-DD o DD/MM/YYYY")


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


# ── GET /operaciones/dashboard ────────────────────────────────────────────────

@router.get("/dashboard")
def get_dashboard(
    fecha: Optional[str] = None,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    fecha_dt   = _parse_fecha(fecha)
    hoy        = date.today()

    # Subquery: proyectos donde el usuario es miembro activo
    miembro_subq = (
        db.query(ProyectoMiembro.proyecto_id)
        .join(Empleado, Empleado.id == ProyectoMiembro.empleado_id)
        .filter(
            Empleado.usuario_id  == usuario_id,
            ProyectoMiembro.activo == True,
        )
        .subquery()
    )

    # Servicios del día seleccionado.
    # Se filtra por Proyecto.fecha_inicio para quedar sincronizado con el
    # calendario (dashboard.py), que también usa ese campo para marcar días.
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
            ProyectoServicio.empresa_id      == empresa_id,
            Proyecto.fecha_inicio            == fecha_dt,
            ProyectoServicio.proyecto_id.in_(miembro_subq),
        )
        .order_by(Proyecto.fecha_inicio.asc(), ProyectoServicio.orden.asc())
        .all()
    )

    _estado_map = {"Pendiente": "Pendiente", "En_Proceso": "Activo", "Completado": "Completado"}
    pendientes = activos = hechos = 0
    servicios: list[dict] = []

    for row in rows:
        ps          = row.ProyectoServicio
        est_raw     = ps.estado or "Pendiente"
        est_fe      = _estado_map.get(est_raw, est_raw)
        fecha_proy  = row.fecha_proyecto          # Proyecto.fecha_inicio — misma que el calendario
        hora_svc    = ps.fecha_programada          # fecha_programada solo para extraer la hora

        if est_raw == "Pendiente":    pendientes += 1
        elif est_raw == "En_Proceso": activos    += 1
        elif est_raw == "Completado": hechos     += 1

        alerta = est_raw == "Pendiente" and fecha_proy is not None and fecha_proy < hoy

        servicios.append({
            "id":           ps.id,
            "cliente":      row.cliente,
            "tipoServicio": ps.nombre,
            "ubicacion":    row.ubicacion or "",
            "fechaStr":     fecha_proy.strftime("%d %b %Y") if fecha_proy else "Sin fecha",
            "horaStr":      hora_svc.strftime("%I:%M %p") if hora_svc else "--:--",
            "estado":       est_fe,
            "alerta":       alerta,
        })

    # Conteo de hoy (siempre TODAY) — también por Proyecto.fecha_inicio
    if fecha_dt != hoy:
        hoy_count = (
            db.query(func.count(ProyectoServicio.id.distinct()))
            .join(Proyecto, Proyecto.id == ProyectoServicio.proyecto_id)
            .filter(
                ProyectoServicio.empresa_id      == empresa_id,
                Proyecto.fecha_inicio            == hoy,
                ProyectoServicio.proyecto_id.in_(miembro_subq),
            )
            .scalar() or 0
        )
    else:
        hoy_count = len(rows)

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

    # 2. Verificar membresía
    miembro = (
        db.query(ProyectoMiembro)
        .join(Empleado, Empleado.id == ProyectoMiembro.empleado_id)
        .filter(
            ProyectoMiembro.proyecto_id == ps.proyecto_id,
            Empleado.usuario_id         == usuario_id,
        )
        .first()
    )
    if not miembro:
        raise HTTPException(status_code=403, detail="No tienes acceso a este servicio")

    fp        = ps.fecha_programada
    fecha_str = fp.strftime("%d %b %Y") if fp else "Sin fecha"
    hora_str  = fp.strftime("%I:%M %p") if fp else "--:--"

    # 3. Equipo de trabajo
    equipo_rows = (
        db.query(Usuario, Empleado.cargo, ProyectoMiembro.rol_proyecto)
        .join(Empleado,       Empleado.id  == ProyectoMiembro.empleado_id)
        .join(Usuario,        Usuario.id   == Empleado.usuario_id)
        .filter(
            ProyectoMiembro.proyecto_id == ps.proyecto_id,
            ProyectoMiembro.activo      == True,
        )
        .all()
    )

    # 🔥 FIX PYDANTIC: Blindaje en Equipo (Evita crash por usuarios sin apellido o foto)
    equipo = [
        MiembroEquipoOut(
            id=str(r.Usuario.id),
            nombre=r.Usuario.nombre or "",
            apellido=r.Usuario.apellido or "",
            foto_url=r.Usuario.foto_url or "",
            cargo=r.cargo or "Sin Cargo",
            rol_proyecto=r.rol_proyecto or "Técnico",
        )
        for r in equipo_rows
    ]

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
        # 🔥 FIX PYDANTIC: Blindaje en Evidencias
        ev_by_proc.setdefault(ev.procedimiento_id, []).append(
            EvidenciaOut(
                id=str(ev.id),
                url_cloudinary=ev.url_cloudinary or "",
                descripcion=ev.descripcion or "",
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
        )
        for p in procs
    ]

    total     = len(procedimientos)
    completos = sum(1 for p in procedimientos if p.estado == "completado")
    progreso  = round(completos / total * 100, 1) if total else 0.0

    # 5. Materiales
    mat_rows = (
        db.query(
            RequerimientoDetalle,
            Requerimiento.id.label("req_id"),
            Requerimiento.estado.label("req_estado"),
            Material.nombre.label("mat_nombre"),
            Material.unidad.label("mat_unidad"),
        )
        .join(Requerimiento, Requerimiento.id  == RequerimientoDetalle.requerimiento_id)
        .join(Material,      Material.id        == RequerimientoDetalle.material_id)
        .filter(
            Requerimiento.proyecto_servicio_id == servicio_id,
            Requerimiento.empresa_id           == empresa_id,
            Requerimiento.tipo                 == "material",
        )
        .order_by(Requerimiento.created_at.asc())
        .all()
    )

    mat_asignados: list[ItemMaterialOut]   = []
    mat_solicitados: list[ItemMaterialOut] = []

    for m in mat_rows:
        rd = m.RequerimientoDetalle
        # 🔥 FIX PYDANTIC: Blindaje en Materiales
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

    # 6. Notas / seguimiento
    nota_rows = (
        db.query(
            SeguimientoProyecto,
            (Usuario.nombre + " " + Usuario.apellido).label("autor"),
        )
        .join(Empleado, Empleado.id == SeguimientoProyecto.registrado_por)
        .join(Usuario,  Usuario.id  == Empleado.usuario_id)
        .filter(
            SeguimientoProyecto.proyecto_id == ps.proyecto_id,
            SeguimientoProyecto.empresa_id  == empresa_id,
        )
        .order_by(SeguimientoProyecto.fecha.asc(), SeguimientoProyecto.created_at.asc())
        .all()
    )

    # 🔥 FIX PYDANTIC: Blindaje en Notas
    notas = [
        NotaOut(
            id=str(n.SeguimientoProyecto.id),
            fecha=(
                n.SeguimientoProyecto.fecha.strftime("%I:%M %p")
                if isinstance(n.SeguimientoProyecto.fecha, datetime)
                else str(n.SeguimientoProyecto.fecha)
            ),
            texto=n.SeguimientoProyecto.descripcion or "",
            autor=n.autor or "Usuario Desconocido",
        )
        for n in nota_rows
    ]

    # 🔥 FIX PYDANTIC PRINCIPAL: Servicio Detalle Out
    return ServicioDetalleOut(
        id=str(ps.id),
        proyecto_id=str(ps.proyecto_id),
        cliente=cliente.razon_social if cliente and cliente.razon_social else "Cliente Sin Nombre",
        tipo_servicio=ps.nombre or "Servicio Técnico",
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
        notas=notas,
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

@router.post("/procedimiento/{proc_id}/evidencia", status_code=status.HTTP_201_CREATED)
async def subir_evidencia(
    proc_id:     str,
    archivo:     UploadFile = File(...),
    descripcion: str        = Form(default=""),
    payload:     dict       = Depends(verificar_token),
    db:          Session    = Depends(get_db),
):
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
        etapa                = "durante",
        descripcion          = descripcion,
    )
    db.add(ev)

    proc.estado     = "completado"
    proc.updated_at = datetime.utcnow()
    db.commit()

    return {"ok": True, "evidencia_id": ev.id, "url": url}


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

    rd = db.query(RequerimientoDetalle).filter(RequerimientoDetalle.id == rd_id).first()
    if not rd:
        raise HTTPException(status_code=404, detail="Detalle no encontrado")

    if body.cantidad is not None:
        rd.cantidad = body.cantidad
        db.commit()

    return {"ok": True}


# ── POST /operaciones/servicio/{id}/nota ──────────────────────────────────────

@router.post("/servicio/{servicio_id}/nota", status_code=status.HTTP_201_CREATED)
def agregar_nota(
    servicio_id: str,
    body: AgregarNotaBody,
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

    total_procs = (
        db.query(func.count(Procedimiento.id))
        .filter(Procedimiento.proyecto_servicio_id == servicio_id)
        .scalar() or 0
    )
    completos = (
        db.query(func.count(Procedimiento.id))
        .filter(
            Procedimiento.proyecto_servicio_id == servicio_id,
            Procedimiento.estado               == "completado",
        )
        .scalar() or 0
    )
    progreso = round(completos / total_procs * 100, 2) if total_procs else 0.0

    nota = SeguimientoProyecto(
        id                = str(_uuid.uuid4()),
        proyecto_id       = ps.proyecto_id,
        empresa_id        = empresa_id,
        porcentaje_avance = progreso,
        descripcion       = body.descripcion,
        fecha             = date.today(),
        registrado_por    = empleado.id,
    )
    db.add(nota)
    db.commit()

    return {"ok": True, "nota_id": nota.id}


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
