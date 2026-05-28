"""
Router: /logistica
Módulo de Logística (HU-15) — Materiales y Equipos/Herramientas con CRUD,
catálogos de soporte (categorías, almacenes, unidades, tipos, marcas, modelos)
y auto-generación de códigos correlativos.

Toda escritura queda registrada por el listener global de auditoría
(`app/core/audit_listener.py`) sobre la tabla `auditoria`.
"""
from __future__ import annotations

import re
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
from ..models.tipo_equipo import TipoEquipo
from ..models.marca import Marca
from ..models.modelo_equipo import ModeloEquipo
from ..models.unidad_medida import UnidadMedida
from ..models.requerimiento import Requerimiento, RequerimientoDetalle
from ..models.requerimiento_entrega import RequerimientoEntrega
from ..models.movimiento_inventario import MovimientoInventario
from ..models.ticket_compra import TicketCompra, TicketCompraItem
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.proyecto import Proyecto
from ..models.proyecto_servicio import ProyectoServicio
from ..models.firma_digital import FirmaDigital
from ..models.notificacion import Notificacion
from ..models.proveedor import Proveedor as ProveedorModel, ProveedorCategoria

from ..schemas.logistica import (
    MaterialIn, MaterialPatch, MaterialOut, MaterialesListResponse,
    EquipoIn,   EquipoPatch,   EquipoOut,   EquiposListResponse,
    LogisticaKpis,
    CatalogoItem, CatalogoIn,
    AlmacenOut, AlmacenIn,
    UnidadOut,  UnidadIn,
    ModeloOut,  ModeloIn,
    RequerimientoItemOut, RequerimientoOut, RequerimientosListResponse,
    AprobarBody, RechazarBody, EntregarBody, FirmarBody,
    TicketCompraItemOut, TicketCompraOut, ComprasListResponse,
    ProcesarCompraBody, CancelarCompraBody, ComprasResumen,
    ProveedorOut, ProveedorIn,
)
from datetime import date as _date


router = APIRouter(prefix="/logistica", tags=["logistica"])


# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

def _autorizar_logistica(payload: dict) -> None:
    """Solo logística / admin / superadmin pueden mutar inventario y catálogos."""
    rol = (payload.get("rol") or "").lower()
    if rol in ("logística", "logistica", "administrador", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Sin permiso para operar sobre logística")


def _siguiente_codigo(db: Session, empresa_id: str, prefijo: str, modelo) -> str:
    """
    Genera el siguiente código correlativo `<PREFIJO>-NNNN` para la empresa.
    Lee el máximo número usado y suma 1. Mismo patrón que los servicios.
    """
    rows = (
        db.query(modelo.codigo)
        .filter(modelo.empresa_id == empresa_id, modelo.codigo.ilike(f"{prefijo}-%"))
        .all()
    )
    max_n = 0
    pat = re.compile(rf"^{re.escape(prefijo)}-(\d+)$", re.IGNORECASE)
    for (c,) in rows:
        if not c:
            continue
        m = pat.match(c.strip())
        if m:
            n = int(m.group(1))
            if n > max_n:
                max_n = n
    return f"{prefijo}-{(max_n + 1):04d}"


def _categoria_or_404(db: Session, empresa_id: str, categoria_id: str) -> CategoriaMaterial:
    cat = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.id == categoria_id,
        CategoriaMaterial.empresa_id == empresa_id,
    ).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")
    return cat


def _almacen_or_404(db: Session, empresa_id: str, almacen_id: str) -> Almacen:
    alm = db.query(Almacen).filter(
        Almacen.id == almacen_id, Almacen.empresa_id == empresa_id
    ).first()
    if not alm:
        raise HTTPException(status_code=404, detail="Almacén no encontrado")
    return alm


def _unidad_or_404(db: Session, empresa_id: str, unidad_id: str) -> UnidadMedida:
    u = db.query(UnidadMedida).filter(
        UnidadMedida.id == unidad_id, UnidadMedida.empresa_id == empresa_id
    ).first()
    if not u:
        raise HTTPException(status_code=404, detail="Unidad no encontrada")
    return u


def _tipo_or_404(db: Session, empresa_id: str, tipo_id: str) -> TipoEquipo:
    t = db.query(TipoEquipo).filter(
        TipoEquipo.id == tipo_id, TipoEquipo.empresa_id == empresa_id
    ).first()
    if not t:
        raise HTTPException(status_code=404, detail="Tipo / familia no encontrada")
    return t


def _marca_or_404(db: Session, empresa_id: str, marca_id: str) -> Marca:
    m = db.query(Marca).filter(
        Marca.id == marca_id, Marca.empresa_id == empresa_id
    ).first()
    if not m:
        raise HTTPException(status_code=404, detail="Marca no encontrada")
    return m


def _modelo_or_404(db: Session, empresa_id: str, modelo_id: str) -> ModeloEquipo:
    m = db.query(ModeloEquipo).filter(
        ModeloEquipo.id == modelo_id, ModeloEquipo.empresa_id == empresa_id
    ).first()
    if not m:
        raise HTTPException(status_code=404, detail="Modelo no encontrado")
    return m


def _stock_principal(db: Session, material_id: str, empresa_id: str):
    """Devuelve (total, minimo, almacen_id, almacen_nombre) del material."""
    rows = (
        db.query(Stock, Almacen.nombre)
        .outerjoin(Almacen, Almacen.id == Stock.almacen_id)
        .filter(Stock.material_id == material_id, Stock.empresa_id == empresa_id)
        .all()
    )
    if not rows:
        return 0, 0, None, ""
    total = sum(int(s.cantidad or 0) for s, _ in rows)
    minimo = max(int(s.cantidad_minima or 0) for s, _ in rows)
    principal_stock, principal_nombre = rows[0]
    return total, minimo, str(principal_stock.almacen_id), principal_nombre or ""


def _material_out(db: Session, mat: Material, empresa_id: str) -> MaterialOut:
    total, minimo, alm_id, alm_nombre = _stock_principal(db, mat.id, empresa_id)

    cat_nombre = "Sin categoría"
    if mat.categoria_id:
        c = db.query(CategoriaMaterial).filter(CategoriaMaterial.id == mat.categoria_id).first()
        if c:
            cat_nombre = c.nombre

    # `unidad` en Material es String; resolvemos el id buscándolo por nombre
    unidad_id = None
    if mat.unidad:
        u = db.query(UnidadMedida).filter(
            UnidadMedida.empresa_id == empresa_id,
            func.lower(UnidadMedida.nombre) == mat.unidad.lower(),
        ).first()
        unidad_id = str(u.id) if u else None

    return MaterialOut(
        id=str(mat.id), codigo=mat.codigo or "", nombre=mat.nombre,
        categoriaId=str(mat.categoria_id) if mat.categoria_id else None,
        categoria=cat_nombre,
        unidadId=unidad_id, unidad=mat.unidad,
        descripcion=mat.descripcion,
        cantidad=total, stockMinimo=minimo,
        almacenId=alm_id, almacen=alm_nombre or "",
        precio=float(mat.precio) if mat.precio is not None else None,
        activo=bool(mat.activo),
    )


