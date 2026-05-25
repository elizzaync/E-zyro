"""
Router: /requerimientos
Catálogo de materiales y gestión de solicitudes (HU-17).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token, es_superadmin
from ..db.database import get_db

from ..models.material import Material, Stock
from ..models.categoria_material import CategoriaMaterial
from ..models.requerimiento import Requerimiento, RequerimientoDetalle
from ..models.requerimiento_entrega import RequerimientoEntrega
from ..models.movimiento_inventario import MovimientoInventario
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.proyecto import Proyecto

from ..models.almacen import Almacen
from ..models.auditoria import Auditoria
from ..schemas.requerimientos import (
    CatalogoItemOut,
    SolicitudDetalleOut,
    MiSolicitudOut,
    CrearSolicitudBody,
    CategoriaOut,
    AlmacenOut,
    CrearMaterialBody,
    InventarioResumenOut,
    MaterialBajoStockOut,
    SolicitudGestionOut,
    GestionarSolicitudBody,
    AjusteStockBody,
    MovimientoOut,
    EditarMaterialBody,
    CategoriaBody,
    TransferenciaBody,
)
import json as _json

router = APIRouter(prefix="/requerimientos", tags=["requerimientos"])


def _get_empleado_or_403(db: Session, usuario_id: str, empresa_id: str) -> Empleado:
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    if not emp:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")
    return emp


# ── GET /requerimientos/catalogo ──────────────────────────────────────────────

@router.get("/catalogo", response_model=List[CatalogoItemOut])
def get_catalogo(
    q:         str = "",
    categoria: str = "",     # HU-15: filtro por categoría
    page:      int = 1,      # HU-15: página (base 1)
    page_size: int = 30,     # HU-15: items por página
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    page_size = min(max(page_size, 1), 100)
    page      = max(page, 1)
    offset    = (page - 1) * page_size

    stock_sq = (
        db.query(
            Stock.material_id,
            func.sum(Stock.cantidad).label("total"),
            func.sum(Stock.cantidad_minima).label("minimo"),
        )
        .filter(Stock.empresa_id == empresa_id)
        .group_by(Stock.material_id)
        .subquery()
    )

    query = (
        db.query(
            Material.id,
            Material.nombre,
            Material.codigo,
            Material.unidad,
            Material.descripcion,
            CategoriaMaterial.nombre.label("categoria"),
            func.coalesce(stock_sq.c.total, 0).label("stock"),
            func.coalesce(stock_sq.c.minimo, 0).label("minimo"),
        )
        .outerjoin(stock_sq, stock_sq.c.material_id == Material.id)
        .outerjoin(CategoriaMaterial, CategoriaMaterial.id == Material.categoria_id)
        .filter(
            Material.empresa_id == empresa_id,
            Material.activo == True,
        )
    )

    if q:
        query = query.filter(
            (Material.nombre.ilike(f"%{q}%")) |
            (Material.codigo.ilike(f"%{q}%"))
        )

    if categoria:
        query = query.filter(CategoriaMaterial.nombre.ilike(f"%{categoria}%"))

    rows = (
        query
        .order_by(Material.nombre.asc())
        .offset(offset)
        .limit(page_size)
        .all()
    )

    return [
        CatalogoItemOut(
            id=r.id,
            nombre=r.nombre,
            codigo=r.codigo,
            unidad=r.unidad,
            stock=int(r.stock),
            stock_minimo=int(r.minimo or 0),
            categoria=r.categoria,
            descripcion=r.descripcion,
            imagen_url=None,
        )
        for r in rows
    ]


# ── GET /requerimientos/inventario/resumen ────────────────────────────────────
# Panel del encargado de logística: KPIs + alertas de bajo stock.

@router.get("/inventario/resumen", response_model=InventarioResumenOut)
def get_inventario_resumen(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    stock_sq = (
        db.query(
            Stock.material_id,
            func.sum(Stock.cantidad).label("total"),
            func.sum(Stock.cantidad_minima).label("minimo"),
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
            CategoriaMaterial.nombre.label("categoria"),
            func.coalesce(stock_sq.c.total, 0).label("stock"),
            func.coalesce(stock_sq.c.minimo, 0).label("minimo"),
        )
        .outerjoin(stock_sq, stock_sq.c.material_id == Material.id)
        .outerjoin(CategoriaMaterial, CategoriaMaterial.id == Material.categoria_id)
        .filter(
            Material.empresa_id == empresa_id,
            Material.activo == True,
        )
        .all()
    )

    total_items = len(rows)
    sin_stock = sum(1 for r in rows if int(r.stock) == 0)
    bajo = [
        r for r in rows
        if int(r.minimo or 0) > 0 and int(r.stock) <= int(r.minimo)
    ]
    bajo.sort(key=lambda r: (int(r.stock) - int(r.minimo)))

    return InventarioResumenOut(
        total_items=total_items,
        bajo_stock=len(bajo),
        sin_stock=sin_stock,
        items_bajo_stock=[
            MaterialBajoStockOut(
                id=str(r.id),
                nombre=r.nombre or "",
                unidad=r.unidad or "und",
                categoria=r.categoria,
                stock=int(r.stock),
                minimo=int(r.minimo or 0),
            )
            for r in bajo[:30]
        ],
    )


# ── Helpers de gestión de logística ───────────────────────────────────────────

def _puede_gestionar_logistica(payload: dict) -> bool:
    """Encargado de logística o administrador (coherente con canGestInventario)."""
    if es_superadmin(payload):
        return True
    rol = (payload.get("rol") or "").lower().strip()
    return "logist" in rol


def _build_solicitud_items(db: Session, req_ids: list[str]) -> dict[str, list]:
    """Devuelve {requerimiento_id: [SolicitudDetalleOut, ...]}."""
    rows = (
        db.query(
            RequerimientoDetalle,
            Material.nombre.label("mat_nombre"),
            Material.unidad.label("mat_unidad"),
        )
        .outerjoin(Material, Material.id == RequerimientoDetalle.material_id)
        .filter(RequerimientoDetalle.requerimiento_id.in_(req_ids))
        .all()
    )
    by_req: dict[str, list] = {}
    for row in rows:
        d = row.RequerimientoDetalle
        by_req.setdefault(d.requerimiento_id, []).append(
            SolicitudDetalleOut(
                id=str(d.id),
                material_id=str(d.material_id) if d.material_id else None,
                nombre=row.mat_nombre or d.nombre_libre or "",
                unidad=row.mat_unidad or d.unidad_libre or "",
                cantidad=d.cantidad or 0,
                cantidad_aprobada=d.cantidad_aprobada,
                nombre_libre=d.nombre_libre,
                unidad_libre=d.unidad_libre,
                especificacion=d.especificacion,
            )
        )
    return by_req


# ── GET /requerimientos/pendientes ────────────────────────────────────────────
# Bandeja del encargado: solicitudes de toda la empresa (excluye borradores).

@router.get("/pendientes", response_model=List[SolicitudGestionOut])
def get_solicitudes_pendientes(
    estado:  str = "",   # filtro opcional: pendiente | aprobado | rechazado | entregado
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    q = (
        db.query(Requerimiento)
        .filter(
            Requerimiento.empresa_id == empresa_id,
            Requerimiento.tipo       == "material",
            Requerimiento.estado     != "borrador",
        )
    )
    if estado:
        q = q.filter(Requerimiento.estado == estado)

    reqs = q.order_by(Requerimiento.created_at.desc()).all()
    if not reqs:
        return []

    req_ids      = [r.id for r in reqs]
    proyecto_ids = list({r.proyecto_id for r in reqs})
    solicitante_ids = list({r.solicitante_id for r in reqs if r.solicitante_id})

    proyectos_map = {
        p.id: p for p in db.query(Proyecto).filter(Proyecto.id.in_(proyecto_ids)).all()
    }

    # Nombre del solicitante (empleado → usuario)
    solicitante_map: dict[str, str] = {}
    if solicitante_ids:
        rows = (
            db.query(Empleado.id, Usuario.nombre, Usuario.apellido)
            .join(Usuario, Usuario.id == Empleado.usuario_id)
            .filter(Empleado.id.in_(solicitante_ids))
            .all()
        )
        solicitante_map = {
            r.id: f"{r.nombre or ''} {r.apellido or ''}".strip() or "Sin nombre"
            for r in rows
        }

    items_by_req = _build_solicitud_items(db, req_ids)

    result = []
    for req in reqs:
        proyecto = proyectos_map.get(req.proyecto_id)
        result.append(SolicitudGestionOut(
            id=str(req.id),
            estado=req.estado or "pendiente",
            fecha=req.fecha.strftime("%d %b %Y") if req.fecha else "",
            observacion=req.observacion,
            observacion_logistico=req.observacion_logistico,
            proyecto_nombre=(proyecto.nombre_proyecto if proyecto else "Proyecto") or "Proyecto",
            solicitante_nombre=solicitante_map.get(req.solicitante_id, "Sin nombre"),
            items=items_by_req.get(req.id, []),
        ))
    return result


# ── PATCH /requerimientos/{req_id}/gestionar ──────────────────────────────────
# Aprobar o rechazar una solicitud.

@router.patch("/{req_id}/gestionar")
def gestionar_solicitud(
    req_id:  str,
    body:    GestionarSolicitudBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    accion = (body.accion or "").lower().strip()
    if accion not in ("aprobar", "rechazar"):
        raise HTTPException(status_code=422, detail="Acción inválida")

    req = db.query(Requerimiento).filter(
        Requerimiento.id         == req_id,
        Requerimiento.empresa_id == empresa_id,
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if req.estado in ("entregado", "rechazado"):
        raise HTTPException(status_code=409, detail="La solicitud ya fue finalizada")

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()

    if accion == "aprobar":
        req.estado = "aprobado"
        # Aprobar la cantidad solicitada por defecto
        for d in db.query(RequerimientoDetalle).filter(
            RequerimientoDetalle.requerimiento_id == req.id
        ).all():
            if d.cantidad_aprobada is None:
                d.cantidad_aprobada = d.cantidad
    else:
        req.estado = "rechazado"

    if body.observacion_logistico:
        req.observacion_logistico = body.observacion_logistico
    if empleado:
        req.aprobado_por = empleado.id
    req.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado": req.estado}


# ── POST /requerimientos/{req_id}/entregar ────────────────────────────────────
# Marca como entregada: descuenta stock y registra la entrega.

@router.post("/{req_id}/entregar")
def entregar_solicitud(
    req_id:  str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    req = db.query(Requerimiento).filter(
        Requerimiento.id         == req_id,
        Requerimiento.empresa_id == empresa_id,
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if req.estado == "entregado":
        raise HTTPException(status_code=409, detail="La solicitud ya fue entregada")
    if req.estado == "rechazado":
        raise HTTPException(status_code=409, detail="La solicitud fue rechazada")

    detalles = db.query(RequerimientoDetalle).filter(
        RequerimientoDetalle.requerimiento_id == req.id
    ).all()

    # Descontar stock de cada material (del almacén con mayor cantidad disponible)
    for d in detalles:
        if not d.material_id:
            continue  # compra externa, sin stock interno
        pedida = d.cantidad_aprobada if d.cantidad_aprobada is not None else d.cantidad
        restante = pedida or 0
        stocks = (
            db.query(Stock)
            .filter(
                Stock.material_id == d.material_id,
                Stock.empresa_id  == empresa_id,
            )
            .order_by(Stock.cantidad.desc())
            .all()
        )
        for st in stocks:
            if restante <= 0:
                break
            quita = min(st.cantidad, restante)
            st.cantidad -= quita
            st.updated_at = datetime.utcnow()
            restante -= quita

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()

    entregado_por = empleado.id if empleado else None
    recibido_por  = req.solicitante_id or entregado_por
    if entregado_por and recibido_por:
        db.add(RequerimientoEntrega(
            requerimiento_id=req.id,
            empresa_id=empresa_id,
            entregado_por_id=entregado_por,
            recibido_por_id=recibido_por,
            fecha_entrega=datetime.utcnow(),
        ))

    req.estado = "entregado"
    req.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado": "entregado"}


# ── POST /requerimientos/inventario/ajuste ────────────────────────────────────
# Ajuste manual de stock (entrada/salida/ajuste exacto) — solo logística/admin.

@router.post("/inventario/ajuste")
def ajustar_stock(
    body:    AjusteStockBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    tipo = (body.tipo or "").lower().strip()
    if tipo not in ("entrada", "salida", "ajuste"):
        raise HTTPException(status_code=422, detail="Tipo inválido")
    if body.cantidad < 0:
        raise HTTPException(status_code=422, detail="La cantidad no puede ser negativa")
    if tipo in ("entrada", "salida") and body.cantidad < 1:
        raise HTTPException(status_code=422, detail="La cantidad debe ser mayor a 0")

    mat = db.query(Material).filter(
        Material.id         == body.material_id,
        Material.empresa_id == empresa_id,
        Material.activo     == True,
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    # Resolver almacén: el indicado, o el que ya tiene stock del material, o el principal.
    almacen_id = body.almacen_id
    stock = None
    if almacen_id:
        stock = db.query(Stock).filter(
            Stock.material_id == mat.id,
            Stock.empresa_id  == empresa_id,
            Stock.almacen_id  == almacen_id,
        ).first()
    else:
        stock = (
            db.query(Stock)
            .filter(Stock.material_id == mat.id, Stock.empresa_id == empresa_id)
            .order_by(Stock.cantidad.desc())
            .first()
        )
        if stock:
            almacen_id = stock.almacen_id
        else:
            alm = db.query(Almacen).filter(Almacen.empresa_id == empresa_id).first()
            if not alm:
                raise HTTPException(status_code=400, detail="No hay almacenes registrados")
            almacen_id = str(alm.id)

    # Crear fila de stock si no existe
    if stock is None:
        stock = Stock(
            material_id    = mat.id,
            empresa_id     = empresa_id,
            almacen_id     = almacen_id,
            cantidad       = 0,
            cantidad_minima= 0,
        )
        db.add(stock)
        db.flush()

    anterior = stock.cantidad or 0
    if tipo == "entrada":
        nuevo = anterior + body.cantidad
        mov_cantidad = body.cantidad
    elif tipo == "salida":
        if body.cantidad > anterior:
            raise HTTPException(
                status_code=409,
                detail=f"Stock insuficiente (disponible: {anterior})",
            )
        nuevo = anterior - body.cantidad
        mov_cantidad = body.cantidad
    else:  # ajuste exacto
        nuevo = body.cantidad
        mov_cantidad = abs(nuevo - anterior)

    stock.cantidad = nuevo
    stock.updated_at = datetime.utcnow()

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()

    db.add(MovimientoInventario(
        id              = str(_uuid.uuid4()),
        empresa_id      = empresa_id,
        material_id     = mat.id,
        almacen_id      = almacen_id,
        tipo            = tipo,
        cantidad        = mov_cantidad,
        motivo          = body.motivo,
        responsable_id  = empleado.id if empleado else None,
        fecha           = datetime.utcnow(),
    ))

    db.commit()
    return {"ok": True, "stock_anterior": anterior, "stock_actual": nuevo}


# ── GET /requerimientos/inventario/movimientos ────────────────────────────────
# Historial de movimientos (opcional filtro por material) — solo logística/admin.

@router.get("/inventario/movimientos", response_model=List[MovimientoOut])
def get_movimientos(
    material_id: str = "",
    limit:       int = 100,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    limit = min(max(limit, 1), 300)

    q = (
        db.query(
            MovimientoInventario,
            Material.nombre.label("mat_nombre"),
            Material.unidad.label("mat_unidad"),
            Almacen.nombre.label("alm_nombre"),
            Usuario.nombre.label("resp_nombre"),
            Usuario.apellido.label("resp_apellido"),
        )
        .join(Material, Material.id == MovimientoInventario.material_id)
        .outerjoin(Almacen, Almacen.id == MovimientoInventario.almacen_id)
        .outerjoin(Empleado, Empleado.id == MovimientoInventario.responsable_id)
        .outerjoin(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(MovimientoInventario.empresa_id == empresa_id)
    )
    if material_id:
        q = q.filter(MovimientoInventario.material_id == material_id)

    rows = q.order_by(MovimientoInventario.fecha.desc()).limit(limit).all()

    result = []
    for r in rows:
        m = r.MovimientoInventario
        responsable = f"{r.resp_nombre or ''} {r.resp_apellido or ''}".strip()
        result.append(MovimientoOut(
            id=str(m.id),
            material_id=str(m.material_id),
            material_nombre=r.mat_nombre or "",
            unidad=r.mat_unidad or "und",
            tipo=m.tipo or "",
            cantidad=m.cantidad or 0,
            motivo=m.motivo,
            almacen_nombre=r.alm_nombre,
            responsable_nombre=responsable or None,
            fecha=m.fecha.strftime("%d %b %Y · %H:%M") if m.fecha else "",
        ))
    return result


# ── POST /requerimientos/inventario/transferencia ─────────────────────────────
# Mueve stock de un almacén a otro — registra 2 movimientos (salida + entrada).

@router.post("/inventario/transferencia")
def transferir_stock(
    body:    TransferenciaBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    if body.cantidad < 1:
        raise HTTPException(status_code=422, detail="La cantidad debe ser mayor a 0")
    if body.almacen_origen_id == body.almacen_destino_id:
        raise HTTPException(status_code=422, detail="El origen y destino deben ser distintos")

    mat = db.query(Material).filter(
        Material.id         == body.material_id,
        Material.empresa_id == empresa_id,
        Material.activo     == True,
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    almacenes = {
        str(a.id): a
        for a in db.query(Almacen).filter(
            Almacen.id.in_([body.almacen_origen_id, body.almacen_destino_id]),
            Almacen.empresa_id == empresa_id,
        ).all()
    }
    origen = almacenes.get(body.almacen_origen_id)
    destino = almacenes.get(body.almacen_destino_id)
    if not origen or not destino:
        raise HTTPException(status_code=404, detail="Almacén no encontrado")

    # Stock origen (debe existir y tener suficiente)
    stock_origen = db.query(Stock).filter(
        Stock.material_id == mat.id,
        Stock.empresa_id  == empresa_id,
        Stock.almacen_id  == body.almacen_origen_id,
    ).first()
    disponible = stock_origen.cantidad if stock_origen else 0
    if body.cantidad > disponible:
        raise HTTPException(
            status_code=409,
            detail=f"Stock insuficiente en origen (disponible: {disponible})",
        )

    stock_origen.cantidad -= body.cantidad
    stock_origen.updated_at = datetime.utcnow()

    # Stock destino (crear si no existe)
    stock_destino = db.query(Stock).filter(
        Stock.material_id == mat.id,
        Stock.empresa_id  == empresa_id,
        Stock.almacen_id  == body.almacen_destino_id,
    ).first()
    if stock_destino:
        stock_destino.cantidad = (stock_destino.cantidad or 0) + body.cantidad
        stock_destino.updated_at = datetime.utcnow()
    else:
        db.add(Stock(
            material_id    = mat.id,
            empresa_id     = empresa_id,
            almacen_id     = body.almacen_destino_id,
            cantidad       = body.cantidad,
            cantidad_minima= 0,
        ))

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    emp_id = empleado.id if empleado else None
    ref = str(_uuid.uuid4())
    nota = body.motivo or ""

    # Movimiento de salida (origen) y entrada (destino)
    db.add(MovimientoInventario(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, material_id=mat.id,
        almacen_id=body.almacen_origen_id, tipo="transferencia",
        cantidad=body.cantidad,
        motivo=f"Salida a {destino.nombre}" + (f" · {nota}" if nota else ""),
        referencia_id=ref, referencia_tipo="transferencia",
        responsable_id=emp_id, fecha=datetime.utcnow(),
    ))
    db.add(MovimientoInventario(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, material_id=mat.id,
        almacen_id=body.almacen_destino_id, tipo="transferencia",
        cantidad=body.cantidad,
        motivo=f"Entrada desde {origen.nombre}" + (f" · {nota}" if nota else ""),
        referencia_id=ref, referencia_tipo="transferencia",
        responsable_id=emp_id, fecha=datetime.utcnow(),
    ))

    db.commit()
    return {"ok": True}


# ── GET /requerimientos/mis-solicitudes ───────────────────────────────────────

@router.get("/mis-solicitudes", response_model=List[MiSolicitudOut])
def get_mis_solicitudes(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    reqs = (
        db.query(Requerimiento)
        .filter(
            Requerimiento.empresa_id    == empresa_id,
            Requerimiento.solicitante_id == empleado.id,
            Requerimiento.tipo          == "material",
        )
        .order_by(Requerimiento.created_at.desc())
        .all()
    )

    if not reqs:
        return []

    req_ids     = [r.id for r in reqs]
    proyecto_ids = list({r.proyecto_id for r in reqs})

    proyectos_map = {
        p.id: p
        for p in db.query(Proyecto).filter(Proyecto.id.in_(proyecto_ids)).all()
    }

    detalles_rows = (
        db.query(
            RequerimientoDetalle,
            Material.nombre.label("mat_nombre"),
            Material.unidad.label("mat_unidad"),
        )
        .outerjoin(Material, Material.id == RequerimientoDetalle.material_id)
        .filter(RequerimientoDetalle.requerimiento_id.in_(req_ids))
        .all()
    )

    detalles_by_req: dict[str, list] = {}
    for row in detalles_rows:
        detalles_by_req.setdefault(row.RequerimientoDetalle.requerimiento_id, []).append(row)

    result = []
    for req in reqs:
        proyecto = proyectos_map.get(req.proyecto_id)
        proyecto_nombre = (
            proyecto.nombre_proyecto
            if proyecto and proyecto.nombre_proyecto
            else "Proyecto"
        )

        items = [
            SolicitudDetalleOut(
                id=str(d.RequerimientoDetalle.id),
                material_id=str(d.RequerimientoDetalle.material_id) if d.RequerimientoDetalle.material_id else None,
                nombre=d.mat_nombre or d.RequerimientoDetalle.nombre_libre or "",
                unidad=d.mat_unidad or d.RequerimientoDetalle.unidad_libre or "",
                cantidad=d.RequerimientoDetalle.cantidad or 0,
                cantidad_aprobada=d.RequerimientoDetalle.cantidad_aprobada,
                nombre_libre=d.RequerimientoDetalle.nombre_libre,
                unidad_libre=d.RequerimientoDetalle.unidad_libre,
                especificacion=d.RequerimientoDetalle.especificacion,
            )
            for d in detalles_by_req.get(req.id, [])
        ]

        result.append(MiSolicitudOut(
            id=str(req.id),
            estado=req.estado or "pendiente",
            fecha=req.fecha.strftime("%d %b %Y") if req.fecha else "",
            observacion=req.observacion,
            observacion_logistico=req.observacion_logistico,  # HU-16
            proyecto_nombre=proyecto_nombre,
            items=items,
        ))

    return result


# ── POST /requerimientos/crear ────────────────────────────────────────────────

@router.post("/crear", status_code=status.HTTP_201_CREATED)
def crear_solicitud(
    body:    CrearSolicitudBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    if not body.items:
        raise HTTPException(status_code=422, detail="Debe incluir al menos un material")

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == body.proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    for item in body.items:
        if item.cantidad < 1:
            raise HTTPException(status_code=422, detail="Cantidad debe ser mayor a 0")
        if item.material_id:
            mat = db.query(Material).filter(
                Material.id         == item.material_id,
                Material.empresa_id == empresa_id,
                Material.activo     == True,
            ).first()
            if not mat:
                raise HTTPException(status_code=404, detail="Material no encontrado")
        else:
            if not item.nombre_libre or not item.unidad_libre:
                raise HTTPException(status_code=422, detail="Material manual requiere nombre_libre y unidad_libre")

    req = Requerimiento(
        id             = str(_uuid.uuid4()),
        proyecto_id    = body.proyecto_id,
        empresa_id     = empresa_id,
        solicitante_id = empleado.id,
        tipo           = "material",
        estado         = "pendiente",
        observacion    = body.observacion,
        fecha          = date.today(),
    )
    db.add(req)
    db.flush()

    for item in body.items:
        db.add(RequerimientoDetalle(
            id               = str(_uuid.uuid4()),
            requerimiento_id = req.id,
            material_id      = item.material_id,
            cantidad         = item.cantidad,
            nombre_libre     = item.nombre_libre,
            unidad_libre     = item.unidad_libre,
            especificacion   = item.especificacion,
        ))

    db.commit()
    return {"ok": True, "requerimiento_id": req.id}


# ── GET /requerimientos/categorias ────────────────────────────────────────────

@router.get("/categorias", response_model=list[CategoriaOut])
def get_categorias(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(CategoriaMaterial)
        .filter(CategoriaMaterial.empresa_id == empresa_id)
        .order_by(CategoriaMaterial.nombre)
        .all()
    )
    return [CategoriaOut(id=str(r.id), nombre=r.nombre) for r in rows]


# ── GET /requerimientos/almacenes ─────────────────────────────────────────────

@router.get("/almacenes", response_model=list[AlmacenOut])
def get_almacenes(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Almacen)
        .filter(Almacen.empresa_id == empresa_id)
        .order_by(Almacen.nombre)
        .all()
    )
    return [AlmacenOut(id=str(r.id), nombre=r.nombre, ubicacion=r.ubicacion) for r in rows]


# ── POST /requerimientos/inventario/material ──────────────────────────────────
# Crear un nuevo material con stock inicial — solo logística/admin

@router.post("/inventario/material", status_code=status.HTTP_201_CREATED)
def crear_material(
    body:    CrearMaterialBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    rol        = (payload.get("rol") or "").lower()

    es_admin     = es_superadmin(payload)
    es_logistica = rol in ("logística", "logistica")
    if not es_admin and not es_logistica:
        raise HTTPException(status_code=403, detail="Sin permiso para agregar al inventario")

    cat = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.id         == body.categoria_id,
        CategoriaMaterial.empresa_id == empresa_id,
    ).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")

    nuevo = Material(
        id          = str(_uuid.uuid4()),
        empresa_id  = empresa_id,
        categoria_id= body.categoria_id,
        nombre      = body.nombre.strip(),
        codigo      = body.codigo.strip() if body.codigo else None,
        unidad      = body.unidad.strip(),
        descripcion = body.descripcion,
        activo      = True,
    )
    db.add(nuevo)
    db.flush()

    if body.cantidad_inicial > 0:
        almacen_id = body.almacen_id
        if not almacen_id:
            alm = db.query(Almacen).filter(Almacen.empresa_id == empresa_id).first()
            if alm:
                almacen_id = str(alm.id)

        if almacen_id:
            db.add(Stock(
                material_id    = nuevo.id,
                empresa_id     = empresa_id,
                almacen_id     = almacen_id,
                cantidad       = body.cantidad_inicial,
                cantidad_minima= 0,
            ))

    db.add(Auditoria(
        id             = str(_uuid.uuid4()),
        empresa_id     = empresa_id,
        usuario_id     = usuario_id,
        tabla_afectada = "material",
        registro_id    = nuevo.id,
        accion         = "INSERT",
        modulo         = "logistica",
        descripcion    = f"Material '{body.nombre}' agregado al inventario con stock {body.cantidad_inicial}",
        datos_nuevos   = {"nombre": body.nombre, "unidad": body.unidad, "cantidad_inicial": body.cantidad_inicial},
        fecha          = datetime.utcnow(),
    ))

    db.commit()
    return {"ok": True, "material_id": nuevo.id}


# ── PATCH /requerimientos/inventario/material/{id} ────────────────────────────
# Editar datos del material y/o su umbral de bajo stock — solo logística/admin.

@router.patch("/inventario/material/{material_id}")
def editar_material(
    material_id: str,
    body:        EditarMaterialBody,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    mat = db.query(Material).filter(
        Material.id         == material_id,
        Material.empresa_id == empresa_id,
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    if body.nombre is not None:
        mat.nombre = body.nombre.strip()
    if body.codigo is not None:
        mat.codigo = body.codigo.strip() or None
    if body.unidad is not None:
        mat.unidad = body.unidad.strip()
    if body.descripcion is not None:
        mat.descripcion = body.descripcion
    if body.categoria_id is not None:
        cat = db.query(CategoriaMaterial).filter(
            CategoriaMaterial.id         == body.categoria_id,
            CategoriaMaterial.empresa_id == empresa_id,
        ).first()
        if not cat:
            raise HTTPException(status_code=404, detail="Categoría no encontrada")
        mat.categoria_id = body.categoria_id

    # Umbral de bajo stock: aplicar a las filas de stock del material
    if body.cantidad_minima is not None:
        if body.cantidad_minima < 0:
            raise HTTPException(status_code=422, detail="El mínimo no puede ser negativo")
        filas = db.query(Stock).filter(
            Stock.material_id == mat.id,
            Stock.empresa_id  == empresa_id,
        ).all()
        if filas:
            for st in filas:
                st.cantidad_minima = body.cantidad_minima
                st.updated_at = datetime.utcnow()
        else:
            alm = db.query(Almacen).filter(Almacen.empresa_id == empresa_id).first()
            if alm:
                db.add(Stock(
                    material_id    = mat.id,
                    empresa_id     = empresa_id,
                    almacen_id     = str(alm.id),
                    cantidad       = 0,
                    cantidad_minima= body.cantidad_minima,
                ))

    db.commit()
    return {"ok": True, "material_id": mat.id}


# ── DELETE /requerimientos/inventario/material/{id} ───────────────────────────
# Baja lógica (activo=False) — solo logística/admin.

@router.delete("/inventario/material/{material_id}")
def eliminar_material(
    material_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    mat = db.query(Material).filter(
        Material.id         == material_id,
        Material.empresa_id == empresa_id,
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    mat.activo = False
    db.commit()
    return {"ok": True}


# ── POST /requerimientos/categorias ───────────────────────────────────────────
# Crear categoría — solo logística/admin.

@router.post("/categorias", status_code=status.HTTP_201_CREATED)
def crear_categoria(
    body:    CategoriaBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")
    if not body.nombre.strip():
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")

    cat = CategoriaMaterial(
        id          = str(_uuid.uuid4()),
        empresa_id  = empresa_id,
        nombre      = body.nombre.strip(),
        descripcion = body.descripcion,
    )
    db.add(cat)
    db.commit()
    return {"ok": True, "categoria_id": cat.id}


# ── PATCH /requerimientos/categorias/{id} ─────────────────────────────────────

@router.patch("/categorias/{categoria_id}")
def editar_categoria(
    categoria_id: str,
    body:         CategoriaBody,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    cat = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.id         == categoria_id,
        CategoriaMaterial.empresa_id == empresa_id,
    ).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")

    if body.nombre.strip():
        cat.nombre = body.nombre.strip()
    cat.descripcion = body.descripcion
    db.commit()
    return {"ok": True}


# ── DELETE /requerimientos/categorias/{id} ────────────────────────────────────
# Solo permite eliminar si no tiene materiales activos asociados.

@router.delete("/categorias/{categoria_id}")
def eliminar_categoria(
    categoria_id: str,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    if not _puede_gestionar_logistica(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")

    cat = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.id         == categoria_id,
        CategoriaMaterial.empresa_id == empresa_id,
    ).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")

    en_uso = db.query(Material).filter(
        Material.categoria_id == categoria_id,
        Material.empresa_id   == empresa_id,
        Material.activo       == True,
    ).first()
    if en_uso:
        raise HTTPException(
            status_code=409,
            detail="No se puede eliminar: hay materiales en esta categoría",
        )

    db.delete(cat)
    db.commit()
    return {"ok": True}
