"""
Router: /logistica
Módulo de Logística (HU-15) — Materiales y Equipos/Herramientas con CRUD.

* Materiales: catálogo (tabla `material`) + stock agregado (tabla `stock`).
* Equipos/Herramientas: tabla `equipo` ampliada con `clase`, mantenimiento
  y campos heredados del legacy `articulos`.

Toda escritura queda registrada por el listener global de auditoría
(`app/core/audit_listener.py`) sobre la tabla `auditoria`, con `modulo`
mapeado a "INVENTARIO" / "MANTENIMIENTO".
"""
from __future__ import annotations

import uuid as _uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db

from ..models.material import Material, Stock
from ..models.categoria_material import CategoriaMaterial
from ..models.almacen import Almacen
from ..models.equipo import Equipo

from ..schemas.logistica import (
    MaterialIn, MaterialPatch, MaterialOut, MaterialesListResponse,
    EquipoIn,   EquipoPatch,   EquipoOut,   EquiposListResponse,
    LogisticaKpis,
)


router = APIRouter(prefix="/logistica", tags=["logistica"])


# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

def _autorizar_logistica(payload: dict) -> None:
    """Solo logística / admin / superadmin pueden mutar inventario."""
    rol = (payload.get("rol") or "").lower()
    if rol in ("logística", "logistica", "administrador", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Sin permiso para operar sobre inventario")


def _categoria_get_or_create(db: Session, empresa_id: str, nombre: str) -> CategoriaMaterial:
    nombre = (nombre or "Sin categoría").strip() or "Sin categoría"
    cat = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.empresa_id == empresa_id,
        func.lower(CategoriaMaterial.nombre) == nombre.lower(),
    ).first()
    if cat:
        return cat
    cat = CategoriaMaterial(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre,
    )
    db.add(cat)
    db.flush()
    return cat


def _almacen_get_or_create(db: Session, empresa_id: str, nombre: str) -> Almacen:
    nombre = (nombre or "Almacén Central").strip() or "Almacén Central"
    alm = db.query(Almacen).filter(
        Almacen.empresa_id == empresa_id,
        func.lower(Almacen.nombre) == nombre.lower(),
    ).first()
    if alm:
        return alm
    alm = Almacen(id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre, activo=True)
    db.add(alm)
    db.flush()
    return alm


def _stock_total(db: Session, material_id: str, empresa_id: str) -> tuple[int, int, Optional[str], Optional[str]]:
    """Devuelve (cantidad_total, stock_minimo_max, almacen_id_principal, almacen_nombre)."""
    rows = (
        db.query(Stock, Almacen.nombre)
        .outerjoin(Almacen, Almacen.id == Stock.almacen_id)
        .filter(Stock.material_id == material_id, Stock.empresa_id == empresa_id)
        .all()
    )
    if not rows:
        return 0, 0, None, None
    total = sum(int(s.cantidad or 0) for s, _ in rows)
    minimo = max(int(s.cantidad_minima or 0) for s, _ in rows)
    principal_stock, principal_nombre = rows[0]
    return total, minimo, str(principal_stock.almacen_id), principal_nombre or "Almacén"


def _material_out(db: Session, mat: Material, empresa_id: str, cat_cache: dict[str, str]) -> MaterialOut:
    total, minimo, alm_id, alm_nombre = _stock_total(db, mat.id, empresa_id)
    cat_nombre = "Sin categoría"
    if mat.categoria_id:
        if mat.categoria_id not in cat_cache:
            c = db.query(CategoriaMaterial).filter(CategoriaMaterial.id == mat.categoria_id).first()
            cat_cache[mat.categoria_id] = c.nombre if c else "Sin categoría"
        cat_nombre = cat_cache[mat.categoria_id]
    return MaterialOut(
        id=str(mat.id), codigo=mat.codigo or "", nombre=mat.nombre,
        categoriaId=str(mat.categoria_id) if mat.categoria_id else None,
        categoria=cat_nombre, unidad=mat.unidad,
        descripcion=mat.descripcion,
        cantidad=total, stockMinimo=minimo,
        almacenId=alm_id, almacen=alm_nombre or "Almacén Central",
        precio=float(mat.precio) if mat.precio is not None else None,
        activo=bool(mat.activo),
    )


