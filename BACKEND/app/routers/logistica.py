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

from ..schemas.logistica import (
    MaterialIn, MaterialPatch, MaterialOut, MaterialesListResponse,
    EquipoIn,   EquipoPatch,   EquipoOut,   EquiposListResponse,
    LogisticaKpis,
    CatalogoItem, CatalogoIn,
    AlmacenOut, AlmacenIn,
    UnidadOut,  UnidadIn,
    ModeloOut,  ModeloIn,
)


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