def _equipo_out(e: Equipo) -> EquipoOut:
    return EquipoOut(
        id=str(e.id), codigo=e.codigo or "", nombre=e.nombre,
        clase=e.clase or "equipo",
        tipoId=str(e.tipo_equipo_id) if e.tipo_equipo_id else None,
        tipo=e.tipo or "",
        marcaId=str(e.marca_id) if e.marca_id else None,
        marca=e.marca,
        modeloId=str(e.modelo_id) if e.modelo_id else None,
        modelo=e.modelo,
        numeroSerie=e.numero_serie,
        almacenId=str(e.almacen_id) if e.almacen_id else None,
        ubicacion=e.ubicacion, cantidad=int(e.cantidad or 1),
        estado=e.estado or "operativo",
        requiereMantenimiento=bool(e.requiere_mantenimiento),
        frecuenciaMantenimiento=e.frecuencia_mantenimiento or "ninguno",
        proximaFechaMantenimiento=e.proxima_fecha_mantenimiento.isoformat() if e.proxima_fecha_mantenimiento else None,
        fechaAdquisicion=e.fecha_adquisicion.isoformat() if e.fecha_adquisicion else None,
        fichaTecnica=e.ficha_tecnica,
    )


# ══════════════════════════════════════════════════════════════════════════
# CATÁLOGOS — categorías, almacenes, unidades, tipos, marcas, modelos
# ══════════════════════════════════════════════════════════════════════════

# ── Categorías de material ─────────────────────────────────────────────────
@router.get("/categorias", response_model=List[CatalogoItem])
def listar_categorias(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(CategoriaMaterial)
        .filter(CategoriaMaterial.empresa_id == empresa_id)
        .order_by(CategoriaMaterial.nombre)
        .all()
    )
    return [CatalogoItem(id=str(r.id), nombre=r.nombre) for r in rows]


@router.post("/categorias", response_model=CatalogoItem, status_code=201)
def crear_categoria(body: CatalogoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")

    existente = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.empresa_id == empresa_id,
        func.lower(CategoriaMaterial.nombre) == nombre.lower(),
    ).first()
    if existente:
        return CatalogoItem(id=str(existente.id), nombre=existente.nombre)

    cat = CategoriaMaterial(id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre)
    db.add(cat)
    db.commit()
    return CatalogoItem(id=str(cat.id), nombre=cat.nombre)


# ── Almacenes ──────────────────────────────────────────────────────────────
@router.get("/almacenes", response_model=List[AlmacenOut])
def listar_almacenes(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Almacen)
        .filter(Almacen.empresa_id == empresa_id, Almacen.activo.is_(True))
        .order_by(Almacen.nombre)
        .all()
    )
    return [AlmacenOut(id=str(r.id), nombre=r.nombre, ubicacion=r.ubicacion) for r in rows]


