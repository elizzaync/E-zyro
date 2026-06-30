"""
Router: /requerimientos
Catálogo de materiales y gestión de solicitudes (HU-17).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status, Security
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token, es_superadmin
from ..core.permisos import exigir_no_roles_operativos, tiene_permiso
from ..db.database import get_db

from ..models.material import Material, Stock
from ..models.categoria_material import CategoriaMaterial
from ..models.requerimiento import Requerimiento, RequerimientoDetalle
from ..models.empleado import Empleado
from ..models.proyecto import Proyecto

from ..models.almacen import Almacen
from ..models.auditoria import Auditoria
from ..schemas.requerimientos import (
    CatalogoItemOut,
    CatalogoResumenOut,
    SolicitudDetalleOut,
    MiSolicitudOut,
    CrearSolicitudBody,
    CategoriaOut,
    AlmacenOut,
    CrearMaterialBody,
)
import json as _json

def _dep_bloquear_requerimientos(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
) -> None:
    """Dependencia FastAPI: por defecto bloquea Técnico y Jefe de Operaciones en
    todo el router (módulo de logística/almacén). EXCEPCIÓN: se concede acceso a
    quien tenga el permiso `requerimientos:solicitar` (delegable por rol o por
    usuario desde Privilegios), para que un Jefe de Operaciones o un Técnico
    pueda solicitar materiales para sus servicios. `tiene_permiso` ya cubre el
    bypass de admin."""
    if tiene_permiso(db, payload, "requerimientos", "solicitar"):
        return
    exigir_no_roles_operativos(payload, "Técnico y Jefe de Operaciones no tienen acceso a Requerimientos")


router = APIRouter(
    prefix="/requerimientos",
    tags=["requerimientos"],
    dependencies=[Depends(_dep_bloquear_requerimientos)],
)


def _get_empleado_or_403(db: Session, usuario_id: str, empresa_id: str) -> Empleado:
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    if not emp:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")
    return emp


# ── GET /requerimientos/catalogo ──────────────────────────────────────────────

def _catalogo_base_query(db: Session, empresa_id: str, *, tipo: str, q: str,
                         categoria: str, estado_stock: str, almacen_id: str,
                         stock_expr, min_expr):
    """Query base compartida por /catalogo y /catalogo/resumen.
    Devuelve el query ya con joins + filtros (texto, categoría, tipo, almacén,
    estado de stock). El orden/paginación se aplica fuera."""
    query = (
        db.query(
            Material.id,
            Material.nombre,
            Material.codigo,
            Material.unidad,
            Material.descripcion,
            CategoriaMaterial.nombre.label("categoria"),
            stock_expr.label("stock"),
            min_expr.label("minimo"),
            Material.tipo,
        )
        .outerjoin(CategoriaMaterial, CategoriaMaterial.id == Material.categoria_id)
        .filter(Material.empresa_id == empresa_id, Material.activo == True)
    )
    if tipo != "todos":
        query = query.filter(Material.tipo == tipo)
    if q:
        query = query.filter(
            (Material.nombre.ilike(f"%{q}%")) | (Material.codigo.ilike(f"%{q}%"))
        )
    if categoria and categoria.lower() not in ("", "todas"):
        query = query.filter(CategoriaMaterial.nombre.ilike(f"%{categoria}%"))

    # Filtro por estado de stock (sobre la expresión calculada)
    if estado_stock == "con_stock":
        query = query.filter(stock_expr > 0)
    elif estado_stock == "agotado":
        query = query.filter(stock_expr <= 0)
    elif estado_stock == "bajo":
        query = query.filter(stock_expr > 0, min_expr > 0, stock_expr <= min_expr)
    return query


def _stock_exprs(db: Session, empresa_id: str, almacen_id: str):
    """Subconsulta de stock (sumada por material). Si se indica almacen_id,
    se acota a ese almacén. Devuelve (stock_expr, min_expr)."""
    sq = db.query(
        Stock.material_id,
        func.sum(Stock.cantidad).label("total"),
        func.max(Stock.cantidad_minima).label("minimo"),
    ).filter(Stock.empresa_id == empresa_id)
    if almacen_id:
        sq = sq.filter(Stock.almacen_id == almacen_id)
    sq = sq.group_by(Stock.material_id).subquery()
    return sq, func.coalesce(sq.c.total, 0), func.coalesce(sq.c.minimo, 0)


@router.get("/catalogo", response_model=List[CatalogoItemOut])
def get_catalogo(
    q:            str = "",
    categoria:    str = "",
    tipo:         str = "consumible",   # consumible | herramienta | todos
    estado_stock: str = "todos",        # todos | con_stock | bajo | agotado
    orden:        str = "nombre",       # nombre | stock_asc | stock_desc | reciente
    almacen_id:   str = "",
    page:         int = 1,
    page_size:    int = 30,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    page_size = min(max(page_size, 1), 100)
    page      = max(page, 1)
    offset    = (page - 1) * page_size

    sq, stock_expr, min_expr = _stock_exprs(db, empresa_id, almacen_id)
    query = (
        _catalogo_base_query(db, empresa_id, tipo=tipo, q=q, categoria=categoria,
                             estado_stock=estado_stock, almacen_id=almacen_id,
                             stock_expr=stock_expr, min_expr=min_expr)
        .outerjoin(sq, sq.c.material_id == Material.id)
    )

    if orden == "stock_asc":
        query = query.order_by(stock_expr.asc(), Material.nombre.asc())
    elif orden == "stock_desc":
        query = query.order_by(stock_expr.desc(), Material.nombre.asc())
    elif orden == "reciente":
        query = query.order_by(Material.created_at.desc())
    else:
        query = query.order_by(Material.nombre.asc())

    rows = query.offset(offset).limit(page_size).all()

    return [
        CatalogoItemOut(
            id=r.id, nombre=r.nombre, codigo=r.codigo, unidad=r.unidad,
            stock=int(r.stock or 0), stock_minimo=int(r.minimo or 0),
            categoria=r.categoria, descripcion=r.descripcion,
            imagen_url=None, tipo=r.tipo or "consumible",
        )
        for r in rows
    ]


@router.get("/catalogo/resumen", response_model=CatalogoResumenOut)
def get_catalogo_resumen(
    q:          str = "",
    categoria:  str = "",
    tipo:       str = "consumible",
    almacen_id: str = "",
    payload:    dict    = Depends(verificar_token),
    db:         Session = Depends(get_db),
):
    """Conteos para el header: total, con stock, bajo mínimo, agotado.
    Respeta los filtros de búsqueda/categoría/almacén (no el de estado_stock)."""
    empresa_id = payload["empresa_id"]
    sq, stock_expr, min_expr = _stock_exprs(db, empresa_id, almacen_id)
    base = (
        _catalogo_base_query(db, empresa_id, tipo=tipo, q=q, categoria=categoria,
                             estado_stock="todos", almacen_id=almacen_id,
                             stock_expr=stock_expr, min_expr=min_expr)
        .outerjoin(sq, sq.c.material_id == Material.id)
    ).subquery()

    total     = db.query(func.count()).select_from(base).scalar() or 0
    con_stock = db.query(func.count()).select_from(base).filter(base.c.stock > 0).scalar() or 0
    agotado   = db.query(func.count()).select_from(base).filter(base.c.stock <= 0).scalar() or 0
    bajo      = db.query(func.count()).select_from(base).filter(
        base.c.stock > 0, base.c.minimo > 0, base.c.stock <= base.c.minimo
    ).scalar() or 0

    return CatalogoResumenOut(total=total, con_stock=con_stock, bajo=bajo, agotado=agotado)


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
    return [AlmacenOut(id=str(r.id), nombre=r.nombre, ubicacion=r.ubicacion,
                       predeterminado=bool(r.predeterminado)) for r in rows]


# ── GET /requerimientos/inventario/resumen ────────────────────────────────────
# Panel del encargado: KPIs de inventario + alertas de bajo stock.
# Lo consume el móvil (pantalla_inventario_panel.dart).

@router.get("/inventario/resumen")
def resumen_inventario(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    # Stock agregado por material (suma cantidades de todos los almacenes; toma
    # el máximo minimo configurado entre filas — el mismo criterio que /logistica/kpis).
    stock_rows = (
        db.query(
            Stock.material_id.label("mid"),
            func.coalesce(func.sum(Stock.cantidad), 0).label("total"),
            func.coalesce(func.max(Stock.cantidad_minima), 0).label("minimo"),
        )
        .filter(Stock.empresa_id == empresa_id)
        .group_by(Stock.material_id)
        .subquery()
    )

    # Lista de materiales activos con su stock agregado (LEFT JOIN: incluir materiales sin stock).
    rows = (
        db.query(
            Material.id,
            Material.nombre,
            Material.unidad,
            CategoriaMaterial.nombre.label("categoria"),
            func.coalesce(stock_rows.c.total, 0).label("stock"),
            func.coalesce(stock_rows.c.minimo, 0).label("minimo"),
        )
        .outerjoin(stock_rows, stock_rows.c.mid == Material.id)
        .outerjoin(CategoriaMaterial, CategoriaMaterial.id == Material.categoria_id)
        .filter(
            Material.empresa_id == empresa_id,
            Material.activo.is_(True),
        )
        .all()
    )

    total_items = len(rows)
    bajo = []   # stock <= minimo y minimo > 0 y stock > 0
    sin = 0
    for r in rows:
        stock = int(r.stock or 0)
        minimo = int(r.minimo or 0)
        if stock == 0:
            sin += 1
            bajo.append(r)
        elif minimo > 0 and stock <= minimo:
            bajo.append(r)

    # Orden: agotados primero, luego por ratio stock/minimo asc.
    def _peso(r):
        s = int(r.stock or 0)
        m = int(r.minimo or 0)
        if s == 0:
            return (0, 0.0)
        return (1, s / m if m > 0 else 1.0)
    bajo.sort(key=_peso)

    items_bajo_stock = [
        {
            "id": str(r.id),
            "nombre": r.nombre or "",
            "unidad": r.unidad or "und",
            "categoria": r.categoria,
            "stock": int(r.stock or 0),
            "minimo": int(r.minimo or 0),
        }
        for r in bajo[:20]  # tope para no inflar el payload
    ]

    return {
        "total_items": total_items,
        "bajo_stock": len(bajo) - sin,   # solo los que están en alerta sin estar agotados
        "sin_stock": sin,
        "items_bajo_stock": items_bajo_stock,
    }


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