def _equipo_out(e: Equipo) -> EquipoOut:
    return EquipoOut(
        id=str(e.id), codigo=e.codigo or "", nombre=e.nombre,
        clase=e.clase or "equipo",
        tipo=e.tipo or "",
        marca=e.marca, modelo=e.modelo, numeroSerie=e.numero_serie,
        ubicacion=e.ubicacion, cantidad=int(e.cantidad or 1),
        estado=e.estado or "operativo",
        requiereMantenimiento=bool(e.requiere_mantenimiento),
        frecuenciaMantenimiento=e.frecuencia_mantenimiento or "ninguno",
        proximaFechaMantenimiento=e.proxima_fecha_mantenimiento.isoformat() if e.proxima_fecha_mantenimiento else None,
        fechaAdquisicion=e.fecha_adquisicion.isoformat() if e.fecha_adquisicion else None,
        fichaTecnica=e.ficha_tecnica,
    )


# ══════════════════════════════════════════════════════════════════════════
# MATERIALES
# ══════════════════════════════════════════════════════════════════════════

@router.get("/materiales", response_model=MaterialesListResponse)
def listar_materiales(
    q:         str = Query("", description="texto a buscar en nombre/código"),
    categoria: str = Query("", description="filtrar por categoría exacta"),
    estado:    str = Query("todos", description="todos|activos|inactivos|stock_bajo"),
    page:      int = Query(1, ge=1),
    page_size: int = Query(30, ge=1, le=200),
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """HU-15: GET /logistica/materiales con filtros y paginación."""
    empresa_id = payload["empresa_id"]

    base = db.query(Material).filter(Material.empresa_id == empresa_id)

    if q:
        like = f"%{q.lower()}%"
        base = base.filter(or_(
            func.lower(Material.nombre).like(like),
            func.lower(Material.codigo).like(like),
            func.lower(Material.descripcion).like(like),
        ))

    if categoria and categoria != "Todas":
        base = base.join(
            CategoriaMaterial, CategoriaMaterial.id == Material.categoria_id
        ).filter(func.lower(CategoriaMaterial.nombre) == categoria.lower())

    if estado == "activos":
        base = base.filter(Material.activo.is_(True))
    elif estado == "inactivos":
        base = base.filter(Material.activo.is_(False))

    total = base.count()

    rows = (
        base.order_by(Material.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    cat_cache: dict[str, str] = {}
    items = [_material_out(db, m, empresa_id, cat_cache) for m in rows]

    # Filtro stock_bajo se aplica en memoria (necesita el stock agregado)
    if estado == "stock_bajo":
        items = [m for m in items if m.cantidad <= m.stockMinimo]

    return MaterialesListResponse(items=items, total=total, page=page, pageSize=page_size)


@router.post("/materiales", response_model=MaterialOut, status_code=201)
def crear_material(
    body:    MaterialIn,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    cat = _categoria_get_or_create(db, empresa_id, body.categoria)
    alm = _almacen_get_or_create(db, empresa_id, body.almacen)

    mat = Material(
        id           = str(_uuid.uuid4()),
        empresa_id   = empresa_id,
        categoria_id = cat.id,
        nombre       = body.nombre.strip(),
        codigo       = (body.codigo or "").strip() or None,
        unidad       = body.unidad.strip() or "Unidad",
        descripcion  = (body.descripcion or "").strip() or None,
        precio       = body.precio,
        activo       = body.activo,
    )
    db.add(mat)
    db.flush()

    db.add(Stock(
        material_id    = mat.id,
        empresa_id     = empresa_id,
        almacen_id     = alm.id,
        cantidad       = max(0, int(body.cantidad)),
        cantidad_minima= max(0, int(body.stockMinimo)),
        updated_at     = datetime.utcnow(),
    ))

    db.commit()
    return _material_out(db, mat, empresa_id, {})


@router.patch("/materiales/{material_id}", response_model=MaterialOut)
def actualizar_material(
    material_id: str,
    body:        MaterialPatch,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    mat = db.query(Material).filter(
        Material.id == material_id, Material.empresa_id == empresa_id
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    if body.codigo      is not None: mat.codigo      = (body.codigo or "").strip() or None
    if body.nombre      is not None: mat.nombre      = body.nombre.strip() or mat.nombre
    if body.unidad      is not None: mat.unidad      = body.unidad.strip() or mat.unidad
    if body.descripcion is not None: mat.descripcion = (body.descripcion or "").strip() or None
    if body.precio      is not None: mat.precio      = body.precio
    if body.activo      is not None: mat.activo      = bool(body.activo)
    if body.categoria   is not None:
        cat = _categoria_get_or_create(db, empresa_id, body.categoria)
        mat.categoria_id = cat.id

    # Stock / almacén
    if body.cantidad is not None or body.stockMinimo is not None or body.almacen is not None:
        alm_nombre = body.almacen if body.almacen is not None else None
        alm = _almacen_get_or_create(db, empresa_id, alm_nombre) if alm_nombre else None

        stock = db.query(Stock).filter(
            Stock.material_id == mat.id, Stock.empresa_id == empresa_id
        ).first()
        if not stock:
            if not alm:
                alm = _almacen_get_or_create(db, empresa_id, "Almacén Central")
            stock = Stock(
                material_id=mat.id, empresa_id=empresa_id, almacen_id=alm.id,
                cantidad=0, cantidad_minima=0,
            )
            db.add(stock)

        if body.cantidad     is not None: stock.cantidad        = max(0, int(body.cantidad))
        if body.stockMinimo  is not None: stock.cantidad_minima = max(0, int(body.stockMinimo))
        # cambio de almacén: si se pidió uno distinto al actual, lo migramos
        if alm and stock.almacen_id != alm.id:
            stock.almacen_id = alm.id
        stock.updated_at = datetime.utcnow()

    db.commit()
    return _material_out(db, mat, empresa_id, {})


@router.delete("/materiales/{material_id}", status_code=204)
def eliminar_material(
    material_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    mat = db.query(Material).filter(
        Material.id == material_id, Material.empresa_id == empresa_id
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    db.query(Stock).filter(
        Stock.material_id == mat.id, Stock.empresa_id == empresa_id
    ).delete(synchronize_session=False)

    db.delete(mat)
    db.commit()
    return


# ══════════════════════════════════════════════════════════════════════════
# EQUIPOS Y HERRAMIENTAS
# ══════════════════════════════════════════════════════════════════════════

@router.get("/equipos", response_model=EquiposListResponse)
def listar_equipos(
    q:        str = Query("", description="texto: nombre/código/marca/serie"),
    clase:    str = Query("todas", description="todas|equipo|herramienta"),
    estado:   str = Query("todos", description="todos|operativo|en_mantenimiento|fuera_de_servicio|baja"),
    page:     int = Query(1, ge=1),
    page_size: int = Query(30, ge=1, le=200),
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    base = db.query(Equipo).filter(Equipo.empresa_id == empresa_id)

    if q:
        like = f"%{q.lower()}%"
        base = base.filter(or_(
            func.lower(Equipo.nombre).like(like),
            func.lower(Equipo.codigo).like(like),
            func.lower(Equipo.marca).like(like),
            func.lower(Equipo.numero_serie).like(like),
        ))
    if clase in ("equipo", "herramienta"):
        base = base.filter(Equipo.clase == clase)
    if estado != "todos":
        base = base.filter(Equipo.estado == estado)

    total = base.count()
    rows = (
        base.order_by(Equipo.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return EquiposListResponse(
        items=[_equipo_out(e) for e in rows],
        total=total, page=page, pageSize=page_size,
    )


@router.post("/equipos", response_model=EquipoOut, status_code=201)
def crear_equipo(
    body:    EquipoIn,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    e = Equipo(
        id           = str(_uuid.uuid4()),
        empresa_id   = empresa_id,
        nombre       = body.nombre.strip(),
        codigo       = (body.codigo or "").strip() or None,
        clase        = body.clase,
        tipo         = (body.tipo or "").strip() or None,
        marca        = (body.marca or "").strip() or None,
        modelo       = (body.modelo or "").strip() or None,
        numero_serie = (body.numeroSerie or "").strip() or None,
        ubicacion    = (body.ubicacion or "").strip() or None,
        cantidad     = max(0, int(body.cantidad)),
        estado       = body.estado,
        requiere_mantenimiento     = bool(body.requiereMantenimiento),
        frecuencia_mantenimiento   = body.frecuenciaMantenimiento if body.requiereMantenimiento else "ninguno",
        proxima_fecha_mantenimiento= body.proximaFechaMantenimiento if body.requiereMantenimiento else None,
        fecha_adquisicion          = body.fechaAdquisicion,
        ficha_tecnica              = (body.fichaTecnica or "").strip() or None,
    )
    db.add(e)
    db.commit()
    db.refresh(e)
    return _equipo_out(e)


@router.patch("/equipos/{equipo_id}", response_model=EquipoOut)
def actualizar_equipo(
    equipo_id: str,
    body:      EquipoPatch,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    e = db.query(Equipo).filter(
        Equipo.id == equipo_id, Equipo.empresa_id == empresa_id
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo/Herramienta no encontrada")

    if body.codigo      is not None: e.codigo      = (body.codigo or "").strip() or None
    if body.nombre      is not None: e.nombre      = body.nombre.strip() or e.nombre
    if body.clase       is not None: e.clase       = body.clase
    if body.tipo        is not None: e.tipo        = (body.tipo or "").strip() or None
    if body.marca       is not None: e.marca       = (body.marca or "").strip() or None
    if body.modelo      is not None: e.modelo      = (body.modelo or "").strip() or None
    if body.numeroSerie is not None: e.numero_serie= (body.numeroSerie or "").strip() or None
    if body.ubicacion   is not None: e.ubicacion   = (body.ubicacion or "").strip() or None
    if body.cantidad    is not None: e.cantidad    = max(0, int(body.cantidad))
    if body.estado      is not None: e.estado      = body.estado
    if body.fechaAdquisicion is not None: e.fecha_adquisicion = body.fechaAdquisicion
    if body.fichaTecnica     is not None: e.ficha_tecnica     = (body.fichaTecnica or "").strip() or None

    if body.requiereMantenimiento is not None:
        e.requiere_mantenimiento = bool(body.requiereMantenimiento)
        if not body.requiereMantenimiento:
            e.frecuencia_mantenimiento    = "ninguno"
            e.proxima_fecha_mantenimiento = None
    if body.frecuenciaMantenimiento is not None and e.requiere_mantenimiento:
        e.frecuencia_mantenimiento = body.frecuenciaMantenimiento
    if body.proximaFechaMantenimiento is not None and e.requiere_mantenimiento:
        e.proxima_fecha_mantenimiento = body.proximaFechaMantenimiento

    e.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(e)
    return _equipo_out(e)


@router.delete("/equipos/{equipo_id}", status_code=204)
def eliminar_equipo(
    equipo_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    e = db.query(Equipo).filter(
        Equipo.id == equipo_id, Equipo.empresa_id == empresa_id
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo/Herramienta no encontrada")
    db.delete(e)
    db.commit()
    return


# ══════════════════════════════════════════════════════════════════════════
# KPIs
# ══════════════════════════════════════════════════════════════════════════

@router.get("/kpis", response_model=LogisticaKpis)
def kpis(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    total_mat = db.query(func.count(Material.id)).filter(
        Material.empresa_id == empresa_id
    ).scalar() or 0

    # Stock bajo: agrupando por material, total <= max(cantidad_minima)
    stock_agg = (
        db.query(
            Stock.material_id,
            func.sum(Stock.cantidad).label("total"),
            func.max(Stock.cantidad_minima).label("minimo"),
        )
        .filter(Stock.empresa_id == empresa_id)
        .group_by(Stock.material_id)
        .all()
    )
    stock_bajo = sum(1 for _, t, m in stock_agg if (t or 0) <= (m or 0))

    total_equipos = db.query(func.count(Equipo.id)).filter(
        Equipo.empresa_id == empresa_id, Equipo.clase == "equipo"
    ).scalar() or 0
    total_herr = db.query(func.count(Equipo.id)).filter(
        Equipo.empresa_id == empresa_id, Equipo.clase == "herramienta"
    ).scalar() or 0
    en_mant = db.query(func.count(Equipo.id)).filter(
        Equipo.empresa_id == empresa_id, Equipo.estado == "en_mantenimiento"
    ).scalar() or 0

    return LogisticaKpis(
        totalMateriales     = int(total_mat),
        materialesStockBajo = int(stock_bajo),
        totalEquipos        = int(total_equipos),
        totalHerramientas   = int(total_herr),
        enMantenimiento     = int(en_mant),
    )
