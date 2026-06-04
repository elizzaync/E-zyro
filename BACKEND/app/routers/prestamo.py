"""
Router: /prestamos
Préstamo de equipos y herramientas (HU-FASE5). Flujo:
  técnico solicitado → logística entregado → técnico devuelto → logística confirmado

Las solicitudes se vinculan a un `proyecto_servicio_id` (NO a proyecto).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import datetime, date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, case
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db

from ..models.prestamo import Prestamo, PrestamoItem
from ..models.equipo import Equipo
from ..models.almacen import Almacen
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.proyecto_servicio import ProyectoServicio
from ..models.proyecto import Proyecto
from ..models.proyecto_miembro import ProyectoMiembro
from ..models.notificacion import Notificacion
from ..models.requerimiento import Requerimiento, RequerimientoDetalle

from ..schemas.prestamo import (
    EquipoCatalogoOut,
    CrearPrestamoBody,
    EntregarPrestamoBody,
    DevolverPrestamoBody,
    ConfirmarDevolucionBody,
    RechazarPrestamoBody,
    PrestamoOut, PrestamoItemOut, PrestamoAvisoOut,
)


router = APIRouter(prefix="/prestamos", tags=["prestamos"])


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

def _autorizar_logistica(payload: dict) -> None:
    rol = (payload.get("rol") or "").lower().strip()
    if rol in ("logística", "logistica", "logístico", "logistico",
               "administrador", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Sin permiso para operar como logística")


def _empleado_or_403(db: Session, payload: dict) -> Empleado:
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == payload["id"],
        Empleado.empresa_id == payload["empresa_id"],
    ).first()
    if not emp:
        raise HTTPException(status_code=403, detail="Tu usuario no está registrado como empleado")
    return emp


def _nombre_empleado(db: Session, empleado_id: Optional[str]) -> str:
    if not empleado_id:
        return ""
    row = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == empleado_id)
        .first()
    )
    return f"{row[0]} {row[1]}".strip() if row else ""


def _prestamos_activos_por_equipo(db: Session, empresa_id: str) -> dict[str, int]:
    """Suma de cantidades en préstamos NO cerrados (estados solicitado/entregado/devuelto),
    agrupado por equipo_id. Usado para calcular disponibilidad."""
    rows = (
        db.query(
            PrestamoItem.equipo_id,
            func.sum(
                case(
                    (Prestamo.estado == "entregado", func.coalesce(PrestamoItem.cantidad_entregada,
                                                                    PrestamoItem.cantidad_solicitada)),
                    (Prestamo.estado == "solicitado", PrestamoItem.cantidad_solicitada),
                    (Prestamo.estado == "devuelto",
                        func.coalesce(PrestamoItem.cantidad_entregada,
                                      PrestamoItem.cantidad_solicitada)
                        - func.coalesce(PrestamoItem.cantidad_devuelta, 0)),
                    else_=0,
                )
            ).label("activos"),
        )
        .join(Prestamo, Prestamo.id == PrestamoItem.prestamo_id)
        .filter(
            Prestamo.empresa_id == empresa_id,
            Prestamo.estado.in_(("solicitado", "entregado", "devuelto")),
        )
        .group_by(PrestamoItem.equipo_id)
        .all()
    )
    return {r.equipo_id: int(r.activos or 0) for r in rows}


def _crear_requerimiento_faltante(
    db: Session,
    srv: ProyectoServicio,
    emp: Empleado,
    empresa_id: str,
    faltantes: list[tuple[Equipo, int]],
) -> str:
    """Crea un requerimiento de COMPRA para el faltante de stock de un préstamo.

    Cada ítem va como texto libre (sin material_id) clasificado por su clase
    (herramienta|equipo). Entra a la bandeja de Logística como 'pendiente';
    al aprobarse, por ser texto libre va a compra → ticket → vincular-inventario
    crea la fila en `equipo` → queda disponible para préstamo.
    """
    hay_equipo = any((eq.clase or "equipo") == "equipo" for eq, _ in faltantes)
    req = Requerimiento(
        id=str(_uuid.uuid4()),
        proyecto_id=srv.proyecto_id,
        proyecto_servicio_id=srv.id,
        empresa_id=empresa_id,
        solicitante_id=emp.id,
        tipo="equipo_especial" if hay_equipo else "herramienta",
        estado="pendiente",
        fecha=date.today(),
        observacion="Compra por faltante de stock (solicitado desde Préstamos)",
        created_at=datetime.utcnow(),
    )
    db.add(req)
    db.flush()

    for eq, faltante in faltantes:
        clase = eq.clase or "equipo"
        db.add(RequerimientoDetalle(
            id=str(_uuid.uuid4()),
            requerimiento_id=req.id,
            material_id=None,
            equipo_id=str(eq.id),   # enlaza con el equipo EXISTENTE → al recibir, reabastece (no crea nuevo)
            cantidad=int(faltante),
            nombre_libre=eq.nombre,
            unidad_libre="Unidad",
            especificacion=f"[{clase}] {eq.codigo or ''}".strip(),
            tipo_item_compra="herramienta" if clase == "herramienta" else "equipo",
            estado_item="pendiente",
            agregado_por_id=str(emp.id),
        ))
    return str(req.id)


def _prestamo_out(db: Session, p: Prestamo) -> PrestamoOut:
    items_rows = (
        db.query(PrestamoItem, Equipo.nombre, Equipo.codigo, Equipo.clase)
        .outerjoin(Equipo, Equipo.id == PrestamoItem.equipo_id)
        .filter(PrestamoItem.prestamo_id == p.id)
        .all()
    )
    items = [
        PrestamoItemOut(
            id=str(it.PrestamoItem.id),
            equipo_id=str(it.PrestamoItem.equipo_id),
            equipo_nombre=it.nombre or "—",
            equipo_codigo=it.codigo,
            clase=it.clase or "equipo",
            cantidad_solicitada=int(it.PrestamoItem.cantidad_solicitada or 0),
            cantidad_entregada=it.PrestamoItem.cantidad_entregada,
            cantidad_devuelta=it.PrestamoItem.cantidad_devuelta,
            cantidad_perdida=int(it.PrestamoItem.cantidad_perdida or 0),
            observacion=it.PrestamoItem.observacion,
        )
        for it in items_rows
    ]

    srv = db.query(ProyectoServicio).filter(ProyectoServicio.id == p.proyecto_servicio_id).first()
    servicio_nombre = srv.nombre if srv else None
    proyecto_nombre = None
    if srv and srv.proyecto_id:
        proy = db.query(Proyecto).filter(Proyecto.id == srv.proyecto_id).first()
        proyecto_nombre = proy.nombre_proyecto if proy else None

    def _fmt(d):
        return d.strftime("%Y-%m-%d %H:%M") if d else None

    return PrestamoOut(
        id=str(p.id),
        servicio_id=str(p.proyecto_servicio_id),
        servicio_nombre=servicio_nombre,
        proyecto_nombre=proyecto_nombre,
        solicitante_id=str(p.solicitante_id),
        solicitante_nombre=_nombre_empleado(db, p.solicitante_id) or "—",
        estado=p.estado,
        observacion=p.observacion,
        observacion_logistico=p.observacion_logistico,
        entregado_por_nombre=_nombre_empleado(db, p.entregado_por_id) or None,
        devuelto_por_nombre=_nombre_empleado(db, p.devuelto_por_id) or None,
        confirmado_por_nombre=_nombre_empleado(db, p.confirmado_por_id) or None,
        fecha_solicitud=_fmt(p.fecha_solicitud) or "",
        fecha_entrega=_fmt(p.fecha_entrega),
        fecha_devolucion=_fmt(p.fecha_devolucion),
        fecha_confirmacion=_fmt(p.fecha_confirmacion),
        items=items,
    )


def _usuarios_de_servicio(db: Session, proyecto_servicio_id) -> list[str]:
    """usuario_id de los miembros activos del proyecto al que pertenece el servicio.

    Se usa para acotar las notificaciones a quienes participan en el proyecto.
    """
    if not proyecto_servicio_id:
        return []
    ps = db.query(ProyectoServicio).filter(ProyectoServicio.id == proyecto_servicio_id).first()
    if not ps or not ps.proyecto_id:
        return []
    rows = (
        db.query(Empleado.usuario_id)
        .join(ProyectoMiembro, ProyectoMiembro.empleado_id == Empleado.id)
        .filter(
            ProyectoMiembro.proyecto_id == str(ps.proyecto_id),
            ProyectoMiembro.activo.is_(True),
            Empleado.usuario_id.isnot(None),
        )
        .all()
    )
    return [r[0] for r in rows if r[0]]


def _notificar(db: Session, empresa_id: str, usuario_id: str, titulo: str, mensaje: str,
               referencia_id: str | None = None) -> None:
    try:
        db.add(Notificacion(
            id=str(_uuid.uuid4()), empresa_id=empresa_id, usuario_id=usuario_id,
            tipo="info", categoria="prestamos",
            titulo=titulo, mensaje=mensaje,
            leido=False, enviado=False,
            referencia_tabla="prestamo", referencia_id=referencia_id,
        ))
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────
# GET /prestamos/equipos-catalogo — catálogo de equipos/herramientas
# ─────────────────────────────────────────────────────────────────────────

@router.get("/equipos-catalogo", response_model=List[EquipoCatalogoOut])
def equipos_catalogo(
    q:       str = Query("", description="texto en nombre/código"),
    clase:   str = Query("", description="equipo | herramienta | (vacío = ambos)"),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    base = (
        db.query(Equipo, Almacen.nombre.label("almacen_nombre"))
        .outerjoin(Almacen, Almacen.id == Equipo.almacen_id)
        .filter(Equipo.empresa_id == empresa_id)
    )
    if q.strip():
        like = f"%{q.lower().strip()}%"
        base = base.filter(or_(
            func.lower(Equipo.nombre).like(like),
            func.lower(Equipo.codigo).like(like),
        ))
    if clase in ("equipo", "herramienta"):
        base = base.filter(Equipo.clase == clase)

    rows = base.order_by(Equipo.nombre).all()
    activos = _prestamos_activos_por_equipo(db, empresa_id)

    return [
        EquipoCatalogoOut(
            id=str(r.Equipo.id),
            codigo=r.Equipo.codigo,
            nombre=r.Equipo.nombre,
            clase=r.Equipo.clase or "equipo",
            tipo=r.Equipo.tipo,
            marca=r.Equipo.marca,
            modelo=r.Equipo.modelo,
            almacen_nombre=r.almacen_nombre,
            cantidad_total=int(r.Equipo.cantidad or 0),
            cantidad_disponible=max(0, int(r.Equipo.cantidad or 0) - activos.get(r.Equipo.id, 0)),
            requiere_mantenimiento=bool(r.Equipo.requiere_mantenimiento),
        )
        for r in rows
    ]


# ─────────────────────────────────────────────────────────────────────────
# POST /prestamos/servicio/{servicio_id} — crear préstamo (técnico)
# ─────────────────────────────────────────────────────────────────────────

@router.post("/servicio/{servicio_id}", status_code=status.HTTP_201_CREATED)
def crear_prestamo(
    servicio_id: str,
    body:        CrearPrestamoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    emp = _empleado_or_403(db, payload)

    srv = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == servicio_id
    ).first()
    if not srv:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    if not body.items:
        raise HTTPException(status_code=422, detail="Agrega al menos un equipo")

    # Disponibilidad actual por equipo (para dividir préstamo vs compra del faltante)
    activos = _prestamos_activos_por_equipo(db, empresa_id)

    p = Prestamo(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        proyecto_servicio_id=servicio_id,
        solicitante_id=emp.id,
        estado="solicitado",
        observacion=body.observacion,
        fecha_solicitud=datetime.utcnow(),
    )
    db.add(p)
    db.flush()

    faltantes: list[tuple[Equipo, int]] = []
    hubo_prestamo = False

    for it in body.items:
        equipo = db.query(Equipo).filter(
            Equipo.id == it.equipo_id, Equipo.empresa_id == empresa_id
        ).first()
        if not equipo:
            raise HTTPException(status_code=404, detail=f"Equipo {it.equipo_id} no encontrado")
        if it.cantidad <= 0:
            raise HTTPException(status_code=422, detail="Cantidad debe ser > 0")

        # Se presta lo disponible; el excedente se solicita a compra.
        disponible = max(0, int(equipo.cantidad or 0) - activos.get(equipo.id, 0))
        a_prestar  = min(int(it.cantidad), disponible)
        faltante   = int(it.cantidad) - a_prestar

        if a_prestar > 0:
            db.add(PrestamoItem(
                id=str(_uuid.uuid4()), prestamo_id=p.id,
                equipo_id=it.equipo_id, cantidad_solicitada=a_prestar,
            ))
            hubo_prestamo = True
        if faltante > 0:
            faltantes.append((equipo, faltante))

    # Compra del faltante (si lo hay) → requerimiento a Logística
    requerimiento_id = None
    if faltantes:
        requerimiento_id = _crear_requerimiento_faltante(db, srv, emp, empresa_id, faltantes)

    # Si todo fue a compra (nada disponible para prestar), no dejamos un
    # préstamo vacío: lo eliminamos antes de commit.
    if not hubo_prestamo:
        db.delete(p)

    db.commit()

    return {
        "ok": True,
        "prestamo_id": str(p.id) if hubo_prestamo else None,
        "requerimiento_id": requerimiento_id,
        "faltantes": [
            {"equipo": eq.nombre, "cantidad": f} for eq, f in faltantes
        ],
    }


# ─────────────────────────────────────────────────────────────────────────
# GET /prestamos/servicio/{servicio_id} — listar préstamos del servicio
# ─────────────────────────────────────────────────────────────────────────

@router.get("/servicio/{servicio_id}", response_model=List[PrestamoOut])
def listar_por_servicio(
    servicio_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Prestamo)
        .filter(
            Prestamo.empresa_id == empresa_id,
            Prestamo.proyecto_servicio_id == servicio_id,
        )
        .order_by(Prestamo.created_at.desc())
        .all()
    )
    return [_prestamo_out(db, p) for p in rows]


# ─────────────────────────────────────────────────────────────────────────
# GET /prestamos — bandeja de logística (filtra por estado)
# ─────────────────────────────────────────────────────────────────────────

@router.get("", response_model=List[PrestamoOut])
def listar_prestamos(
    estado:  str = Query("todos", description="todos|solicitado|entregado|devuelto|confirmado|rechazado"),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    base = db.query(Prestamo).filter(Prestamo.empresa_id == empresa_id)
    if estado and estado != "todos":
        base = base.filter(Prestamo.estado == estado)
    rows = base.order_by(Prestamo.created_at.desc()).limit(200).all()
    return [_prestamo_out(db, p) for p in rows]


# ─────────────────────────────────────────────────────────────────────────
# GET /prestamos/avisos/sin-confirmar — banner del detalle de servicio
# Préstamos del servicio que están en estado 'devuelto' (esperando confirmación log)
# ─────────────────────────────────────────────────────────────────────────

@router.get("/servicio/{servicio_id}/avisos", response_model=List[PrestamoAvisoOut])
def avisos_servicio(
    servicio_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Prestamo.id, Prestamo.estado, Prestamo.fecha_devolucion,
                 func.count(PrestamoItem.id).label("n"))
        .outerjoin(PrestamoItem, PrestamoItem.prestamo_id == Prestamo.id)
        .filter(
            Prestamo.empresa_id == empresa_id,
            Prestamo.proyecto_servicio_id == servicio_id,
            Prestamo.estado == "devuelto",
        )
        .group_by(Prestamo.id)
        .all()
    )
    return [
        PrestamoAvisoOut(
            id=str(r.id),
            servicio_id=servicio_id,
            estado=r.estado,
            fecha_devolucion=r.fecha_devolucion.strftime("%Y-%m-%d %H:%M") if r.fecha_devolucion else None,
            total_items=int(r.n or 0),
        )
        for r in rows
    ]


# ─────────────────────────────────────────────────────────────────────────
# POST /prestamos/{id}/entregar — logística entrega (estado → entregado)
# ─────────────────────────────────────────────────────────────────────────

@router.post("/{prestamo_id}/entregar", response_model=PrestamoOut)
def entregar_prestamo(
    prestamo_id: str,
    body:        EntregarPrestamoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    emp = _empleado_or_403(db, payload)

    p = db.query(Prestamo).filter(
        Prestamo.id == prestamo_id, Prestamo.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    if p.estado != "solicitado":
        raise HTTPException(status_code=409, detail="El préstamo no está pendiente de entrega")

    decisiones = {d.item_id: d.cantidad_entregada for d in body.items}

    items = db.query(PrestamoItem).filter(PrestamoItem.prestamo_id == p.id).all()
    for it in items:
        cant = decisiones.get(str(it.id))
        it.cantidad_entregada = int(cant) if cant is not None else int(it.cantidad_solicitada)

    p.estado = "entregado"
    p.entregado_por_id = emp.id
    p.fecha_entrega = datetime.utcnow()
    p.updated_at = datetime.utcnow()
    if body.observacion:
        p.observacion_logistico = body.observacion

    # Notificar al solicitante
    sol_row = db.query(Empleado.usuario_id).filter(Empleado.id == p.solicitante_id).first()
    if sol_row:
        _notificar(db, empresa_id, sol_row[0],
                   "Equipos entregados",
                   "Logística entregó los equipos de tu préstamo.",
                   referencia_id=p.id)

    db.commit()
    db.refresh(p)
    return _prestamo_out(db, p)


# ─────────────────────────────────────────────────────────────────────────
# POST /prestamos/{id}/rechazar — logística rechaza
# ─────────────────────────────────────────────────────────────────────────

@router.post("/{prestamo_id}/rechazar", response_model=PrestamoOut)
def rechazar_prestamo(
    prestamo_id: str,
    body:        RechazarPrestamoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    p = db.query(Prestamo).filter(
        Prestamo.id == prestamo_id, Prestamo.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    if p.estado != "solicitado":
        raise HTTPException(status_code=409, detail="El préstamo ya fue procesado")

    p.estado = "rechazado"
    p.observacion_logistico = body.observacion
    p.updated_at = datetime.utcnow()

    sol_row = db.query(Empleado.usuario_id).filter(Empleado.id == p.solicitante_id).first()
    if sol_row:
        _notificar(db, empresa_id, sol_row[0],
                   "Préstamo rechazado",
                   f"Tu solicitud de equipos fue rechazada: {body.observacion}",
                   referencia_id=p.id)

    db.commit()
    db.refresh(p)
    return _prestamo_out(db, p)


# ─────────────────────────────────────────────────────────────────────────
# POST /prestamos/{id}/devolver — técnico devuelve (estado → devuelto)
# ─────────────────────────────────────────────────────────────────────────

@router.post("/{prestamo_id}/devolver", response_model=PrestamoOut)
def devolver_prestamo(
    prestamo_id: str,
    body:        DevolverPrestamoBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    emp = _empleado_or_403(db, payload)

    p = db.query(Prestamo).filter(
        Prestamo.id == prestamo_id, Prestamo.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    if p.estado != "entregado":
        raise HTTPException(status_code=409, detail="El préstamo no está en estado entregado")

    if not body.items:
        raise HTTPException(status_code=422, detail="Indica cuántas unidades devuelves de cada equipo")

    decisiones = {d.item_id: d for d in body.items}
    items = db.query(PrestamoItem).filter(PrestamoItem.prestamo_id == p.id).all()

    for it in items:
        d = decisiones.get(str(it.id))
        entregada = int(it.cantidad_entregada or it.cantidad_solicitada or 0)
        if d is None:
            # Si el técnico no reportó este item, asumimos devolución completa
            it.cantidad_devuelta = entregada
            it.cantidad_perdida  = 0
            continue
        devuelta = int(d.cantidad_devuelta or 0)
        if devuelta < 0 or devuelta > entregada:
            raise HTTPException(
                status_code=422,
                detail=f"Cantidad devuelta inválida (0..{entregada})",
            )
        it.cantidad_devuelta = devuelta
        it.cantidad_perdida  = entregada - devuelta
        if d.observacion:
            it.observacion = d.observacion

    p.estado = "devuelto"
    p.devuelto_por_id = emp.id
    p.fecha_devolucion = datetime.utcnow()
    p.updated_at = datetime.utcnow()
    if body.observacion:
        p.observacion = (p.observacion or "") + (f"\n[Devolución] {body.observacion}"
                                                  if p.observacion else body.observacion)

    # Notificar SOLO a los miembros del proyecto del servicio (no a toda la empresa).
    try:
        for uid in set(_usuarios_de_servicio(db, p.proyecto_servicio_id)):
            _notificar(db, empresa_id, uid,
                       "Devolución de préstamo pendiente",
                       "Un técnico devolvió equipos. Falta confirmar la recepción.",
                       referencia_id=p.id)
    except Exception:
        pass

    db.commit()
    db.refresh(p)
    return _prestamo_out(db, p)


# ─────────────────────────────────────────────────────────────────────────
# POST /prestamos/{id}/confirmar-devolucion — logística confirma
# ─────────────────────────────────────────────────────────────────────────

@router.post("/{prestamo_id}/confirmar-devolucion", response_model=PrestamoOut)
def confirmar_devolucion(
    prestamo_id: str,
    body:        ConfirmarDevolucionBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    emp = _empleado_or_403(db, payload)

    p = db.query(Prestamo).filter(
        Prestamo.id == prestamo_id, Prestamo.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    if p.estado != "devuelto":
        raise HTTPException(status_code=409, detail="El préstamo no está pendiente de confirmación")

    if body.aceptar:
        p.estado = "confirmado"
        p.confirmado_por_id = emp.id
        p.fecha_confirmacion = datetime.utcnow()
    else:
        # Rechazo de la devolución: queda 'devuelto' con observación; técnico debe corregir
        p.observacion_logistico = body.observacion or "Devolución observada por logística"

    p.updated_at = datetime.utcnow()
    if body.observacion and body.aceptar:
        p.observacion_logistico = body.observacion

    sol_row = db.query(Empleado.usuario_id).filter(Empleado.id == p.solicitante_id).first()
    if sol_row:
        _notificar(db, empresa_id, sol_row[0],
                   "Devolución confirmada" if body.aceptar else "Devolución observada",
                   ("Logística confirmó la recepción de tus equipos."
                    if body.aceptar
                    else f"Tu devolución necesita revisión: {body.observacion or 'sin detalle'}"),
                   referencia_id=p.id)

    db.commit()
    db.refresh(p)
    return _prestamo_out(db, p)