@router.post("/almacenes", response_model=AlmacenOut, status_code=201)
def crear_almacen(body: AlmacenIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")

    existente = db.query(Almacen).filter(
        Almacen.empresa_id == empresa_id,
        func.lower(Almacen.nombre) == nombre.lower(),
    ).first()
    if existente:
        return AlmacenOut(id=str(existente.id), nombre=existente.nombre, ubicacion=existente.ubicacion)

    alm = Almacen(
        id=str(_uuid.uuid4()), empresa_id=empresa_id,
        nombre=nombre, ubicacion=body.ubicacion, activo=True,
    )
    db.add(alm)
    db.commit()
    return AlmacenOut(id=str(alm.id), nombre=alm.nombre, ubicacion=alm.ubicacion)


# ── Unidades de medida ─────────────────────────────────────────────────────
@router.get("/unidades", response_model=List[UnidadOut])
def listar_unidades(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(UnidadMedida)
        .filter(UnidadMedida.empresa_id == empresa_id)
        .order_by(UnidadMedida.nombre)
        .all()
    )
    return [UnidadOut(id=str(r.id), nombre=r.nombre, abreviatura=r.abreviatura) for r in rows]


@router.post("/unidades", response_model=UnidadOut, status_code=201)
def crear_unidad(body: UnidadIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")

    existente = db.query(UnidadMedida).filter(
        UnidadMedida.empresa_id == empresa_id,
        func.lower(UnidadMedida.nombre) == nombre.lower(),
    ).first()
    if existente:
        return UnidadOut(id=str(existente.id), nombre=existente.nombre, abreviatura=existente.abreviatura)

    u = UnidadMedida(
        id=str(_uuid.uuid4()), empresa_id=empresa_id,
        nombre=nombre, abreviatura=body.abreviatura,
    )
    db.add(u)
    db.commit()
    return UnidadOut(id=str(u.id), nombre=u.nombre, abreviatura=u.abreviatura)


# ── Tipos / familias de equipo ─────────────────────────────────────────────
@router.get("/tipos-equipo", response_model=List[CatalogoItem])
def listar_tipos_equipo(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(TipoEquipo)
        .filter(TipoEquipo.empresa_id == empresa_id)
        .order_by(TipoEquipo.nombre)
        .all()
    )
    return [CatalogoItem(id=str(r.id), nombre=r.nombre) for r in rows]


@router.post("/tipos-equipo", response_model=CatalogoItem, status_code=201)
def crear_tipo_equipo(body: CatalogoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")

    existente = db.query(TipoEquipo).filter(
        TipoEquipo.empresa_id == empresa_id,
        func.lower(TipoEquipo.nombre) == nombre.lower(),
    ).first()
    if existente:
        return CatalogoItem(id=str(existente.id), nombre=existente.nombre)

    t = TipoEquipo(id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre)
    db.add(t)
    db.commit()
    return CatalogoItem(id=str(t.id), nombre=t.nombre)


# ── Marcas ─────────────────────────────────────────────────────────────────
@router.get("/marcas", response_model=List[CatalogoItem])
def listar_marcas(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Marca)
        .filter(Marca.empresa_id == empresa_id)
        .order_by(Marca.nombre)
        .all()
    )
    return [CatalogoItem(id=str(r.id), nombre=r.nombre) for r in rows]


@router.post("/marcas", response_model=CatalogoItem, status_code=201)
def crear_marca(body: CatalogoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")

    existente = db.query(Marca).filter(
        Marca.empresa_id == empresa_id,
        func.lower(Marca.nombre) == nombre.lower(),
    ).first()
    if existente:
        return CatalogoItem(id=str(existente.id), nombre=existente.nombre)

    m = Marca(id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre)
    db.add(m)
    db.commit()
    return CatalogoItem(id=str(m.id), nombre=m.nombre)


# ── Modelos (filtrables por marca) ─────────────────────────────────────────
@router.get("/modelos", response_model=List[ModeloOut])
def listar_modelos(
    marca_id: Optional[str] = Query(None),
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    q = db.query(ModeloEquipo).filter(ModeloEquipo.empresa_id == empresa_id)
    if marca_id:
        q = q.filter(ModeloEquipo.marca_id == marca_id)
    rows = q.order_by(ModeloEquipo.nombre).all()
    return [ModeloOut(id=str(r.id), nombre=r.nombre, marcaId=str(r.marca_id)) for r in rows]


@router.post("/modelos", response_model=ModeloOut, status_code=201)
def crear_modelo(body: ModeloIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    _marca_or_404(db, empresa_id, body.marcaId)

    existente = db.query(ModeloEquipo).filter(
        ModeloEquipo.empresa_id == empresa_id,
        ModeloEquipo.marca_id == body.marcaId,
        func.lower(ModeloEquipo.nombre) == nombre.lower(),
    ).first()
    if existente:
        return ModeloOut(id=str(existente.id), nombre=existente.nombre, marcaId=str(existente.marca_id))

    m = ModeloEquipo(
        id=str(_uuid.uuid4()), empresa_id=empresa_id,
        marca_id=body.marcaId, nombre=nombre,
    )
    db.add(m)
    db.commit()
    return ModeloOut(id=str(m.id), nombre=m.nombre, marcaId=str(m.marca_id))


# ══════════════════════════════════════════════════════════════════════════
# MATERIALES
# ══════════════════════════════════════════════════════════════════════════

@router.get("/materiales", response_model=MaterialesListResponse)
def listar_materiales(
    q:         str = Query("", description="texto a buscar en nombre/código"),
    categoria: str = Query("", description="filtrar por nombre exacto de categoría"),
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
    items = [_material_out(db, m, empresa_id) for m in rows]

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

    cat = _categoria_or_404(db, empresa_id, body.categoriaId)
    alm = _almacen_or_404(db, empresa_id, body.almacenId)
    uni = _unidad_or_404(db, empresa_id, body.unidadId)

    codigo = (body.codigo or "").strip() or _siguiente_codigo(db, empresa_id, "MAT", Material)

    mat = Material(
        id           = str(_uuid.uuid4()),
        empresa_id   = empresa_id,
        categoria_id = cat.id,
        nombre       = body.nombre.strip(),
        codigo       = codigo,
        unidad       = uni.nombre,           # cache denormalizado
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
    return _material_out(db, mat, empresa_id)


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

    if body.codigo      is not None: mat.codigo      = (body.codigo or "").strip() or mat.codigo
    if body.nombre      is not None: mat.nombre      = body.nombre.strip() or mat.nombre
    if body.descripcion is not None: mat.descripcion = (body.descripcion or "").strip() or None
    if body.precio      is not None: mat.precio      = body.precio
    if body.activo      is not None: mat.activo      = bool(body.activo)
    if body.categoriaId is not None:
        cat = _categoria_or_404(db, empresa_id, body.categoriaId)
        mat.categoria_id = cat.id
    if body.unidadId is not None:
        uni = _unidad_or_404(db, empresa_id, body.unidadId)
        mat.unidad = uni.nombre

    if body.cantidad is not None or body.stockMinimo is not None or body.almacenId is not None:
        alm = _almacen_or_404(db, empresa_id, body.almacenId) if body.almacenId else None

        stock = db.query(Stock).filter(
            Stock.material_id == mat.id, Stock.empresa_id == empresa_id
        ).first()
        if not stock:
            if not alm:
                # Crear en el primer almacén disponible si aún no hay stock
                alm = db.query(Almacen).filter(Almacen.empresa_id == empresa_id).first()
            stock = Stock(
                material_id=mat.id, empresa_id=empresa_id,
                almacen_id=alm.id if alm else None,
                cantidad=0, cantidad_minima=0,
            )
            db.add(stock)

        if body.cantidad     is not None: stock.cantidad        = max(0, int(body.cantidad))
        if body.stockMinimo  is not None: stock.cantidad_minima = max(0, int(body.stockMinimo))
        if alm and stock.almacen_id != alm.id:
            stock.almacen_id = alm.id
        stock.updated_at = datetime.utcnow()

    db.commit()
    return _material_out(db, mat, empresa_id)


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

    # Resolver FKs opcionales (cache denormalizado por nombre)
    tipo_nombre = None
    if body.tipoId:
        t = _tipo_or_404(db, empresa_id, body.tipoId)
        tipo_nombre = t.nombre

    marca_nombre = None
    if body.marcaId:
        ma = _marca_or_404(db, empresa_id, body.marcaId)
        marca_nombre = ma.nombre

    modelo_nombre = None
    if body.modeloId:
        mo = _modelo_or_404(db, empresa_id, body.modeloId)
        if body.marcaId and mo.marca_id != body.marcaId:
            raise HTTPException(status_code=400, detail="El modelo no pertenece a la marca indicada")
        modelo_nombre = mo.nombre

    if body.almacenId:
        _almacen_or_404(db, empresa_id, body.almacenId)

    # Autogeneración de código: EQ-NNNN o HR-NNNN según clase
    prefijo = "EQ" if body.clase == "equipo" else "HR"
    codigo = (body.codigo or "").strip() or _siguiente_codigo(db, empresa_id, prefijo, Equipo)

    e = Equipo(
        id           = str(_uuid.uuid4()),
        empresa_id   = empresa_id,
        nombre       = body.nombre.strip(),
        codigo       = codigo,
        clase        = body.clase,
        tipo_equipo_id = body.tipoId,
        tipo         = tipo_nombre,
        marca_id     = body.marcaId,
        marca        = marca_nombre,
        modelo_id    = body.modeloId,
        modelo       = modelo_nombre,
        numero_serie = (body.numeroSerie or "").strip() or None,
        almacen_id   = body.almacenId,
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

    if body.codigo      is not None: e.codigo      = (body.codigo or "").strip() or e.codigo
    if body.nombre      is not None: e.nombre      = body.nombre.strip() or e.nombre
    if body.clase       is not None: e.clase       = body.clase
    if body.numeroSerie is not None: e.numero_serie= (body.numeroSerie or "").strip() or None
    if body.cantidad    is not None: e.cantidad    = max(0, int(body.cantidad))
    if body.estado      is not None: e.estado      = body.estado
    if body.fechaAdquisicion is not None: e.fecha_adquisicion = body.fechaAdquisicion
    if body.fichaTecnica     is not None: e.ficha_tecnica     = (body.fichaTecnica or "").strip() or None

    if body.tipoId is not None:
        if body.tipoId == "":
            e.tipo_equipo_id = None; e.tipo = None
        else:
            t = _tipo_or_404(db, empresa_id, body.tipoId)
            e.tipo_equipo_id = t.id; e.tipo = t.nombre
    if body.marcaId is not None:
        if body.marcaId == "":
            e.marca_id = None; e.marca = None
            e.modelo_id = None; e.modelo = None
        else:
            ma = _marca_or_404(db, empresa_id, body.marcaId)
            e.marca_id = ma.id; e.marca = ma.nombre
            # Si la marca cambia, invalidar modelo si ya no le pertenece
            if e.modelo_id:
                mo_actual = db.query(ModeloEquipo).filter(ModeloEquipo.id == e.modelo_id).first()
                if not mo_actual or mo_actual.marca_id != ma.id:
                    e.modelo_id = None; e.modelo = None
    if body.modeloId is not None:
        if body.modeloId == "":
            e.modelo_id = None; e.modelo = None
        else:
            mo = _modelo_or_404(db, empresa_id, body.modeloId)
            if e.marca_id and mo.marca_id != e.marca_id:
                raise HTTPException(status_code=400, detail="El modelo no pertenece a la marca indicada")
            e.modelo_id = mo.id; e.modelo = mo.nombre
            # Si no tenía marca, la inferimos desde el modelo
            if not e.marca_id:
                ma_inf = db.query(Marca).filter(Marca.id == mo.marca_id).first()
                if ma_inf:
                    e.marca_id = ma_inf.id; e.marca = ma_inf.nombre
    if body.almacenId is not None:
        if body.almacenId == "":
            e.almacen_id = None; e.ubicacion = None
        else:
            alm = _almacen_or_404(db, empresa_id, body.almacenId)
            e.almacen_id = alm.id
            e.ubicacion = alm.nombre

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
# KPIs + Siguiente código (preview para el frontend)
# ══════════════════════════════════════════════════════════════════════════

@router.get("/kpis", response_model=LogisticaKpis)
def kpis(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]

    total_mat = db.query(func.count(Material.id)).filter(
        Material.empresa_id == empresa_id
    ).scalar() or 0

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


@router.get("/siguiente-codigo")
def siguiente_codigo(
    tipo:    str = Query(..., description="material|equipo|herramienta"),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Devuelve el próximo código que se asignará (preview para el formulario)."""
    empresa_id = payload["empresa_id"]
    t = tipo.lower()
    if t == "material":
        return {"codigo": _siguiente_codigo(db, empresa_id, "MAT", Material)}
    if t == "equipo":
        return {"codigo": _siguiente_codigo(db, empresa_id, "EQ",  Equipo)}
    if t == "herramienta":
        return {"codigo": _siguiente_codigo(db, empresa_id, "HR",  Equipo)}
    raise HTTPException(status_code=400, detail="tipo debe ser material|equipo|herramienta")


# ══════════════════════════════════════════════════════════════════════════
# REQUERIMIENTOS (HU-16) — Control de stock y aprobación de pedidos
# ══════════════════════════════════════════════════════════════════════════

def _stock_de_material(db: Session, material_id: str, empresa_id: str) -> int:
    total = (
        db.query(func.coalesce(func.sum(Stock.cantidad), 0))
        .filter(Stock.material_id == material_id, Stock.empresa_id == empresa_id)
        .scalar()
    )
    return int(total or 0)


def _nombre_empleado(db: Session, empleado_id: str | None) -> tuple[str, str | None]:
    """Devuelve (nombre_completo, foto_url) del empleado vía su usuario."""
    if not empleado_id:
        return "—", None
    row = (
        db.query(Usuario.nombre, Usuario.apellido, Usuario.foto_url)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == empleado_id)
        .first()
    )
    if not row:
        return "—", None
    return f"{row[0]} {row[1]}".strip(), row[2]


def _req_out(db: Session, req: Requerimiento, empresa_id: str) -> RequerimientoOut:
    # Proyecto / servicio
    proyecto = db.query(Proyecto).filter(Proyecto.id == req.proyecto_id).first()
    proyecto_nombre = proyecto.nombre_proyecto if proyecto else "Proyecto"

    servicio_nombre = None
    if req.proyecto_servicio_id:
        srv = db.query(ProyectoServicio).filter(ProyectoServicio.id == req.proyecto_servicio_id).first()
        servicio_nombre = srv.nombre if srv else None

    solicitante_nombre, solicitante_foto = _nombre_empleado(db, req.solicitante_id)

    # Ítems
    detalles = (
        db.query(RequerimientoDetalle, Material.nombre, Material.unidad)
        .outerjoin(Material, Material.id == RequerimientoDetalle.material_id)
        .filter(RequerimientoDetalle.requerimiento_id == req.id)
        .all()
    )
    items: list[RequerimientoItemOut] = []
    for d, mat_nombre, mat_unidad in detalles:
        es_externa = d.material_id is None
        stock = 0 if es_externa else _stock_de_material(db, d.material_id, empresa_id)
        items.append(RequerimientoItemOut(
            id=str(d.id),
            materialId=str(d.material_id) if d.material_id else None,
            nombre=mat_nombre or d.nombre_libre or "—",
            unidad=mat_unidad or d.unidad_libre or "",
            cantidad=int(d.cantidad or 0),
            cantidadAprobada=d.cantidad_aprobada,
            stockDisponible=stock,
            enStock=(not es_externa and stock >= int(d.cantidad or 0)),
            esCompraExterna=es_externa,
            especificacion=d.especificacion,
            estadoItem=d.estado_item or "pendiente",
            agregadoPor=None,
        ))

    # Entrega
    entrega = (
        db.query(RequerimientoEntrega)
        .filter(RequerimientoEntrega.requerimiento_id == req.id)
        .order_by(RequerimientoEntrega.created_at.desc())
        .first()
    )
    entregado_nombre = recibido_nombre = firma_url = fecha_entrega = None
    if entrega:
        entregado_nombre, _ = _nombre_empleado(db, entrega.entregado_por_id)
        recibido_nombre, _  = _nombre_empleado(db, entrega.recibido_por_id)
        firma_url = entrega.firma_receptor_url
        fecha_entrega = entrega.fecha_entrega.isoformat() if entrega.fecha_entrega else None

    return RequerimientoOut(
        id=str(req.id), estado=req.estado or "pendiente",
        fecha=req.fecha.strftime("%d %b %Y") if req.fecha else None,
        observacion=req.observacion,
        observacionLogistico=req.observacion_logistico,
        proyectoId=str(req.proyecto_id) if req.proyecto_id else None,
        proyectoNombre=proyecto_nombre,
        servicioId=str(req.proyecto_servicio_id) if req.proyecto_servicio_id else None,
        servicioNombre=servicio_nombre,
        solicitanteId=str(req.solicitante_id) if req.solicitante_id else None,
        solicitanteNombre=solicitante_nombre,
        solicitanteFoto=solicitante_foto,
        items=items,
        entregadoPorNombre=entregado_nombre,
        recibidoPorNombre=recibido_nombre,
        firmaUrl=firma_url,
        fechaEntrega=fecha_entrega,
    )


@router.get("/requerimientos", response_model=RequerimientosListResponse)
def listar_requerimientos(
    estado:      str = Query("pendiente", description="pendiente|aprobado|listo|entregado|rechazado|todos"),
    proyecto_id: str = Query(""),
    servicio_id: str = Query(""),
    q:           str = Query(""),
    page:        int = Query(1, ge=1),
    page_size:   int = Query(30, ge=1, le=200),
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Lista requerimientos para el panel de Logística (excluye borradores)."""
    empresa_id = payload["empresa_id"]
    base = db.query(Requerimiento).filter(
        Requerimiento.empresa_id == empresa_id,
        Requerimiento.estado != "borrador",
    )
    if estado and estado != "todos":
        base = base.filter(Requerimiento.estado == estado)
    if proyecto_id:
        base = base.filter(Requerimiento.proyecto_id == proyecto_id)
    if servicio_id:
        base = base.filter(Requerimiento.proyecto_servicio_id == servicio_id)

    total = base.count()
    rows = (
        base.order_by(Requerimiento.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    items = [_req_out(db, r, empresa_id) for r in rows]

    if q:
        ql = q.lower()
        items = [
            it for it in items
            if ql in it.proyectoNombre.lower()
            or ql in (it.servicioNombre or "").lower()
            or ql in it.solicitanteNombre.lower()
            or any(ql in i.nombre.lower() for i in it.items)
        ]

    return RequerimientosListResponse(items=items, total=total, page=page, pageSize=page_size)


@router.get("/requerimientos/historial", response_model=RequerimientosListResponse)
def historial_requerimientos(
    proyecto_id: str = Query(""),
    servicio_id: str = Query(""),
    page:        int = Query(1, ge=1),
    page_size:   int = Query(50, ge=1, le=200),
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Historial de consumo: requerimientos ya aprobados / entregados / rechazados."""
    empresa_id = payload["empresa_id"]
    base = db.query(Requerimiento).filter(
        Requerimiento.empresa_id == empresa_id,
        Requerimiento.estado.in_(["aprobado", "listo", "entregado", "rechazado"]),
    )
    if proyecto_id:
        base = base.filter(Requerimiento.proyecto_id == proyecto_id)
    if servicio_id:
        base = base.filter(Requerimiento.proyecto_servicio_id == servicio_id)

    total = base.count()
    rows = (
        base.order_by(Requerimiento.updated_at.desc().nullslast(), Requerimiento.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return RequerimientosListResponse(
        items=[_req_out(db, r, empresa_id) for r in rows],
        total=total, page=page, pageSize=page_size,
    )


@router.get("/requerimientos/{req_id}", response_model=RequerimientoOut)
def detalle_requerimiento(
    req_id:  str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    return _req_out(db, req, empresa_id)


@router.post("/requerimientos/{req_id}/aprobar", response_model=RequerimientoOut)
def aprobar_requerimiento(
    req_id:  str,
    body:    AprobarBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Procesa la decisión por ítem:
      * aprobar → resta stock (movimiento salida) y marca estado_item='aprobado'
      * compra  → marca 'para_compra' (genera ticket de compra, sin tocar stock)
      * rechazar→ marca 'rechazado'
    El requerimiento pasa a 'aprobado' (listo para entregar) si hay al menos un ítem aprobado.
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    if req.estado not in ("pendiente",):
        raise HTTPException(status_code=409, detail="El requerimiento ya fue procesado")

    # empleado logístico (responsable del movimiento)
    emp_log = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    # almacén de salida
    almacen_id = body.almacenId
    if not almacen_id:
        alm = db.query(Almacen).filter(Almacen.empresa_id == empresa_id).first()
        almacen_id = str(alm.id) if alm else None

    decisiones = {d.detalleId: d for d in body.decisiones}

    detalles = db.query(RequerimientoDetalle).filter(
        RequerimientoDetalle.requerimiento_id == req.id
    ).all()

    hay_aprobado = False
    for d in detalles:
        dec = decisiones.get(str(d.id))
        # Por defecto: si está en stock se aprueba, si no, va a compra
        if dec is None:
            es_externa = d.material_id is None
            stock = 0 if es_externa else _stock_de_material(db, d.material_id, empresa_id)
            decision = "aprobar" if (not es_externa and stock >= int(d.cantidad or 0)) else "compra"
            cant_aprob = int(d.cantidad or 0)
        else:
            decision = dec.decision
            cant_aprob = dec.cantidadAprobada if dec.cantidadAprobada is not None else int(d.cantidad or 0)

        if decision == "aprobar" and d.material_id:
            disponible = _stock_de_material(db, d.material_id, empresa_id)
            cant_aprob = min(cant_aprob, disponible)
            if cant_aprob <= 0:
                # sin stock real → mandar a compra
                d.estado_item = "para_compra"
                d.cantidad_aprobada = 0
                continue

            # Resta de stock (del almacén con más cantidad disponible)
            restante = cant_aprob
            stocks = (
                db.query(Stock)
                .filter(Stock.material_id == d.material_id, Stock.empresa_id == empresa_id, Stock.cantidad > 0)
                .order_by(Stock.cantidad.desc())
                .all()
            )
            for s in stocks:
                if restante <= 0:
                    break
                quita = min(int(s.cantidad), restante)
                s.cantidad = int(s.cantidad) - quita
                s.updated_at = datetime.utcnow()
                restante -= quita

            # Movimiento de inventario (registro de salida — auditoría/proyección)
            db.add(MovimientoInventario(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                material_id=d.material_id, almacen_id=almacen_id,
                tipo="salida", cantidad=cant_aprob,
                referencia_id=req.id, referencia_tipo="requerimiento",
                responsable_id=emp_log.id if emp_log else None,
                fecha=datetime.utcnow(),
            ))
            d.estado_item = "aprobado"
            d.cantidad_aprobada = cant_aprob
            hay_aprobado = True

        elif decision == "compra":
            d.estado_item = "para_compra"
            d.cantidad_aprobada = cant_aprob
        else:  # rechazar
            d.estado_item = "rechazado"
            d.cantidad_aprobada = 0

    req.estado = "aprobado" if hay_aprobado else "rechazado"
    if body.observacion:
        req.observacion_logistico = body.observacion
    req.aprobado_por = emp_log.id if emp_log else None
    req.updated_at = datetime.utcnow()

    # Auto-crear TicketCompra para los ítems marcados para_compra
    detalles_compra = [d for d in detalles if d.estado_item == "para_compra"]
    if detalles_compra:
        _crear_ticket_compra(db, req, empresa_id, detalles_compra)

    db.commit()

    # Notificar al solicitante
    _notificar_solicitante(
        db, req, empresa_id,
        titulo="Requerimiento procesado",
        mensaje=f"Tu pedido de materiales fue {'aprobado' if hay_aprobado else 'rechazado'} por Logística.",
    )

    db.refresh(req)
    return _req_out(db, req, empresa_id)


@router.post("/requerimientos/{req_id}/rechazar", response_model=RequerimientoOut)
def rechazar_requerimiento(
    req_id:  str,
    body:    RechazarBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    if req.estado not in ("pendiente",):
        raise HTTPException(status_code=409, detail="El requerimiento ya fue procesado")

    req.estado = "rechazado"
    req.observacion_logistico = body.observacion
    req.updated_at = datetime.utcnow()
    for d in db.query(RequerimientoDetalle).filter(
        RequerimientoDetalle.requerimiento_id == req.id
    ).all():
        d.estado_item = "rechazado"
    db.commit()

    _notificar_solicitante(
        db, req, empresa_id,
        titulo="Requerimiento rechazado",
        mensaje=f"Tu pedido fue rechazado: {body.observacion}",
    )
    db.refresh(req)
    return _req_out(db, req, empresa_id)


@router.post("/requerimientos/{req_id}/firmar", response_model=RequerimientoOut)
def firmar_requerimiento(
    req_id:  str,
    body:    FirmarBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    El técnico (líder / jefe ops, recomendado) confirma recepción desde el
    detalle del servicio con su firma virtual. El requerimiento pasa a 'listo'
    y se notifica a Logística para que despache.
    """
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    if req.estado not in ("aprobado", "listo"):
        raise HTTPException(status_code=409, detail="Solo se firman requerimientos aprobados")

    # Firmante: el indicado o, por defecto, el empleado del usuario logueado
    if body.recibidoPorId:
        receptor = db.query(Empleado).filter(
            Empleado.id == body.recibidoPorId, Empleado.empresa_id == empresa_id
        ).first()
    else:
        receptor = db.query(Empleado).filter(
            Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
        ).first()
    if not receptor:
        raise HTTPException(status_code=404, detail="Firmante no encontrado")

    req.firma_receptor_url    = body.firmaUrl
    req.firma_recibido_por_id = receptor.id
    req.firma_fecha           = datetime.utcnow()
    req.estado                = "listo"
    req.updated_at            = datetime.utcnow()
    db.commit()

    # Notificar a Logística (responsables de almacén) — best effort: a todos
    # los usuarios con rol logística/admin de la empresa.
    try:
        logisticos = (
            db.query(Usuario)
            .filter(Usuario.empresa_id == empresa_id, Usuario.activo.is_(True))
            .all()
        )
        for u in logisticos:
            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empresa_id, usuario_id=u.id,
                tipo="info", categoria="logistica",
                titulo="Requerimiento listo para entrega",
                mensaje="Un técnico firmó la recepción. Despacha los materiales.",
                leido=False, enviado=False,
                referencia_tabla="requerimiento", referencia_id=str(req.id),
            ))
        db.commit()
    except Exception:
        db.rollback()

    db.refresh(req)
    return _req_out(db, req, empresa_id)


@router.post("/requerimientos/{req_id}/entregar", response_model=RequerimientoOut)
def entregar_requerimiento(
    req_id:  str,
    body:    EntregarBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Registra la entrega física: quién entrega (logística), quién recibe (técnico)
    y la firma virtual del receptor. Marca el requerimiento como 'entregado'.
    Usa la firma ya capturada en /firmar si el body no la trae.
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    if req.estado not in ("aprobado", "listo"):
        raise HTTPException(status_code=409, detail="Solo se entregan requerimientos aprobados")

    emp_log = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp_log:
        raise HTTPException(status_code=403, detail="No eres un empleado registrado")

    # Receptor: el del body o el que firmó previamente
    receptor_id = body.recibidoPorId or req.firma_recibido_por_id
    if not receptor_id:
        raise HTTPException(status_code=422, detail="Falta el receptor de la entrega")
    receptor = db.query(Empleado).filter(
        Empleado.id == receptor_id, Empleado.empresa_id == empresa_id
    ).first()
    if not receptor:
        raise HTTPException(status_code=404, detail="Receptor no encontrado")

    firma = body.firmaUrl or req.firma_receptor_url

    db.add(RequerimientoEntrega(
        id=str(_uuid.uuid4()), requerimiento_id=req.id, empresa_id=empresa_id,
        entregado_por_id=emp_log.id, recibido_por_id=receptor.id,
        firma_receptor_url=firma, fecha_entrega=datetime.utcnow(),
        notas=body.notas,
    ))
    req.estado = "entregado"
    req.updated_at = datetime.utcnow()
    db.commit()

    _notificar_solicitante(
        db, req, empresa_id,
        titulo="Materiales entregados",
        mensaje="Logística registró la entrega de tus materiales.",
    )
    db.refresh(req)
    return _req_out(db, req, empresa_id)


def _notificar_solicitante(db: Session, req: Requerimiento, empresa_id: str, titulo: str, mensaje: str) -> None:
    """Crea una notificación para el usuario solicitante (silenciosa si falla)."""
    try:
        if not req.solicitante_id:
            return
        emp = db.query(Empleado).filter(Empleado.id == req.solicitante_id).first()
        if not emp:
            return
        db.add(Notificacion(
            id=str(_uuid.uuid4()), empresa_id=empresa_id, usuario_id=emp.usuario_id,
            tipo="info", categoria="logistica",
            titulo=titulo, mensaje=mensaje,
            leido=False, enviado=False,
            referencia_tabla="requerimiento", referencia_id=str(req.id),
        ))
        db.commit()
    except Exception:
        db.rollback()


# ══════════════════════════════════════════════════════════════════════════
# COMPRAS (HU-17) — Tickets generados desde requerimientos aprobados
# ══════════════════════════════════════════════════════════════════════════

def _siguiente_codigo_ticket(db: Session, empresa_id: str) -> str:
    rows = db.query(TicketCompra.codigo).filter(
        TicketCompra.empresa_id == empresa_id,
        TicketCompra.codigo.ilike("TC-%"),
    ).all()
    max_n = 0
    pat = re.compile(r"^TC-(\d+)$", re.IGNORECASE)
    for (c,) in rows:
        if c:
            m = pat.match(c.strip())
            if m:
                n = int(m.group(1))
                if n > max_n:
                    max_n = n
    return f"TC-{(max_n + 1):04d}"


def _ticket_item_out(it: TicketCompraItem) -> TicketCompraItemOut:
    return TicketCompraItemOut(
        id=str(it.id),
        ticketId=str(it.ticket_id),
        materialId=it.material_id,
        nombre=it.nombre,
        cantidad=int(it.cantidad or 0),
        cantidadComprada=int(it.cantidad_comprada) if it.cantidad_comprada is not None else None,
        unidad=it.unidad or "",
        precioUnitario=float(it.precio_unitario) if it.precio_unitario is not None else None,
        totalItem=float(it.total_item) if it.total_item is not None else None,
        proveedorId=it.proveedor_id,
        proveedorNombre=it.proveedor_nombre,
        canalPersonalizado=it.canal_personalizado,
        factura=it.factura,
        estadoItem=it.estado_item or "pendiente",
        nota=it.nota,
    )


def _ticket_out(db: Session, tc: TicketCompra) -> TicketCompraOut:
    items_db = (
        db.query(TicketCompraItem)
        .filter(TicketCompraItem.ticket_id == tc.id)
        .all()
    )
    return TicketCompraOut(
        id=str(tc.id),
        codigo=tc.codigo,
        requerimientoId=tc.requerimiento_id,
        proyectoId=tc.proyecto_id,
        proyectoNombre=tc.proyecto_nombre or "—",
        servicioId=tc.proyecto_servicio_id,
        servicioNombre=tc.servicio_nombre,
        solicitanteNombre=tc.solicitante_nombre or "—",
        estado=tc.estado or "pendiente",
        items=[_ticket_item_out(it) for it in items_db],
        modoUnificado=tc.modo_unificado,
        proveedorUnicoId=tc.proveedor_unico_id,
        proveedorUnicoNombre=tc.proveedor_unico_nombre,
        canalUnico=tc.canal_unico,
        totalEstimado=float(tc.total_estimado) if tc.total_estimado is not None else None,
        totalReal=float(tc.total_real) if tc.total_real is not None else None,
        responsableId=tc.responsable_id,
        responsableNombre=None,
        nota=tc.nota,
        creadoEn=tc.created_at.isoformat() if tc.created_at else "",
        actualizadoEn=tc.updated_at.isoformat() if tc.updated_at else None,
    )


def _crear_ticket_compra(
    db: Session,
    req: Requerimiento,
    empresa_id: str,
    detalles_compra: list,
) -> TicketCompra | None:
    """Crea un TicketCompra con los ítems marcados 'para_compra'. Idempotente."""
    if not detalles_compra:
        return None

    # Si ya existe un ticket para este requerimiento, no duplicar
    existente = db.query(TicketCompra).filter(
        TicketCompra.requerimiento_id == req.id,
        TicketCompra.empresa_id == empresa_id,
        TicketCompra.estado != "cancelado",
    ).first()
    if existente:
        return existente

    # Datos de contexto
    proyecto = db.query(Proyecto).filter(Proyecto.id == req.proyecto_id).first()
    proyecto_nombre = proyecto.nombre_proyecto if proyecto else "Proyecto"
    servicio_nombre = None
    if req.proyecto_servicio_id:
        srv = db.query(ProyectoServicio).filter(ProyectoServicio.id == req.proyecto_servicio_id).first()
        servicio_nombre = srv.nombre if srv else None
    sol_nombre, _ = _nombre_empleado(db, req.solicitante_id)

    codigo = _siguiente_codigo_ticket(db, empresa_id)
    tc = TicketCompra(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        requerimiento_id=str(req.id),
        codigo=codigo,
        estado="pendiente",
        proyecto_id=str(req.proyecto_id) if req.proyecto_id else None,
        proyecto_servicio_id=str(req.proyecto_servicio_id) if req.proyecto_servicio_id else None,
        proyecto_nombre=proyecto_nombre,
        servicio_nombre=servicio_nombre,
        solicitante_nombre=sol_nombre,
        created_at=datetime.utcnow(),
    )
    db.add(tc)
    db.flush()  # necesitamos tc.id para los ítems

    for d in detalles_compra:
        nombre = d.nombre_libre or "—"
        unidad = d.unidad_libre or ""
        if d.material_id:
            mat = db.query(Material).filter(Material.id == d.material_id).first()
            if mat:
                nombre = mat.nombre
                unidad = mat.unidad or unidad
        db.add(TicketCompraItem(
            id=str(_uuid.uuid4()),
            ticket_id=tc.id,
            requerimiento_detalle_id=str(d.id),
            material_id=str(d.material_id) if d.material_id else None,
            nombre=nombre,
            cantidad=int(d.cantidad or 0),
            unidad=unidad,
            estado_item="pendiente",
        ))

    return tc


@router.get("/compras", response_model=ComprasListResponse)
def listar_compras(
    estado:      str = Query("pendiente", description="pendiente|en_proceso|completado|cancelado|todos"),
    proyecto_id: str = Query(""),
    q:           str = Query(""),
    page:        int = Query(1, ge=1),
    page_size:   int = Query(50, ge=1, le=200),
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    base = db.query(TicketCompra).filter(TicketCompra.empresa_id == empresa_id)

    if estado and estado != "todos":
        base = base.filter(TicketCompra.estado == estado)
    if proyecto_id:
        base = base.filter(TicketCompra.proyecto_id == proyecto_id)

    total = base.count()
    rows = (
        base.order_by(TicketCompra.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    items = [_ticket_out(db, tc) for tc in rows]

    if q:
        ql = q.lower()
        items = [
            it for it in items
            if ql in it.proyectoNombre.lower()
            or ql in (it.servicioNombre or "").lower()
            or ql in it.solicitanteNombre.lower()
            or ql in it.codigo.lower()
            or any(ql in i.nombre.lower() for i in it.items)
        ]

    return ComprasListResponse(items=items, total=total, page=page, pageSize=page_size)


@router.get("/compras/resumen", response_model=ComprasResumen)
def resumen_compras(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Conteo de tickets por estado para los KPIs del encabezado."""
    empresa_id = payload["empresa_id"]
    from sqlalchemy import case as sql_case

    row = db.query(
        func.count(sql_case((TicketCompra.estado == "pendiente",  1))).label("pendiente"),
        func.count(sql_case((TicketCompra.estado == "en_proceso", 1))).label("en_proceso"),
        func.count(sql_case((TicketCompra.estado == "completado", 1))).label("completado"),
        func.count(sql_case((TicketCompra.estado == "cancelado",  1))).label("cancelado"),
    ).filter(TicketCompra.empresa_id == empresa_id).first()

    return ComprasResumen(
        pendiente  = row.pendiente  or 0,
        en_proceso = row.en_proceso or 0,
        completado = row.completado or 0,
        cancelado  = row.cancelado  or 0,
    )


@router.get("/compras/{ticket_id}", response_model=TicketCompraOut)
def detalle_compra(
    ticket_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    tc = db.query(TicketCompra).filter(
        TicketCompra.id == ticket_id,
        TicketCompra.empresa_id == empresa_id,
    ).first()
    if not tc:
        raise HTTPException(status_code=404, detail="Ticket de compra no encontrado")
    return _ticket_out(db, tc)


@router.patch("/compras/{ticket_id}/procesar", response_model=TicketCompraOut)
def procesar_compra(
    ticket_id: str,
    body:      ProcesarCompraBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    tc = db.query(TicketCompra).filter(
        TicketCompra.id == ticket_id,
        TicketCompra.empresa_id == empresa_id,
    ).first()
    if not tc:
        raise HTTPException(status_code=404, detail="Ticket de compra no encontrado")
    if tc.estado in ("completado", "cancelado"):
        raise HTTPException(status_code=409, detail=f"El ticket ya está {tc.estado}")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    # Mapa itemId → body
    items_map = {b.itemId: b for b in body.items}

    total_real = 0.0
    for it in db.query(TicketCompraItem).filter(TicketCompraItem.ticket_id == tc.id).all():
        b = items_map.get(str(it.id))
        if b is None:
            continue
        it.cantidad_comprada = b.cantidadComprada
        it.precio_unitario   = b.precioUnitario
        it.total_item        = (b.cantidadComprada or 0) * (b.precioUnitario or 0)
        it.factura           = b.factura
        it.nota              = b.nota

        # Proveedor / canal
        if body.modoUnificado:
            it.proveedor_id        = body.proveedorUnicoId
            it.proveedor_nombre    = body.proveedorUnicoNombre
            it.canal_personalizado = body.canalUnico
        else:
            it.proveedor_id        = b.proveedorId
            it.proveedor_nombre    = b.proveedorNombre
            it.canal_personalizado = b.canalPersonalizado

        it.estado_item = "comprado" if (b.cantidadComprada or 0) > 0 else "pendiente"
        total_real += float(it.total_item or 0)

    # Actualizar cabecera del ticket
    tc.modo_unificado         = body.modoUnificado
    tc.proveedor_unico_id     = body.proveedorUnicoId if body.modoUnificado else None
    tc.proveedor_unico_nombre = body.proveedorUnicoNombre if body.modoUnificado else None
    tc.canal_unico            = body.canalUnico if body.modoUnificado else None
    tc.nota                   = body.nota
    tc.total_real             = total_real
    tc.responsable_id         = str(emp.id) if emp else None
    tc.estado                 = "completado" if body.completado else "en_proceso"
    tc.updated_at             = datetime.utcnow()

    db.commit()
    db.refresh(tc)
    return _ticket_out(db, tc)


@router.post("/compras/{ticket_id}/cancelar", response_model=TicketCompraOut)
def cancelar_compra(
    ticket_id: str,
    body:      CancelarCompraBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    tc = db.query(TicketCompra).filter(
        TicketCompra.id == ticket_id,
        TicketCompra.empresa_id == empresa_id,
    ).first()
    if not tc:
        raise HTTPException(status_code=404, detail="Ticket de compra no encontrado")
    if tc.estado == "cancelado":
        raise HTTPException(status_code=409, detail="El ticket ya está cancelado")

    tc.estado              = "cancelado"
    tc.motivo_cancelacion  = body.motivo
    tc.updated_at          = datetime.utcnow()
    db.commit()
    db.refresh(tc)
    return _ticket_out(db, tc)


# ══════════════════════════════════════════════════════════════════════════
# PROVEEDORES — CRUD básico
# ══════════════════════════════════════════════════════════════════════════

def _prov_out(db: Session, p: ProveedorModel) -> ProveedorOut:
    cats = (
        db.query(CategoriaMaterial.nombre)
        .join(ProveedorCategoria, ProveedorCategoria.categoria_id == CategoriaMaterial.id)
        .filter(ProveedorCategoria.proveedor_id == p.id)
        .all()
    )
    return ProveedorOut(
        id       = str(p.id),
        nombre   = p.razon_social,
        ruc      = p.ruc,
        contacto = p.telefono or p.contacto,
        email    = p.email,
        rating   = getattr(p, "rating", 0) or 0,
        categorias = [c[0] for c in cats],
        activo   = bool(p.activo),
    )


@router.get("/proveedores", response_model=List[ProveedorOut])
def listar_proveedores(
    solo_activos: bool = Query(True),
    q:            str  = Query(""),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    base = db.query(ProveedorModel).filter(ProveedorModel.empresa_id == empresa_id)
    if solo_activos:
        base = base.filter(ProveedorModel.activo.is_(True))
    if q:
        like = f"%{q.lower()}%"
        base = base.filter(func.lower(ProveedorModel.razon_social).like(like))
    rows = base.order_by(ProveedorModel.razon_social).all()
    return [_prov_out(db, p) for p in rows]


@router.post("/proveedores", response_model=ProveedorOut, status_code=201)
def crear_proveedor(
    body:    ProveedorIn,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")

    existente = db.query(ProveedorModel).filter(
        ProveedorModel.empresa_id == empresa_id,
        func.lower(ProveedorModel.razon_social) == nombre.lower(),
    ).first()
    if existente:
        return _prov_out(db, existente)

    p = ProveedorModel(
        id           = str(_uuid.uuid4()),
        empresa_id   = empresa_id,
        razon_social = nombre,
        ruc          = (body.ruc or "").strip() or None,
        contacto     = None,
        telefono     = (body.contacto or "").strip() or None,
        email        = (body.email or "").strip() or None,
        activo       = True,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return _prov_out(db, p)
