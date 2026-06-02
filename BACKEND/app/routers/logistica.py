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
from ..models.proyecto_miembro import ProyectoMiembro
from ..models.firma_digital import FirmaDigital
from ..models.notificacion import Notificacion
from ..models.proveedor import Proveedor as ProveedorModel, ProveedorCategoria
from ..models.retorno import Retorno, RetornoDetalle
from ..models.incidencia import Incidencia

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
    IngresoItemBody, RegistrarIngresoBody, VincularInventarioBody,
    SalidaItemOut, SalidaOut, SalidasListResponse, SalidasKpis,
    IngresoItemOut, IngresoOut, IngresosListResponse,
    RetornoDetalleOut, RetornoOut, RetornosListResponse,
    CrearRetornoBody, CrearRetornoServicioBody, InspectionarRetornoBody,
    CrearIncidenciaBody, ResolverIncidenciaBody,
    IncidenciaOut, IncidenciasListResponse, EquipoStockDesglose,
)
from datetime import date as _date


router = APIRouter(prefix="/logistica", tags=["logistica"])


# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

def _autorizar_logistica(payload: dict) -> None:
    """Solo logística / admin / superadmin pueden mutar inventario y catálogos.

    Acepta el nombre real del rol en BD ('Logístico') además de variantes; el
    admin (administrador/admin/superadmin) siempre pasa. Equivale al permiso
    inventario:gestionar dado el seed de rol_permiso.
    """
    rol = (payload.get("rol") or "").lower().strip()
    if rol in ("logística", "logistica", "logístico", "logistico",
               "administrador", "admin", "superadmin"):
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
        tipo=getattr(mat, "tipo", "consumible") or "consumible",
    )


def _equipo_out(e: Equipo) -> EquipoOut:
    # Normalizar clase: valores legacy como 'equipo_tecnologico' se mapean a 'equipo'
    clase_raw = (e.clase or "equipo").lower()
    clase = clase_raw if clase_raw in ("equipo", "herramienta") else "equipo"
    return EquipoOut(
        id=str(e.id), codigo=e.codigo or "", nombre=e.nombre,
        clase=clase,
        tipoId=str(e.tipo_equipo_id) if e.tipo_equipo_id else None,
        tipo=e.tipo or "",
        marcaId=str(e.marca_id) if e.marca_id else None,
        marca=e.marca,
        modeloId=str(e.modelo_id) if e.modelo_id else None,
        modelo=e.modelo,
        numeroSerie=e.numero_serie,
        almacenId=str(e.almacen_id) if e.almacen_id else None,
        ubicacion=e.ubicacion,
        ubicacionId=str(e.ubicacion_id) if e.ubicacion_id else None,
        zonaId=str(e.zona_id) if e.zona_id else None,
        areaId=str(e.area_id) if e.area_id else None,
        cantidad=int(e.cantidad or 1),
        estado=(e.estado if e.estado in ("operativo","en_mantenimiento","fuera_de_servicio","baja") else "operativo"),
        requiereMantenimiento=bool(e.requiere_mantenimiento),
        frecuenciaMantenimiento=(e.frecuencia_mantenimiento if e.frecuencia_mantenimiento in ("ninguno","mensual","trimestral","semestral","anual") else "ninguno"),
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


@router.delete("/categorias/{categoria_id}", status_code=200)
def eliminar_categoria(
    categoria_id: str,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    """Baja una categoría. Falla con 409 si tiene materiales asociados."""
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    cat = db.query(CategoriaMaterial).filter(
        CategoriaMaterial.id == categoria_id,
        CategoriaMaterial.empresa_id == empresa_id,
    ).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")

    en_uso = db.query(func.count(Material.id)).filter(
        Material.categoria_id == categoria_id,
        Material.empresa_id == empresa_id,
    ).scalar() or 0
    if en_uso > 0:
        raise HTTPException(
            status_code=409,
            detail=f"La categoría está en uso por {en_uso} material(es)",
        )

    db.delete(cat)
    db.commit()
    return {"ok": True}


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
    tipo:      str = Query("consumible", description="consumible|herramienta|todos"),
    page:      int = Query(1, ge=1),
    page_size: int = Query(30, ge=1, le=200),
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    base = db.query(Material).filter(Material.empresa_id == empresa_id)

    if tipo != "todos":
        base = base.filter(Material.tipo == tipo)

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
        ubicacion_id = body.ubicacionId or None,
        zona_id      = body.zonaId or None,
        area_id      = body.areaId or None,
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
    # Jerarquía geográfica (FK). "" limpia el valor.
    if body.ubicacionId is not None:
        e.ubicacion_id = body.ubicacionId or None
    if body.zonaId is not None:
        e.zona_id = body.zonaId or None
    if body.areaId is not None:
        e.area_id = body.areaId or None

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
        Equipo.empresa_id == empresa_id,
        Equipo.estado.in_(["en_mantenimiento", "fuera_de_servicio"]),
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


async def _notificar_servicio_ws(servicio_id) -> None:
    """Emite un evento de control al room WS del servicio para que el detalle
    (web/móvil) refresque la recepción de materiales en tiempo real."""
    if not servicio_id:
        return
    try:
        from .chat_ws import manager as _ws_manager
        await _ws_manager.broadcast_servicio(
            str(servicio_id), {"tipo": "requerimiento_actualizado"}
        )
    except Exception:
        pass


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
    entregado_nombre = recibido_nombre = firma_url = firma_entregador_url = fecha_entrega = None
    if entrega:
        entregado_nombre, _ = _nombre_empleado(db, entrega.entregado_por_id)
        recibido_nombre, _  = _nombre_empleado(db, entrega.recibido_por_id)
        firma_url = entrega.firma_receptor_url
        firma_entregador_url = entrega.firma_entregador_url if entrega else None
        fecha_entrega = entrega.fecha_entrega.isoformat() if entrega.fecha_entrega else None
    # Cinema-seat lock info
    firmando_por_nombre = None
    firmando_desde_iso = None
    if getattr(req, "firmando_por_id", None):
        firmando_por_nombre, _ = _nombre_empleado(db, req.firmando_por_id)
        firmando_desde_iso = req.firmando_desde.isoformat() if req.firmando_desde else None

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
        firmaEntregadorUrl=firma_entregador_url,
        firmandoPorNombre=firmando_por_nombre,
        firmandoDesde=firmando_desde_iso,
        fechaEntrega=fecha_entrega,
    )


@router.get("/requerimientos", response_model=RequerimientosListResponse)
def listar_requerimientos(
    estado:      str = Query("pendiente", description="pendiente|comprando|listo|aprobado|entregado|rechazado|activos|todos"),
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
    if estado == "activos":
        # 'aprobado' = logística firmó la entrega, pasa a historial esperando firma del técnico
        base = base.filter(Requerimiento.estado.in_(["pendiente", "comprando", "listo"]))
    elif estado and estado != "todos":
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
        Requerimiento.estado.in_(["comprando", "aprobado", "listo", "entregado", "rechazado"]),
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
async def aprobar_requerimiento(
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
            if disponible < cant_aprob:
                # Stock insuficiente para la cantidad completa solicitada.
                # Regla: NO hacer deducción parcial — esperar la compra completa.
                d.estado_item = "para_compra"
                d.cantidad_aprobada = int(d.cantidad or 0)
                continue

            # Stock suficiente para todo → deducir del inventario
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

    hay_para_compra  = any(d.estado_item == "para_compra"  for d in detalles)
    todos_rechazados = all(d.estado_item == "rechazado" for d in detalles)
    if todos_rechazados:
        req.estado = "rechazado"
    elif hay_para_compra:
        req.estado = "comprando"
    else:
        req.estado = "listo"
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
    if todos_rechazados:
        _msg = "Tu pedido de materiales fue rechazado por Logística."
    elif hay_aprobado and hay_para_compra:
        _msg = "Pedido procesado. Ítems disponibles en stock ya reservados; el resto está en proceso de compra."
    elif hay_para_compra:
        _msg = "Tu pedido fue aceptado. Los materiales están siendo adquiridos."
    else:
        _msg = "Tu pedido de materiales fue aprobado por Logística."
    _notificar_solicitante(
        db, req, empresa_id,
        titulo="Requerimiento procesado",
        mensaje=_msg,
    )
    # Recepción en vivo: avisar al room del servicio para refrescar la firma.
    await _notificar_servicio_ws(req.proyecto_servicio_id)
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
async def firmar_requerimiento(
    req_id:  str,
    body:    FirmarBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    MODELO HÍBRIDO — paso 1 de cierre (técnico):
    El técnico/líder confirma la RECEPCIÓN física de los materiales. El
    requerimiento pasa a 'aprobado' (= recibido por el equipo). Estado FINAL
    funcional para el campo. Luego logística debe cerrarlo con `entregar`
    para alcanzar 'entregado' (estado FINAL contable).

    Solo se firma lo que está 'listo'. Al firmar se libera el cinema-seat lock
    para que el detalle se actualice en tiempo real en otros dispositivos.
    Cualquier miembro del equipo puede firmar pero solo el primero cuenta
    (el lock garantiza atomicidad).
    """
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    if req.estado != "listo":
        raise HTTPException(
            status_code=409,
            detail="Solo se firma la recepción de requerimientos en estado 'listo'.",
        )

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
    req.estado                = "aprobado"   # recibido por el equipo (estado funcional final)
    # Liberar cinema-seat lock: la firma ya quedó atómicamente; el "ganador" fue
    # el primero en llegar al commit. Los demás verán el nuevo estado por WS.
    req.firmando_por_id       = None
    req.firmando_desde        = None
    req.updated_at            = datetime.utcnow()
    db.commit()

    # Notificar SOLO a los miembros del proyecto (no a toda la empresa): quien no
    # participa en el proyecto no recibe ruido. El solicitante ya se notifica aparte.
    try:
        destinatarios = set(_usuarios_de_proyecto(db, req.proyecto_id))
        for uid in destinatarios:
            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empresa_id, usuario_id=uid,
                tipo="info", categoria="logistica",
                titulo="Materiales recibidos por el equipo",
                mensaje="Un técnico firmó la recepción de los materiales.",
                leido=False, enviado=False,
                referencia_tabla="requerimiento", referencia_id=str(req.id),
            ))
        db.commit()
    except Exception:
        db.rollback()

    # Recepción en vivo: avisar al room del servicio (otros ven "recibido").
    await _notificar_servicio_ws(req.proyecto_servicio_id)

    db.refresh(req)
    return _req_out(db, req, empresa_id)


# ──────────────────────────────────────────────────────────────────────────
# FASE 4 — helper de salida de inventario al momento de entregar
# ──────────────────────────────────────────────────────────────────────────

async def _registrar_salidas_entrega(
    db:         Session,
    req:        Requerimiento,
    empresa_id: str,
    emp_log,
) -> None:
    """
    Descuenta del inventario los ítems que llegaron vía compra y registra
    el movimiento de salida vinculado al requerimiento y su servicio.

    Regla de exclusión mutua con aprobar_requerimiento:
    - Ítems de stock directo: su salida ya fue registrada en aprobar_requerimiento
      (cuando stock >= solicitado). NO se tocan aquí.
    - Ítems vía para_compra (tienen ticket_compra_item asociado): su stock fue
      sumado en _aplicar_ingreso_ticket pero nunca se descontó para el servicio.
      Se descuentan aquí al momento de la entrega formal.
    - Ítems de texto libre (sin material_id): no existen en inventario, se omiten.
    """
    # Ítems con material que pasaron por el flujo de compra
    detalles_compra = (
        db.query(RequerimientoDetalle)
        .join(TicketCompraItem,
              TicketCompraItem.requerimiento_detalle_id == RequerimientoDetalle.id)
        .filter(
            RequerimientoDetalle.requerimiento_id == req.id,
            RequerimientoDetalle.estado_item      == "aprobado",
            RequerimientoDetalle.material_id.isnot(None),
        )
        .all()
    )
    if not detalles_compra:
        return

    # Almacén activo por defecto (desde el que se despacha)
    alm = db.query(Almacen).filter(
        Almacen.empresa_id == empresa_id, Almacen.activo.is_(True)
    ).first()
    almacen_id = str(alm.id) if alm else None

    servicio_label = str(req.proyecto_servicio_id or req.proyecto_id or "")

    for d in detalles_compra:
        cant = int(d.cantidad_aprobada or d.cantidad or 0)
        if cant <= 0:
            continue

        # Descontar del almacén con más stock disponible (FIFO por cantidad)
        stocks = (
            db.query(Stock)
            .filter(
                Stock.material_id == d.material_id,
                Stock.empresa_id  == empresa_id,
                Stock.cantidad    > 0,
            )
            .order_by(Stock.cantidad.desc())
            .all()
        )
        restante = cant
        for s in stocks:
            if restante <= 0:
                break
            quita       = min(int(s.cantidad), restante)
            s.cantidad  = int(s.cantidad) - quita
            s.updated_at = datetime.utcnow()
            restante    -= quita

        # Movimiento de salida — trazable al requerimiento Y al servicio
        db.add(MovimientoInventario(
            id              = str(_uuid.uuid4()),
            empresa_id      = empresa_id,
            material_id     = d.material_id,
            almacen_id      = almacen_id,
            tipo            = "salida",
            cantidad        = cant,
            referencia_id   = req.id,
            referencia_tipo = "requerimiento",
            responsable_id  = str(emp_log.id) if emp_log else None,
            motivo          = f"Despacho al servicio {servicio_label}",
            fecha           = datetime.utcnow(),
        ))


@router.post("/requerimientos/{req_id}/entregar", response_model=RequerimientoOut)
async def entregar_requerimiento(
    req_id:  str,
    body:    EntregarBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    MODELO HÍBRIDO — paso 2 de cierre (logística):
    Cierra administrativamente un requerimiento que el técnico ya firmó
    ('aprobado' → 'entregado'). Aporta la firma del entregador como segunda
    firma (la del receptor ya está). Estado FINAL contable.

    Precondición estricta: estado='aprobado' (= el técnico ya firmó).
    Requiere `firmaEntregadorUrl` y reusa el receptor ya registrado en
    `firma_recibido_por_id`. No se acepta cerrar sin firma del receptor previa.
    """
    # Cualquier usuario autenticado puede confirmar la recepción (técnico o logística)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    if req.estado != "aprobado":
        raise HTTPException(
            status_code=409,
            detail="Solo se confirma la recepción de un requerimiento 'aprobado' (entregado por logística).",
        )
    if not body.firmaEntregadorUrl:
        raise HTTPException(
            status_code=422,
            detail="Se requiere la firma del entregador (firmaEntregadorUrl).",
        )

    emp_log = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp_log:
        raise HTTPException(status_code=403, detail="No eres un empleado registrado")

    # Receptor: el ya firmante (garantizado por la precondición 'aprobado').
    # Si por algún motivo no está (datos sucios), 422 explícito.
    receptor_id = req.firma_recibido_por_id
    if not receptor_id:
        raise HTTPException(
            status_code=422,
            detail="El requerimiento no tiene firma de receptor (datos inconsistentes).",
        )
    receptor = db.query(Empleado).filter(
        Empleado.id == receptor_id, Empleado.empresa_id == empresa_id
    ).first()
    if not receptor:
        raise HTTPException(status_code=404, detail="Receptor original no encontrado")

    db.add(RequerimientoEntrega(
        id=str(_uuid.uuid4()), requerimiento_id=req.id, empresa_id=empresa_id,
        entregado_por_id=emp_log.id, recibido_por_id=receptor.id,
        firma_receptor_url=req.firma_receptor_url,
        firma_entregador_url=body.firmaEntregadorUrl,
        fecha_entrega=datetime.utcnow(),
        notas=body.notas,
    ))
    req.firma_entregador_url = body.firmaEntregadorUrl
    req.estado = "entregado"
    # El lock ya está liberado tras firmar; lo limpiamos por idempotencia.
    req.firmando_por_id = None
    req.firmando_desde  = None
    req.updated_at = datetime.utcnow()

    # ── Fase 4: descuento de stock para ítems vía compra ─────────────────
    # Los ítems de stock directo ya fueron descontados en aprobar_requerimiento.
    # Los ítems que pasaron por ticket_compra necesitan su salida aquí.
    await _registrar_salidas_entrega(db, req, empresa_id, emp_log)

    db.commit()

    _notificar_solicitante(
        db, req, empresa_id,
        titulo="Entrega cerrada por logística",
        mensaje="Logística cerró contablemente la entrega de tus materiales.",
    )
    # Notificar en vivo al room del servicio (otros ven el cierre)
    await _notificar_servicio_ws(req.proyecto_servicio_id)
    db.refresh(req)
    return _req_out(db, req, empresa_id)




@router.post("/requerimientos/{req_id}/bloquear-firma")
async def bloquear_firma_requerimiento(
    req_id:  str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Bloquea la firma (cinema-seat, 2-min timeout). 409 si ya bloqueado.
    Emite WS para que otros miembros vean 'X está firmando' sin recargar."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")
    ahora = datetime.utcnow()
    firmando_por = getattr(req, "firmando_por_id", None)
    firmando_desde = getattr(req, "firmando_desde", None)
    if firmando_por and firmando_desde:
        segundos = (ahora - firmando_desde).total_seconds()
        if segundos < 120 and firmando_por != usuario_id:
            nombre, _ = _nombre_empleado(db, firmando_por)
            raise HTTPException(status_code=409, detail=f"firmando_por:{nombre or 'otro usuario'}")
    try:
        req.firmando_por_id = usuario_id
        req.firmando_desde  = ahora
        req.updated_at      = ahora
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=409, detail="No se pudo bloquear la firma")
    # Broadcast en vivo: los demás dispositivos del equipo ven el "alguien está firmando"
    await _notificar_servicio_ws(req.proyecto_servicio_id)
    return {"ok": True}


@router.delete("/requerimientos/{req_id}/bloquear-firma")
async def liberar_firma_requerimiento(
    req_id:  str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Libera el bloqueo de firma. Emite WS para que el detalle se refresque
    en otros dispositivos (vuelve a estar disponible para firmar)."""
    empresa_id = payload["empresa_id"]
    req = db.query(Requerimiento).filter(
        Requerimiento.id == req_id, Requerimiento.empresa_id == empresa_id
    ).first()
    if req:
        try:
            req.firmando_por_id = None
            req.firmando_desde  = None
            req.updated_at      = datetime.utcnow()
            db.commit()
            await _notificar_servicio_ws(req.proyecto_servicio_id)
        except Exception:
            db.rollback()
    return {"ok": True}


def _usuarios_de_proyecto(db: Session, proyecto_id) -> list[str]:
    """usuario_id de los empleados miembros activos del proyecto.

    Base para acotar notificaciones a quienes participan en el proyecto; un admin
    que no es miembro no recibe la notificación.
    """
    if not proyecto_id:
        return []
    rows = (
        db.query(Empleado.usuario_id)
        .join(ProyectoMiembro, ProyectoMiembro.empleado_id == Empleado.id)
        .filter(
            ProyectoMiembro.proyecto_id == str(proyecto_id),
            ProyectoMiembro.activo.is_(True),
            Empleado.usuario_id.isnot(None),
        )
        .all()
    )
    return [r[0] for r in rows if r[0]]


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
        cantidadSugerida=int(it.cantidad_sugerida) if it.cantidad_sugerida is not None else None,
        stockAlAprobar=int(it.stock_al_aprobar) if it.stock_al_aprobar is not None else None,
        stockMinimoAlAprobar=int(it.stock_minimo_al_aprobar) if it.stock_minimo_al_aprobar is not None else None,
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
        tipoItem=it.tipo_item or "material",
        equipoId=str(it.equipo_id) if it.equipo_id else None,
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
        ingresoRegistrado=bool(tc.ingreso_registrado),
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

    total_est = sum(
        float(d.precio_estimado or 0) * int(d.cantidad or 0)
        for d in detalles_compra
    )

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
        total_estimado=total_est if total_est > 0 else None,
        created_at=datetime.utcnow(),
    )
    db.add(tc)
    db.flush()  # necesitamos tc.id para los ítems

    for d in detalles_compra:
        nombre          = d.nombre_libre or "—"
        unidad          = d.unidad_libre or ""
        qty_solicitada  = int(d.cantidad or 0)
        cantidad_ticket = qty_solicitada   # valor que verá logística (editable)
        sugerida        = None             # snapshot inmutable
        stock_snap      = None
        minimo_snap     = None

        if d.material_id:
            mat = db.query(Material).filter(Material.id == d.material_id).first()
            if mat:
                nombre = mat.nombre
                unidad = mat.unidad or unidad

            # ── Fórmula de sugerencia automática (Fase 2) ─────────────────
            # stock_actual y stock_minimo al momento de la aprobación
            stock_total, stock_minimo, _, _ = _stock_principal(db, d.material_id, empresa_id)
            stock_snap  = stock_total
            minimo_snap = stock_minimo

            # Faltante para cubrir el pedido
            faltante   = max(0, qty_solicitada - stock_total)
            # Reposición para dejar el stock por encima del mínimo en un 50 %
            reposicion = int(stock_minimo * 1.5)
            sugerida   = faltante + reposicion

            # Si la sugerencia fuera 0 o negativa (edge case), usamos al menos
            # la cantidad solicitada para no generar un ticket inútil
            if sugerida <= 0:
                sugerida = qty_solicitada

            cantidad_ticket = sugerida  # logística parte de la sugerencia

        else:
            # Ítem de texto libre: sin stock de referencia, comprar lo solicitado
            sugerida = qty_solicitada

        # Clasificación del ítem: desde campo explícito o derivada del contexto
        # - material_id presente → siempre 'material'
        # - compra externa con tipo_item_compra → usar ese valor
        # - equipo/herramienta de inventario (especificación heurística)
        if d.material_id:
            tipo_item = "material"
        elif getattr(d, "tipo_item_compra", None):
            tipo_item = d.tipo_item_compra
        else:
            # fallback: inferir de especificacion para ítems del tab 'equipos'
            espec = (d.especificacion or "").lower()
            if "[equipo]" in espec or "equipo" in espec:
                tipo_item = "equipo"
            elif "[herramienta]" in espec or "herramienta" in espec:
                tipo_item = "herramienta"
            else:
                tipo_item = "material"

        db.add(TicketCompraItem(
            id=str(_uuid.uuid4()),
            ticket_id=tc.id,
            requerimiento_detalle_id=str(d.id),
            material_id=str(d.material_id) if d.material_id else None,
            nombre=nombre,
            cantidad=cantidad_ticket,
            unidad=unidad,
            estado_item="pendiente",
            cantidad_sugerida=sugerida,
            stock_al_aprobar=stock_snap,
            stock_minimo_al_aprobar=minimo_snap,
            tipo_item=tipo_item,
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


# ──────────────────────────────────────────────────────────────────────────
# FASE 3 — helper de ingreso reutilizable
# ──────────────────────────────────────────────────────────────────────────

async def _aplicar_ingreso_ticket(
    db:              Session,
    tc:              TicketCompra,
    empresa_id:      str,
    emp,
    almacen_default: str | None,
) -> None:
    """
    Registra el ingreso al inventario de todos los ítems 'comprado' del ticket.

    Reglas:
    - Ítem de catálogo (material_id): suma stock + MovimientoInventario ingreso.
    - Ítem de texto libre (sin material_id): no toca stock (no existe en catálogo).
    - Ambos tipos: actualiza requerimiento_detalle.estado_item → 'aprobado'.
    - Al finalizar: transiciona requerimiento comprando→listo si no quedan para_compra.
    - Emite evento WS al room del servicio para actualización en tiempo real.
    - Idempotencia garantizada por tc.ingreso_registrado (guard externo).
    """
    items_db = (
        db.query(TicketCompraItem)
        .filter(TicketCompraItem.ticket_id == tc.id)
        .all()
    )

    for it in items_db:
        cant = int(it.cantidad_comprada or 0)
        if cant <= 0:
            continue

        tipo = (it.tipo_item or "material").lower()

        if tipo == "material" and it.material_id:
            # ── Consumible de catálogo: actualizar stock ───────────────────
            alm_id = almacen_default
            stock_row = db.query(Stock).filter(
                Stock.material_id == it.material_id,
                Stock.empresa_id  == empresa_id,
                Stock.almacen_id  == alm_id,
            ).first()
            if stock_row:
                stock_row.cantidad   = int(stock_row.cantidad or 0) + cant
                stock_row.updated_at = datetime.utcnow()
            else:
                db.add(Stock(
                    id=str(_uuid.uuid4()), empresa_id=empresa_id,
                    material_id=it.material_id, almacen_id=alm_id,
                    cantidad=cant, cantidad_minima=0,
                    updated_at=datetime.utcnow(),
                ))

            # Actualizar precio del material con el precio unitario de la compra
            if it.precio_unitario:
                mat_upd = db.query(Material).filter(
                    Material.id == it.material_id,
                    Material.empresa_id == empresa_id,
                ).first()
                if mat_upd:
                    mat_upd.precio = float(it.precio_unitario)
            db.add(MovimientoInventario(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                material_id=it.material_id, almacen_id=alm_id,
                tipo="ingreso", cantidad=cant,
                referencia_id=str(tc.id), referencia_tipo="compra",
                responsable_id=str(emp.id) if emp else None,
                fecha=datetime.utcnow(),
            ))

        elif tipo in ("equipo", "herramienta") and it.equipo_id:
            # ── No-consumible: sumar cantidad en tabla equipo ──────────────
            eq = db.query(Equipo).filter(
                Equipo.id == it.equipo_id, Equipo.empresa_id == empresa_id
            ).first()
            if eq:
                eq.cantidad    = int(eq.cantidad or 0) + cant
                eq.updated_at  = datetime.utcnow()

        # Ítems sin vínculo (material_id=None Y equipo_id=None):
        # el usuario no ejecutó vincular-inventario → se omiten en el ingreso.
        # El detalle queda como aprobado para no bloquear el requerimiento.

        # Marcar detalle del requerimiento como aprobado
        if it.requerimiento_detalle_id:
            det = db.query(RequerimientoDetalle).filter(
                RequerimientoDetalle.id == it.requerimiento_detalle_id
            ).first()
            if det and det.estado_item == "para_compra":
                det.estado_item       = "aprobado"
                det.cantidad_aprobada = cant

    # Marcar ticket como ingresado (guard de idempotencia)
    tc.ingreso_registrado = True
    tc.updated_at         = datetime.utcnow()
    db.commit()

    # ── Transición automática comprando → listo ───────────────────────────
    if tc.requerimiento_id:
        req = db.query(Requerimiento).filter(
            Requerimiento.id == tc.requerimiento_id
        ).first()
        if req and req.estado == "comprando":
            pendientes = db.query(RequerimientoDetalle).filter(
                RequerimientoDetalle.requerimiento_id == req.id,
                RequerimientoDetalle.estado_item      == "para_compra",
            ).count()
            if pendientes == 0:
                req.estado     = "listo"
                req.updated_at = datetime.utcnow()
                _notificar_solicitante(
                    db, req, str(req.empresa_id),
                    titulo  = "Materiales listos para retirar",
                    mensaje = (
                        "La compra llegó y fue registrada. Todos los materiales "
                        "de tu pedido están disponibles. Ya puedes retirarlos."
                    ),
                )
                db.commit()
                # Notificar en tiempo real al room del servicio
                await _notificar_servicio_ws(req.proyecto_servicio_id)


@router.post("/compras/{ticket_id}/items/{item_id}/vincular-inventario",
             response_model=TicketCompraItemOut)
def vincular_inventario(
    ticket_id: str,
    item_id:   str,
    body:      VincularInventarioBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """
    Fase 2 — Crea el ítem en su tabla de inventario y lo enlaza al ticket_compra_item.

    Para tipo_item='material':
      - Crea registro en `material` + fila en `stock` con cantidad=0.
      - Asigna ticket_compra_item.material_id.

    Para tipo_item='equipo'|'herramienta':
      - Crea registro en `equipo` con la clase correspondiente y cantidad=0
        (la cantidad real se suma al registrar el ingreso).
      - Asigna ticket_compra_item.equipo_id.

    Si el ítem ya tiene material_id o equipo_id, devuelve 409 (ya vinculado).
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]

    it = db.query(TicketCompraItem).filter(
        TicketCompraItem.id == item_id,
        TicketCompraItem.ticket_id == ticket_id,
    ).first()
    if not it:
        raise HTTPException(status_code=404, detail="Ítem no encontrado")
    if it.material_id or it.equipo_id:
        raise HTTPException(
            status_code=409,
            detail="El ítem ya está vinculado a un registro de inventario.",
        )

    tipo = (it.tipo_item or "material").lower()
    alm = db.query(Almacen).filter(
        Almacen.empresa_id == empresa_id, Almacen.activo.is_(True)
    ).first()
    alm_id = body.almacenId or (str(alm.id) if alm else None)

    # Cantidad comprada del ítem — se registra directamente al crear
    cant_comprada = int(it.cantidad_comprada or it.cantidad or 0)

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == payload["id"], Empleado.empresa_id == empresa_id
    ).first()

    if tipo == "material":
        if not body.unidad:
            raise HTTPException(status_code=422, detail="Se requiere la unidad para crear un material.")

        # Auto-código si no se proporciona
        codigo = body.codigo
        if not codigo:
            from sqlalchemy import text as _sql_text
            r = db.execute(_sql_text(
                "SELECT COUNT(*) FROM material WHERE empresa_id = :eid"
            ), {"eid": empresa_id}).scalar()
            codigo = f"MAT-{int(r or 0) + 1:04d}"

        mat = Material(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            nombre=body.nombre.strip(), unidad=body.unidad.strip(),
            codigo=codigo, descripcion=body.descripcion,
            categoria_id=body.categoriaId, precio=body.precioUnitario,
            activo=True,
        )
        db.add(mat)
        db.flush()

        # Stock inicial = cantidad comprada (ingreso inmediato al crear)
        db.add(Stock(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            material_id=mat.id, almacen_id=alm_id,
            cantidad=cant_comprada, cantidad_minima=int(body.stockMinimo or 0),
            updated_at=datetime.utcnow(),
        ))
        # Movimiento de ingreso trazable al ticket
        if cant_comprada > 0:
            db.add(MovimientoInventario(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                material_id=mat.id, almacen_id=alm_id,
                tipo="ingreso", cantidad=cant_comprada,
                referencia_id=str(it.ticket_id), referencia_tipo="compra",
                responsable_id=str(emp.id) if emp else None,
                fecha=datetime.utcnow(),
            ))
        it.material_id = mat.id

    else:  # equipo o herramienta
        clase = "herramienta" if tipo == "herramienta" else "equipo"
        eq = Equipo(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            nombre=body.nombre.strip(), clase=clase,
            modelo=body.modelo, marca=body.marca,
            numero_serie=body.numeroSerie,
            ubicacion=body.ubicacion or (alm.ubicacion if alm else None),
            almacen_id=alm_id,
            cantidad=cant_comprada,   # ingreso inmediato al crear
            estado="operativo",
            estado_operativo="operativo",
        )
        db.add(eq)
        db.flush()
        it.equipo_id = eq.id

    db.commit()
    db.refresh(it)
    return _ticket_item_out(it)


@router.patch("/compras/{ticket_id}/procesar", response_model=TicketCompraOut)
async def procesar_compra(
    ticket_id: str,
    body:      ProcesarCompraBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """
    Registra los detalles de la compra (cantidades, precios, proveedores).

    Si body.completado = True:
      - El ticket pasa a estado 'completado'.
      - Se registra automáticamente el ingreso al inventario (Fase 3):
          stock actualizado + movimiento_inventario ingreso + requerimiento → 'listo'.
      - El ingreso es idempotente: una vez aplicado no puede repetirse.

    Si body.completado = False:
      - El ticket pasa a 'en_proceso' (guardado parcial, sin ingreso).
    """
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

    # ── Fase 3: auto-ingreso cuando se confirma la compra ─────────────────
    if body.completado and not tc.ingreso_registrado:
        alm = db.query(Almacen).filter(
            Almacen.empresa_id == empresa_id, Almacen.activo.is_(True)
        ).first()
        await _aplicar_ingreso_ticket(
            db, tc, empresa_id, emp,
            almacen_default=str(alm.id) if alm else None,
        )
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




@router.post("/compras/{ticket_id}/registrar-ingreso", response_model=TicketCompraOut)
async def registrar_ingreso_compra(
    ticket_id: str,
    body:      RegistrarIngresoBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """
    Registro manual de ingreso (override).

    Úsalo cuando necesites registrar la recepción física separada de la
    confirmación de compra, o cuando el auto-ingreso de procesar_compra
    no pudo ejecutarse (p.ej. almacén no especificado).

    Precondiciones:
    - Ticket en estado 'completado'.
    - Ingreso aún no registrado (ingreso_registrado = false).

    El body.items permite indicar cantidades distintas a las compradas
    (útil en recepciones parciales o con diferencias de bulto).
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    tc = db.query(TicketCompra).filter(
        TicketCompra.id == ticket_id, TicketCompra.empresa_id == empresa_id
    ).first()
    if not tc:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    if tc.estado != "completado":
        raise HTTPException(status_code=409, detail="Solo tickets completados admiten ingreso")
    if tc.ingreso_registrado:
        raise HTTPException(
            status_code=409,
            detail="El ingreso ya fue registrado automáticamente al confirmar la compra. "
                   "Consulta los movimientos de inventario para verificar el stock actualizado.",
        )

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    # Aplicar cantidades del body (override manual — pueden diferir de cantidad_comprada)
    items_map = {b.itemId: b for b in body.items}
    for it in db.query(TicketCompraItem).filter(TicketCompraItem.ticket_id == tc.id).all():
        b = items_map.get(str(it.id))
        if b is not None and max(0, b.cantidad) > 0:
            it.cantidad_comprada = max(0, b.cantidad)
    db.commit()
    db.refresh(tc)

    alm = db.query(Almacen).filter(
        Almacen.empresa_id == empresa_id, Almacen.activo.is_(True)
    ).first()
    almacen_default = body.almacenId or (str(alm.id) if alm else None)

    await _aplicar_ingreso_ticket(db, tc, empresa_id, emp, almacen_default)
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


# ═══════════════════════════════════════════════════════════════════════════
# SALIDAS DE MATERIALES (HU-18)
# ═══════════════════════════════════════════════════════════════════════════

def _build_salida_out(db: Session, req: Requerimiento, empresa_id: str) -> SalidaOut:
    """Convierte un Requerimiento entregado en SalidaOut."""
    proyecto = db.query(Proyecto).filter(Proyecto.id == req.proyecto_id).first()
    proyecto_nombre = proyecto.nombre_proyecto if proyecto else "Proyecto"

    servicio_nombre = None
    if req.proyecto_servicio_id:
        srv = db.query(ProyectoServicio).filter(ProyectoServicio.id == req.proyecto_servicio_id).first()
        servicio_nombre = srv.nombre if srv else None

    sol_nombre, _ = _nombre_empleado(db, req.solicitante_id)

    # Ítems no rechazados con su origen (stock directo vs vía compra)
    detalles = (
        db.query(RequerimientoDetalle, Material.nombre, Material.unidad)
        .outerjoin(Material, Material.id == RequerimientoDetalle.material_id)
        .filter(
            RequerimientoDetalle.requerimiento_id == req.id,
            RequerimientoDetalle.estado_item.notin_(["rechazado"]),
        )
        .all()
    )

    # Conjunto de requerimiento_detalle_id que pasaron por ticket_compra
    detalle_ids_via_compra = set(
        str(r[0]) for r in
        db.query(TicketCompraItem.requerimiento_detalle_id)
        .filter(TicketCompraItem.requerimiento_detalle_id.isnot(None))
        .join(TicketCompra, TicketCompra.id == TicketCompraItem.ticket_id)
        .filter(TicketCompra.requerimiento_id == req.id)
        .all()
    )

    items: list[SalidaItemOut] = []
    total_unidades = 0
    for d, mat_nombre, mat_unidad in detalles:
        cant = int(d.cantidad_aprobada or d.cantidad or 0)
        total_unidades += cant
        origen = "compra" if str(d.id) in detalle_ids_via_compra else "stock"
        items.append(SalidaItemOut(
            id=str(d.id),
            nombre=mat_nombre or d.nombre_libre or "—",
            unidad=mat_unidad or d.unidad_libre or "",
            cantidadSolicitada=int(d.cantidad or 0),
            cantidadEntregada=cant,
            origenItem=origen,
        ))

    entrega = (
        db.query(RequerimientoEntrega)
        .filter(RequerimientoEntrega.requerimiento_id == req.id)
        .order_by(RequerimientoEntrega.created_at.desc())
        .first()
    )
    entregado_nombre = recibido_nombre = firma_url = fecha_salida = None
    firma_entregador_url = req.firma_entregador_url
    firmando_desde_iso   = req.firmando_desde.isoformat() if req.firmando_desde else None
    firmando_por_nombre, _ = (
        _nombre_empleado(db, req.firmando_por_id)
        if req.firmando_por_id else (None, None)
    )

    if entrega:
        entregado_nombre, _ = _nombre_empleado(db, entrega.entregado_por_id)
        recibido_nombre, _  = _nombre_empleado(db, entrega.recibido_por_id)
        firma_url    = entrega.firma_receptor_url
        fecha_salida = entrega.fecha_entrega.isoformat() if entrega.fecha_entrega else None
        if entrega.firma_entregador_url:
            firma_entregador_url = entrega.firma_entregador_url

    return SalidaOut(
        id=str(req.id),
        fechaSolicitud=req.created_at.isoformat() if req.created_at else None,
        fechaSalida=fecha_salida,
        proyectoId=str(req.proyecto_id) if req.proyecto_id else None,
        proyectoNombre=proyecto_nombre,
        servicioId=str(req.proyecto_servicio_id) if req.proyecto_servicio_id else None,
        servicioNombre=servicio_nombre,
        solicitanteNombre=sol_nombre,
        entregadoPorNombre=entregado_nombre,
        recibidoPorNombre=recibido_nombre,
        firmaUrl=firma_url,
        firmaEntregadorUrl=firma_entregador_url,
        firmandoPorNombre=firmando_por_nombre,
        firmandoDesde=firmando_desde_iso,
        observacion=req.observacion_logistico,
        items=items,
        totalItems=len(items),
        totalUnidades=total_unidades,
    )


@router.get("/salidas/kpis", response_model=SalidasKpis)
def salidas_kpis(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Métricas globales de salidas de materiales."""
    empresa_id = payload["empresa_id"]

    total = (
        db.query(func.count(Requerimiento.id))
        .filter(Requerimiento.empresa_id == empresa_id, Requerimiento.estado == "entregado")
        .scalar() or 0
    )

    inicio_mes = datetime.utcnow().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    este_mes = (
        db.query(func.count(Requerimiento.id))
        .join(RequerimientoEntrega, RequerimientoEntrega.requerimiento_id == Requerimiento.id)
        .filter(
            Requerimiento.empresa_id == empresa_id,
            Requerimiento.estado == "entregado",
            RequerimientoEntrega.fecha_entrega >= inicio_mes,
        )
        .scalar() or 0
    )

    total_unidades = (
        db.query(func.coalesce(func.sum(RequerimientoDetalle.cantidad_aprobada), 0))
        .join(Requerimiento, Requerimiento.id == RequerimientoDetalle.requerimiento_id)
        .filter(
            Requerimiento.empresa_id == empresa_id,
            Requerimiento.estado == "entregado",
            RequerimientoDetalle.estado_item == "aprobado",
        )
        .scalar() or 0
    )

    proyectos = (
        db.query(func.count(func.distinct(Requerimiento.proyecto_id)))
        .filter(Requerimiento.empresa_id == empresa_id, Requerimiento.estado == "entregado")
        .scalar() or 0
    )

    return SalidasKpis(
        totalSalidas=int(total),
        totalUnidadesEntregadas=int(total_unidades),
        salidasEsteMes=int(este_mes),
        proyectosAtendidos=int(proyectos),
    )


@router.get("/salidas", response_model=SalidasListResponse)
def listar_salidas(
    q:           str           = Query(""),
    proyecto_id: str           = Query(""),
    servicio_id: str           = Query("", description="Filtrar por proyecto_servicio_id"),
    desde:       Optional[str] = Query(None, description="YYYY-MM-DD"),
    hasta:       Optional[str] = Query(None, description="YYYY-MM-DD"),
    page:        int           = Query(1, ge=1),
    page_size:   int           = Query(30, ge=1, le=200),
    payload:     dict          = Depends(verificar_token),
    db:          Session       = Depends(get_db),
):
    """
    Lista de requerimientos entregados (salidas de materiales al campo).
    Filtros: proyecto_id, servicio_id (proyecto_servicio_id), desde/hasta, búsqueda libre.
    Cada ítem incluye origenItem ('stock' | 'compra') para trazabilidad.
    """
    empresa_id = payload["empresa_id"]

    base = db.query(Requerimiento).filter(
        Requerimiento.empresa_id == empresa_id,
        Requerimiento.estado == "entregado",
    )
    if proyecto_id:
        base = base.filter(Requerimiento.proyecto_id == proyecto_id)
    if servicio_id:
        base = base.filter(Requerimiento.proyecto_servicio_id == servicio_id)

    if desde or hasta:
        base = base.join(
            RequerimientoEntrega,
            RequerimientoEntrega.requerimiento_id == Requerimiento.id,
        )
        if desde:
            try:
                d = datetime.strptime(desde, "%Y-%m-%d")
                base = base.filter(RequerimientoEntrega.fecha_entrega >= d)
            except ValueError:
                pass
        if hasta:
            try:
                h = datetime.strptime(hasta, "%Y-%m-%d").replace(hour=23, minute=59, second=59)
                base = base.filter(RequerimientoEntrega.fecha_entrega <= h)
            except ValueError:
                pass

    total = base.count()
    rows = (
        base.order_by(Requerimiento.updated_at.desc().nullslast(), Requerimiento.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    items = [_build_salida_out(db, r, empresa_id) for r in rows]

    if q:
        ql = q.lower()
        items = [s for s in items if
            ql in s.proyectoNombre.lower()
            or ql in (s.servicioNombre or "").lower()
            or ql in s.solicitanteNombre.lower()
            or ql in (s.recibidoPorNombre or "").lower()
            or any(ql in i.nombre.lower() for i in s.items)
        ]

    return SalidasListResponse(items=items, total=total, page=page, pageSize=page_size)


# ══════════════════════════════════════════════════════════════════════════
# INGRESOS — historial de compras recibidas que afectaron el inventario
# Filtra por defecto al mes actual; soporta rango de fechas y búsqueda libre.
# ══════════════════════════════════════════════════════════════════════════

@router.get("/ingresos", response_model=IngresosListResponse)
def listar_ingresos(
    q:         str           = Query(""),
    desde:     Optional[str] = Query(None, description="YYYY-MM-DD (default: 1er día mes actual)"),
    hasta:     Optional[str] = Query(None, description="YYYY-MM-DD (default: hoy)"),
    page:      int           = Query(1, ge=1),
    page_size: int           = Query(30, ge=1, le=200),
    payload:   dict          = Depends(verificar_token),
    db:        Session       = Depends(get_db),
):
    """
    Historial de ingresos al inventario originados por compras completadas.
    Devuelve un registro por TicketCompra cuyo ingreso_registrado=True.
    Por defecto filtra el mes en curso; acepta rango desde/hasta.
    """
    empresa_id = payload["empresa_id"]
    now = datetime.utcnow()

    if desde:
        try:
            desde_dt = datetime.strptime(desde, "%Y-%m-%d")
        except ValueError:
            desde_dt = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    else:
        desde_dt = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    if hasta:
        try:
            hasta_dt = datetime.strptime(hasta, "%Y-%m-%d").replace(hour=23, minute=59, second=59)
        except ValueError:
            hasta_dt = now
    else:
        hasta_dt = now

    base = (
        db.query(TicketCompra)
        .filter(
            TicketCompra.empresa_id        == empresa_id,
            TicketCompra.ingreso_registrado == True,
            TicketCompra.updated_at        >= desde_dt,
            TicketCompra.updated_at        <= hasta_dt,
        )
        .order_by(TicketCompra.updated_at.desc())
    )

    total   = base.count()
    tickets = base.offset((page - 1) * page_size).limit(page_size).all()

    result: list[IngresoOut] = []
    for tc in tickets:
        tc_items = (
            db.query(TicketCompraItem)
            .filter(
                TicketCompraItem.ticket_id         == tc.id,
                TicketCompraItem.cantidad_comprada  > 0,
            )
            .all()
        )

        ingreso_items = [
            IngresoItemOut(
                nombre         = it.nombre,
                cantidad       = int(it.cantidad_comprada or 0),
                unidad         = it.unidad or "",
                tipoItem       = (it.tipo_item or "material").lower(),
                precioUnitario = float(it.precio_unitario) if it.precio_unitario else None,
            )
            for it in tc_items
        ]

        total_unidades = sum(i.cantidad for i in ingreso_items)

        # Proveedor: modo unificado usa proveedor_unico_nombre;
        # modo por ítem agrega los distintos nombres sin repetir.
        if tc.proveedor_unico_nombre:
            proveedor_nombre = tc.proveedor_unico_nombre
        else:
            nombres = list(dict.fromkeys(
                it.proveedor_nombre for it in tc_items if it.proveedor_nombre
            ))
            proveedor_nombre = ", ".join(nombres) if nombres else None

        result.append(IngresoOut(
            id                = str(tc.id),
            ticketCodigo      = tc.codigo,
            fechaIngreso      = tc.updated_at.isoformat() if tc.updated_at else "",
            proyectoNombre    = tc.proyecto_nombre or "—",
            servicioNombre    = tc.servicio_nombre,
            solicitanteNombre = tc.solicitante_nombre or "—",
            proveedorNombre   = proveedor_nombre,
            totalReal         = float(tc.total_real)      if tc.total_real      else None,
            totalEstimado     = float(tc.total_estimado)  if tc.total_estimado  else None,
            items             = ingreso_items,
            totalItems        = len(ingreso_items),
            totalUnidades     = total_unidades,
        ))

    if q:
        ql = q.lower()
        result = [
            r for r in result
            if ql in r.proyectoNombre.lower()
            or ql in (r.servicioNombre or "").lower()
            or ql in r.ticketCodigo.lower()
            or any(ql in it.nombre.lower() for it in r.items)
        ]

    return IngresosListResponse(items=result, total=total, page=page, pageSize=page_size)


# ══════════════════════════════════════════════════════════════════════════
# INVENTARIO — Ajuste manual de stock, transferencias y movimientos
# Migrado desde /requerimientos/inventario/* (versión móvil). El móvil ya
# consume estas rutas vía RequerimientoService.
# ══════════════════════════════════════════════════════════════════════════

def _almacen_default(db: Session, empresa_id: str) -> "Almacen | None":
    return db.query(Almacen).filter(
        Almacen.empresa_id == empresa_id,
        Almacen.activo.is_(True),
    ).order_by(Almacen.nombre).first()


@router.post("/inventario/ajuste", status_code=201)
def ajustar_stock(
    body:    dict,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Ajuste manual de stock — solo log/admin.

    Body: { material_id, tipo, cantidad, motivo?, almacen_id? }
      * tipo='entrada': suma cantidad al stock del almacén
      * tipo='salida' : resta cantidad; falla 422 si dejaría negativo
      * tipo='ajuste' : fija la cantidad exacta del almacén (sobreescribe)
    Registra siempre un MovimientoInventario.
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    material_id = (body.get("material_id") or "").strip()
    tipo        = (body.get("tipo") or "").strip().lower()
    motivo      = body.get("motivo")
    almacen_id  = body.get("almacen_id")
    try:
        cantidad = int(body.get("cantidad") or 0)
    except (TypeError, ValueError):
        cantidad = 0

    if not material_id or tipo not in ("entrada", "salida", "ajuste"):
        raise HTTPException(status_code=422, detail="material_id y tipo (entrada|salida|ajuste) son requeridos")
    if cantidad < 0:
        raise HTTPException(status_code=422, detail="cantidad no puede ser negativa")

    mat = db.query(Material).filter(
        Material.id == material_id, Material.empresa_id == empresa_id
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")

    if not almacen_id:
        alm = _almacen_default(db, empresa_id)
        if not alm:
            raise HTTPException(status_code=422, detail="No hay almacenes activos")
        almacen_id = str(alm.id)

    stock = db.query(Stock).filter(
        Stock.material_id == material_id,
        Stock.empresa_id  == empresa_id,
        Stock.almacen_id  == almacen_id,
    ).first()

    if tipo == "entrada":
        if stock:
            stock.cantidad = int(stock.cantidad or 0) + cantidad
            stock.updated_at = datetime.utcnow()
        else:
            stock = Stock(
                material_id=material_id, empresa_id=empresa_id, almacen_id=almacen_id,
                cantidad=cantidad, cantidad_minima=0, updated_at=datetime.utcnow(),
            )
            db.add(stock)
        delta = cantidad

    elif tipo == "salida":
        actual = int(stock.cantidad or 0) if stock else 0
        if cantidad > actual:
            raise HTTPException(
                status_code=422,
                detail=f"Stock insuficiente (disponible {actual}, solicitado {cantidad})",
            )
        stock.cantidad = actual - cantidad
        stock.updated_at = datetime.utcnow()
        delta = cantidad

    else:  # ajuste — fija valor exacto
        if stock:
            stock.cantidad = cantidad
            stock.updated_at = datetime.utcnow()
        else:
            db.add(Stock(
                material_id=material_id, empresa_id=empresa_id, almacen_id=almacen_id,
                cantidad=cantidad, cantidad_minima=0, updated_at=datetime.utcnow(),
            ))
        delta = cantidad

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()
    db.add(MovimientoInventario(
        id=str(_uuid.uuid4()), empresa_id=empresa_id,
        material_id=material_id, almacen_id=almacen_id,
        tipo=tipo, cantidad=delta,
        referencia_id=None, referencia_tipo="ajuste_manual",
        responsable_id=emp.id if emp else None,
        fecha=datetime.utcnow(),
    ))
    db.commit()
    return {"ok": True}


@router.get("/inventario/movimientos")
def listar_movimientos(
    material_id: str = Query("", description="filtrar por material"),
    page:        int = Query(1, ge=1),
    page_size:   int = Query(50, ge=1, le=200),
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Historial de movimientos de inventario (enriquecido para la UI móvil)."""
    empresa_id = payload["empresa_id"]

    base = db.query(MovimientoInventario).filter(
        MovimientoInventario.empresa_id == empresa_id
    )
    if material_id:
        base = base.filter(MovimientoInventario.material_id == material_id)

    rows = (
        base.order_by(MovimientoInventario.fecha.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    if not rows:
        return []

    mat_ids   = {r.material_id for r in rows if r.material_id}
    alm_ids   = {r.almacen_id  for r in rows if r.almacen_id}
    resp_ids  = {r.responsable_id for r in rows if r.responsable_id}

    mats = {
        m.id: (m.nombre, m.unidad)
        for m in db.query(Material.id, Material.nombre, Material.unidad)
                   .filter(Material.id.in_(mat_ids)).all()
    } if mat_ids else {}
    alms = {
        a.id: a.nombre
        for a in db.query(Almacen.id, Almacen.nombre)
                   .filter(Almacen.id.in_(alm_ids)).all()
    } if alm_ids else {}
    resps: dict[str, str] = {}
    if resp_ids:
        rows_r = (
            db.query(Empleado.id, Usuario.nombre, Usuario.apellido)
            .join(Usuario, Usuario.id == Empleado.usuario_id)
            .filter(Empleado.id.in_(resp_ids))
            .all()
        )
        for r in rows_r:
            resps[r.id] = f"{r.nombre or ''} {r.apellido or ''}".strip()

    return [
        {
            "id": str(r.id),
            "material_id": str(r.material_id) if r.material_id else "",
            "material_nombre": mats.get(r.material_id, ("", ""))[0],
            "unidad": mats.get(r.material_id, ("", "und"))[1] or "und",
            "tipo": r.tipo or "",
            "cantidad": int(r.cantidad or 0),
            "motivo": None,  # MovimientoInventario no guarda motivo libre hoy
            "almacen_nombre": alms.get(r.almacen_id) if r.almacen_id else None,
            "responsable_nombre": resps.get(r.responsable_id) if r.responsable_id else None,
            "fecha": r.fecha.strftime("%Y-%m-%d %H:%M") if r.fecha else "",
        }
        for r in rows
    ]


@router.post("/inventario/transferencia", status_code=201)
def transferir_stock(
    body:    dict,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Transfiere stock de un almacén a otro (mismo material).
    Body: { material_id, almacen_origen_id, almacen_destino_id, cantidad, motivo? }
    Registra dos MovimientoInventario (salida en origen, entrada en destino).
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    material_id = (body.get("material_id") or "").strip()
    origen_id   = (body.get("almacen_origen_id")  or "").strip()
    destino_id  = (body.get("almacen_destino_id") or "").strip()
    try:
        cantidad = int(body.get("cantidad") or 0)
    except (TypeError, ValueError):
        cantidad = 0

    if not material_id or not origen_id or not destino_id:
        raise HTTPException(status_code=422, detail="material_id, almacen_origen_id y almacen_destino_id son requeridos")
    if origen_id == destino_id:
        raise HTTPException(status_code=422, detail="El almacén origen y destino deben ser distintos")
    if cantidad <= 0:
        raise HTTPException(status_code=422, detail="cantidad debe ser > 0")

    # Validar pertenencia a la empresa
    mat = db.query(Material).filter(
        Material.id == material_id, Material.empresa_id == empresa_id
    ).first()
    if not mat:
        raise HTTPException(status_code=404, detail="Material no encontrado")
    for aid in (origen_id, destino_id):
        a = db.query(Almacen).filter(Almacen.id == aid, Almacen.empresa_id == empresa_id).first()
        if not a:
            raise HTTPException(status_code=404, detail=f"Almacén {aid} no encontrado")

    stock_o = db.query(Stock).filter(
        Stock.material_id == material_id, Stock.empresa_id == empresa_id, Stock.almacen_id == origen_id,
    ).first()
    actual = int(stock_o.cantidad or 0) if stock_o else 0
    if cantidad > actual:
        raise HTTPException(
            status_code=422,
            detail=f"Stock insuficiente en origen (disponible {actual}, solicitado {cantidad})",
        )

    stock_d = db.query(Stock).filter(
        Stock.material_id == material_id, Stock.empresa_id == empresa_id, Stock.almacen_id == destino_id,
    ).first()

    stock_o.cantidad = actual - cantidad
    stock_o.updated_at = datetime.utcnow()
    if stock_d:
        stock_d.cantidad = int(stock_d.cantidad or 0) + cantidad
        stock_d.updated_at = datetime.utcnow()
    else:
        db.add(Stock(
            material_id=material_id, empresa_id=empresa_id, almacen_id=destino_id,
            cantidad=cantidad, cantidad_minima=0, updated_at=datetime.utcnow(),
        ))

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()
    ref_id = str(_uuid.uuid4())  # par de movimientos comparten referencia
    for almacen_id, tipo in ((origen_id, "salida"), (destino_id, "entrada")):
        db.add(MovimientoInventario(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            material_id=material_id, almacen_id=almacen_id,
            tipo="transferencia", cantidad=cantidad,
            referencia_id=ref_id, referencia_tipo="transferencia",
            responsable_id=emp.id if emp else None,
            fecha=datetime.utcnow(),
        ))
        # tipo (entrada/salida) se infiere por el signo en consumidores; aquí
        # marcamos ambas como "transferencia" para que el historial las agrupe.
        _ = tipo

    db.commit()
    return {"ok": True}


# ══════════════════════════════════════════════════════════════════════════
# RETORNOS — devolución de materiales/equipos/herramientas al campo
# ══════════════════════════════════════════════════════════════════════════

def _retorno_detalle_out(d: RetornoDetalle) -> RetornoDetalleOut:
    return RetornoDetalleOut(
        id=str(d.id),
        materialId=str(d.material_id) if d.material_id else None,
        equipoId=str(d.equipo_id)     if d.equipo_id   else None,
        nombre=d.nombre,
        unidad=d.unidad or "Unidades",
        tipoItem=d.tipo_item or "material",
        cantidadEntregada=int(d.cantidad_entregada or 0),
        cantidadRetornada=d.cantidad_retornada,
        cantidadConfirmada=d.cantidad_confirmada,
        esObligatorio=bool(d.es_obligatorio),
        estadoItem=d.estado_item or "pendiente",
    )


def _retorno_out(db: Session, r: Retorno) -> RetornoOut:
    detalles = db.query(RetornoDetalle).filter(RetornoDetalle.retorno_id == r.id).all()

    servicio_nombre = proyecto_nombre = None
    if r.proyecto_servicio_id:
        srv = db.query(ProyectoServicio).filter(ProyectoServicio.id == r.proyecto_servicio_id).first()
        if srv:
            servicio_nombre = srv.nombre
            proy = db.query(Proyecto).filter(Proyecto.id == srv.proyecto_id).first()
            proyecto_nombre = proy.nombre_proyecto if proy else None

    iniciado_nombre, _ = _nombre_empleado(db, r.iniciado_por_id)      if r.iniciado_por_id      else (None, None)
    insp_nombre,     _ = _nombre_empleado(db, r.inspeccionado_por_id) if r.inspeccionado_por_id else (None, None)

    items_out    = [_retorno_detalle_out(d) for d in detalles]
    obligatorios = sum(1 for d in detalles if d.es_obligatorio)
    pendientes   = sum(1 for d in detalles if d.estado_item == "pendiente")

    return RetornoOut(
        id=str(r.id),
        proyectoServicioId=str(r.proyecto_servicio_id) if r.proyecto_servicio_id else None,
        servicioNombre=servicio_nombre,
        proyectoNombre=proyecto_nombre,
        requerimientoId=str(r.requerimiento_id) if r.requerimiento_id else None,
        estado=r.estado or "enviado",
        iniciadoPorNombre=iniciado_nombre,
        inspeccionadoPorNombre=insp_nombre,
        notaTecnico=r.nota_tecnico,
        notaLogistica=r.nota_logistica,
        creadoEn=r.created_at.isoformat() if r.created_at else "",
        completadoEn=r.completado_en.isoformat() if r.completado_en else None,
        items=items_out,
        totalItems=len(items_out),
        itemsObligatorios=obligatorios,
        itemsPendientes=pendientes,
    )


@router.post("/retornos", response_model=RetornoOut, status_code=201)
def crear_retorno(
    body:    CrearRetornoBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Técnico declara ítems a devolver. Crea retorno en estado='enviado'."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    req = db.query(Requerimiento).filter(
        Requerimiento.id == body.requerimientoId,
        Requerimiento.empresa_id == empresa_id,
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Requerimiento no encontrado")

    existente = db.query(Retorno).filter(
        Retorno.requerimiento_id == req.id,
        Retorno.estado != "completado",
    ).first()
    if existente:
        raise HTTPException(status_code=409, detail="Ya existe un retorno activo para este requerimiento.")

    retorno = Retorno(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        proyecto_servicio_id=str(req.proyecto_servicio_id) if req.proyecto_servicio_id else None,
        requerimiento_id=str(req.id),
        estado="enviado",
        iniciado_por_id=str(emp.id) if emp else None,
        nota_tecnico=body.notaTecnico,
        created_at=datetime.utcnow(),
    )
    db.add(retorno)
    db.flush()

    items_map = {it.detalleId: it.cantidadRetornada for it in body.items}

    detalles_req = (
        db.query(RequerimientoDetalle)
        .filter(
            RequerimientoDetalle.requerimiento_id == req.id,
            RequerimientoDetalle.estado_item == "aprobado",
        )
        .all()
    )
    for d in detalles_req:
        cant_ret = max(0, items_map.get(str(d.id), 0))
        tipo     = (getattr(d, "tipo_item_compra", None) or "material").lower()
        nombre   = d.nombre_libre or ""
        unidad   = d.unidad_libre or "Unidades"
        if d.material_id:
            mat = db.query(Material).filter(Material.id == d.material_id).first()
            if mat:
                nombre = mat.nombre
                unidad = mat.unidad or unidad
            tipo = "material"
        db.add(RetornoDetalle(
            id=str(_uuid.uuid4()),
            retorno_id=str(retorno.id),
            material_id=str(d.material_id) if d.material_id else None,
            nombre=nombre or "Ítem",
            unidad=unidad,
            tipo_item=tipo,
            cantidad_entregada=int(d.cantidad_aprobada or d.cantidad or 0),
            cantidad_retornada=cant_ret,
            es_obligatorio=(tipo in ("equipo", "herramienta")),
            estado_item="pendiente",
        ))

    db.commit()
    db.refresh(retorno)
    return _retorno_out(db, retorno)


@router.post("/retornos/desde-servicio", response_model=RetornoOut, status_code=201)
def crear_retorno_desde_servicio(
    body:    CrearRetornoServicioBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    El técnico registra la devolución al completar el servicio.
    Agrega los ítems de TODOS los requerimientos aprobados/entregados
    del servicio en un único retorno. Un servicio solo puede tener
    un retorno activo (409 si ya existe).
    """
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == body.proyectoServicioId,
        ProyectoServicio.empresa_id == empresa_id,
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    # Idempotencia: solo un retorno activo por servicio
    existente = db.query(Retorno).filter(
        Retorno.proyecto_servicio_id == body.proyectoServicioId,
        Retorno.estado != "completado",
    ).first()
    if existente:
        raise HTTPException(status_code=409, detail="Ya existe un retorno activo para este servicio.")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    retorno = Retorno(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        proyecto_servicio_id=str(ps.id),
        requerimiento_id=None,          # agrupa varios reqs
        estado="enviado",
        iniciado_por_id=str(emp.id) if emp else None,
        nota_tecnico=body.notaTecnico,
        created_at=datetime.utcnow(),
    )
    db.add(retorno)
    db.flush()

    items_map = {it.detalleId: it.cantidadRetornada for it in body.items}

    # Todos los reqs del servicio en estado aprobado o entregado
    reqs_ids = [
        str(r.id) for r in db.query(Requerimiento).filter(
            Requerimiento.proyecto_servicio_id == ps.id,
            Requerimiento.empresa_id           == empresa_id,
            Requerimiento.estado.in_(["aprobado", "entregado", "listo"]),
        ).all()
    ]

    detalles_todos = (
        db.query(RequerimientoDetalle)
        .filter(
            RequerimientoDetalle.requerimiento_id.in_(reqs_ids),
            RequerimientoDetalle.estado_item == "aprobado",
        )
        .all()
    )

    for d in detalles_todos:
        cant_ret = max(0, items_map.get(str(d.id), 0))
        tipo     = (getattr(d, "tipo_item_compra", None) or "material").lower()
        nombre   = d.nombre_libre or ""
        unidad   = d.unidad_libre or "Unidades"
        if d.material_id:
            mat = db.query(Material).filter(Material.id == d.material_id).first()
            if mat:
                nombre = mat.nombre
                unidad = mat.unidad or unidad
            tipo = "material"
        db.add(RetornoDetalle(
            id=str(_uuid.uuid4()),
            retorno_id=str(retorno.id),
            material_id=str(d.material_id) if d.material_id else None,
            nombre=nombre or "Ítem",
            unidad=unidad,
            tipo_item=tipo,
            cantidad_entregada=int(d.cantidad_aprobada or d.cantidad or 0),
            cantidad_retornada=cant_ret,
            es_obligatorio=(tipo in ("equipo", "herramienta")),
            estado_item="pendiente",
        ))

    db.commit()
    db.refresh(retorno)
    return _retorno_out(db, retorno)


@router.get("/retornos/check-servicio/{servicio_id}")
def check_retorno_servicio(
    servicio_id: str,
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """
    Verifica si el servicio ya tiene un retorno registrado.
    Devuelve {tieneRetorno: bool, retornoId: str|null, estado: str|null}
    El frontend lo usa al cargar un servicio Completado para decidir
    si debe forzar el modal de devolución.
    """
    empresa_id = payload["empresa_id"]
    retorno = db.query(Retorno).filter(
        Retorno.proyecto_servicio_id == servicio_id,
        Retorno.empresa_id           == empresa_id,
    ).order_by(Retorno.created_at.desc()).first()

    if retorno:
        return {
            "tieneRetorno": True,
            "retornoId":    str(retorno.id),
            "estado":       retorno.estado,
        }
    return {"tieneRetorno": False, "retornoId": None, "estado": None}


@router.get("/retornos", response_model=RetornosListResponse)
def listar_retornos(
    q:         str           = Query(""),
    estado:    str           = Query(""),
    desde:     Optional[str] = Query(None),
    hasta:     Optional[str] = Query(None),
    page:      int           = Query(1, ge=1),
    page_size: int           = Query(30, ge=1, le=200),
    payload:   dict          = Depends(verificar_token),
    db:        Session       = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    base = db.query(Retorno).filter(Retorno.empresa_id == empresa_id)
    if estado:
        base = base.filter(Retorno.estado == estado)
    if desde:
        try:
            base = base.filter(Retorno.created_at >= datetime.strptime(desde, "%Y-%m-%d"))
        except ValueError:
            pass
    if hasta:
        try:
            base = base.filter(
                Retorno.created_at <= datetime.strptime(hasta, "%Y-%m-%d").replace(hour=23, minute=59, second=59)
            )
        except ValueError:
            pass

    total  = base.count()
    rows   = base.order_by(Retorno.created_at.desc()).offset((page - 1) * page_size).limit(page_size).all()
    result = [_retorno_out(db, r) for r in rows]

    if q:
        ql = q.lower()
        result = [r for r in result if
            ql in (r.servicioNombre or "").lower() or
            ql in (r.proyectoNombre or "").lower() or
            ql in (r.iniciadoPorNombre or "").lower() or
            any(ql in it.nombre.lower() for it in r.items)]

    return RetornosListResponse(items=result, total=total, page=page, pageSize=page_size)


@router.get("/retornos/{retorno_id}", response_model=RetornoOut)
def detalle_retorno(
    retorno_id: str,
    payload:    dict    = Depends(verificar_token),
    db:         Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    r = db.query(Retorno).filter(Retorno.id == retorno_id, Retorno.empresa_id == empresa_id).first()
    if not r:
        raise HTTPException(status_code=404, detail="Retorno no encontrado")
    return _retorno_out(db, r)


@router.patch("/retornos/{retorno_id}/inspeccionar", response_model=RetornoOut)
def inspeccionar_retorno(
    retorno_id: str,
    body:       InspectionarRetornoBody,
    payload:    dict    = Depends(verificar_token),
    db:         Session = Depends(get_db),
):
    """Logística confirma cantidades recibidas por ítem."""
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    r = db.query(Retorno).filter(Retorno.id == retorno_id, Retorno.empresa_id == empresa_id).first()
    if not r:
        raise HTTPException(status_code=404, detail="Retorno no encontrado")
    if r.estado == "completado":
        raise HTTPException(status_code=409, detail="El retorno ya está completado")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    confirmaciones = {it.detalleId: it.cantidadConfirmada for it in body.items}
    detalles = db.query(RetornoDetalle).filter(RetornoDetalle.retorno_id == r.id).all()
    for d in detalles:
        cant_conf = confirmaciones.get(str(d.id))
        if cant_conf is not None:
            d.cantidad_confirmada = max(0, cant_conf)
            d.estado_item = "confirmado" if d.cantidad_confirmada > 0 else "faltante"

    r.estado               = "inspeccion"
    r.inspeccionado_por_id = str(emp.id) if emp else None
    r.nota_logistica       = body.notaLogistica or r.nota_logistica
    r.updated_at           = datetime.utcnow()
    db.commit()
    db.refresh(r)
    return _retorno_out(db, r)


@router.patch("/retornos/{retorno_id}/completar", response_model=RetornoOut)
def completar_retorno(
    retorno_id: str,
    payload:    dict    = Depends(verificar_token),
    db:         Session = Depends(get_db),
):
    """Cierra el retorno: devuelve ítems confirmados al inventario."""
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    r = db.query(Retorno).filter(Retorno.id == retorno_id, Retorno.empresa_id == empresa_id).first()
    if not r:
        raise HTTPException(status_code=404, detail="Retorno no encontrado")
    if r.estado == "completado":
        raise HTTPException(status_code=409, detail="El retorno ya está completado")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    alm       = _almacen_default(db, empresa_id)
    almacen_id = str(alm.id) if alm else None

    detalles = db.query(RetornoDetalle).filter(RetornoDetalle.retorno_id == r.id).all()
    for d in detalles:
        cant = int(d.cantidad_confirmada or d.cantidad_retornada or 0)
        if cant <= 0:
            continue
        if d.material_id:
            stock_row = db.query(Stock).filter(
                Stock.material_id == d.material_id,
                Stock.empresa_id  == empresa_id,
                Stock.almacen_id  == almacen_id,
            ).first()
            if stock_row:
                stock_row.cantidad   = int(stock_row.cantidad or 0) + cant
                stock_row.updated_at = datetime.utcnow()
            else:
                db.add(Stock(
                    id=str(_uuid.uuid4()), empresa_id=empresa_id,
                    material_id=d.material_id, almacen_id=almacen_id,
                    cantidad=cant, cantidad_minima=0, updated_at=datetime.utcnow(),
                ))
            db.add(MovimientoInventario(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                material_id=d.material_id, almacen_id=almacen_id,
                tipo="retorno", cantidad=cant,
                referencia_id=str(r.id), referencia_tipo="retorno",
                responsable_id=str(emp.id) if emp else None,
                motivo=f"Retorno de campo – {r.proyecto_servicio_id or ''}",
                fecha=datetime.utcnow(),
            ))
        elif d.equipo_id:
            eq = db.query(Equipo).filter(Equipo.id == d.equipo_id, Equipo.empresa_id == empresa_id).first()
            if eq:
                eq.cantidad   = int(eq.cantidad or 0) + cant
                eq.updated_at = datetime.utcnow()
        if d.estado_item == "pendiente":
            d.estado_item = "confirmado"

    r.estado        = "completado"
    r.completado_en = datetime.utcnow()
    r.updated_at    = datetime.utcnow()
    db.commit()
    db.refresh(r)
    return _retorno_out(db, r)


# ══════════════════════════════════════════════════════════════════════════
# INCIDENCIAS — daños/fallos reportados sobre equipos y herramientas
# ══════════════════════════════════════════════════════════════════════════

def _incidencia_out(db: Session, inc: Incidencia) -> IncidenciaOut:
    eq = db.query(Equipo).filter(Equipo.id == inc.equipo_id).first()
    equipo_nombre = eq.nombre if eq else "—"
    equipo_clase  = (eq.clase or "equipo") if eq else "equipo"
    equipo_sin_serie = (not eq or not (eq.numero_serie or "").strip()) if eq else True

    servicio_nombre = None
    if inc.proyecto_servicio_id:
        srv = db.query(ProyectoServicio).filter(ProyectoServicio.id == inc.proyecto_servicio_id).first()
        servicio_nombre = srv.nombre if srv else None

    rep_nombre, _ = _nombre_empleado(db, inc.reportado_por_id) if inc.reportado_por_id else (None, None)
    res_nombre, _ = _nombre_empleado(db, inc.resuelto_por_id)  if inc.resuelto_por_id  else (None, None)

    return IncidenciaOut(
        id=str(inc.id),
        equipoId=str(inc.equipo_id),
        equipoNombre=equipo_nombre,
        equipoClase=equipo_clase,
        equipoSinSerie=equipo_sin_serie,
        proyectoServicioId=str(inc.proyecto_servicio_id) if inc.proyecto_servicio_id else None,
        servicioNombre=servicio_nombre,
        reportadoPorNombre=rep_nombre,
        resueltoPorNombre=res_nombre,
        numeroSerie=inc.numero_serie,
        cantidadAfectada=int(inc.cantidad_afectada or 1),
        tipoFalla=inc.tipo_falla or "otro",
        descripcion=inc.descripcion or "",
        estado=inc.estado or "abierta",
        resolucionNota=inc.resolucion_nota,
        fechaReporte=inc.fecha_reporte.isoformat() if inc.fecha_reporte else "",
        fechaResolucion=inc.fecha_resolucion.isoformat() if inc.fecha_resolucion else None,
    )


def _sincronizar_estado_equipo(db: Session, equipo_id: str, empresa_id: str) -> None:
    """
    Recalcula equipo.estado y equipo.cantidad_inoperativa a partir de las
    incidencias activas. Regla: el equipo vuelve a 'operativo' solo cuando
    todas sus incidencias activas (abierta | en_reparacion) están cerradas.
    """
    activas = db.query(Incidencia).filter(
        Incidencia.equipo_id == equipo_id,
        Incidencia.estado.in_(["abierta", "en_reparacion"]),
    ).all()

    eq = db.query(Equipo).filter(
        Equipo.id == equipo_id, Equipo.empresa_id == empresa_id
    ).first()
    if not eq:
        return

    cantidad_inop = sum(int(i.cantidad_afectada or 1) for i in activas)
    eq.cantidad_inoperativa = cantidad_inop
    eq.updated_at           = datetime.utcnow()

    if not activas:
        eq.estado = "operativo"
    else:
        hay_reparacion = any(i.estado == "en_reparacion" for i in activas)
        eq.estado = "en_mantenimiento" if hay_reparacion else "en_mantenimiento"


@router.post("/incidencias", response_model=IncidenciaOut, status_code=201)
def crear_incidencia(
    body:    CrearIncidenciaBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Técnico reporta una incidencia sobre un equipo o herramienta."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    eq = db.query(Equipo).filter(
        Equipo.id == body.equipoId, Equipo.empresa_id == empresa_id
    ).first()
    if not eq:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    inc = Incidencia(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        equipo_id=body.equipoId,
        proyecto_servicio_id=body.proyectoServicioId,
        reportado_por_id=str(emp.id) if emp else None,
        numero_serie=body.numeroSerie or eq.numero_serie,
        cantidad_afectada=max(1, int(body.cantidadAfectada or 1)),
        tipo_falla=body.tipoFalla or "otro",
        descripcion=body.descripcion.strip(),
        estado="abierta",
        fecha_reporte=datetime.utcnow(),
        created_at=datetime.utcnow(),
    )
    db.add(inc)
    db.flush()

    _sincronizar_estado_equipo(db, body.equipoId, empresa_id)
    db.commit()
    db.refresh(inc)
    return _incidencia_out(db, inc)


@router.get("/incidencias", response_model=IncidenciasListResponse)
def listar_incidencias(
    q:         str           = Query(""),
    clase:     str           = Query(""),      # equipo | herramienta
    estado:    str           = Query(""),      # abierta | en_reparacion | solucionado | dado_de_baja
    desde:     Optional[str] = Query(None),
    hasta:     Optional[str] = Query(None),
    page:      int           = Query(1, ge=1),
    page_size: int           = Query(30, ge=1, le=200),
    payload:   dict          = Depends(verificar_token),
    db:        Session       = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    base = db.query(Incidencia).filter(Incidencia.empresa_id == empresa_id)

    if estado:
        base = base.filter(Incidencia.estado == estado)
    if clase in ("equipo", "herramienta"):
        base = base.join(Equipo, Equipo.id == Incidencia.equipo_id).filter(Equipo.clase == clase)
    if desde:
        try:
            base = base.filter(Incidencia.fecha_reporte >= datetime.strptime(desde, "%Y-%m-%d"))
        except ValueError:
            pass
    if hasta:
        try:
            base = base.filter(Incidencia.fecha_reporte <= datetime.strptime(hasta, "%Y-%m-%d").replace(hour=23, minute=59, second=59))
        except ValueError:
            pass

    total  = base.count()
    rows   = base.order_by(Incidencia.fecha_reporte.desc()).offset((page - 1) * page_size).limit(page_size).all()
    result = [_incidencia_out(db, i) for i in rows]

    if q:
        ql = q.lower()
        result = [r for r in result if
            ql in r.equipoNombre.lower() or
            ql in (r.servicioNombre or "").lower() or
            ql in (r.reportadoPorNombre or "").lower() or
            ql in r.descripcion.lower() or
            ql in (r.numeroSerie or "").lower()]

    return IncidenciasListResponse(items=result, total=total, page=page, pageSize=page_size)


@router.get("/incidencias/{incidencia_id}", response_model=IncidenciaOut)
def detalle_incidencia(
    incidencia_id: str,
    payload:       dict    = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    inc = db.query(Incidencia).filter(Incidencia.id == incidencia_id, Incidencia.empresa_id == empresa_id).first()
    if not inc:
        raise HTTPException(status_code=404, detail="Incidencia no encontrada")
    return _incidencia_out(db, inc)


@router.patch("/incidencias/{incidencia_id}/resolver", response_model=IncidenciaOut)
def resolver_incidencia(
    incidencia_id: str,
    body:          ResolverIncidenciaBody,
    payload:       dict    = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    """
    Logística resuelve una incidencia.
    - en_reparacion: equipo pasa a en_mantenimiento
    - solucionado:   si no quedan incidencias activas, equipo vuelve a operativo
    - dado_de_baja:  descuenta cantidad_afectada del stock permanentemente
    """
    _autorizar_logistica(payload)
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    estados_validos = ("en_reparacion", "solucionado", "dado_de_baja")
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail=f"Estado debe ser uno de: {estados_validos}")

    inc = db.query(Incidencia).filter(Incidencia.id == incidencia_id, Incidencia.empresa_id == empresa_id).first()
    if not inc:
        raise HTTPException(status_code=404, detail="Incidencia no encontrada")
    if inc.estado in ("solucionado", "dado_de_baja"):
        raise HTTPException(status_code=409, detail="La incidencia ya está cerrada")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    inc.estado           = body.estado
    inc.resolucion_nota  = body.resolucionNota
    inc.resuelto_por_id  = str(emp.id) if emp else None
    inc.updated_at       = datetime.utcnow()

    if body.estado in ("solucionado", "dado_de_baja"):
        inc.fecha_resolucion = datetime.utcnow()

    # Impacto en inventario para dado_de_baja: descontar stock permanentemente
    if body.estado == "dado_de_baja":
        eq = db.query(Equipo).filter(Equipo.id == inc.equipo_id, Equipo.empresa_id == empresa_id).first()
        if eq:
            nueva_cantidad = max(0, int(eq.cantidad or 0) - int(inc.cantidad_afectada or 1))
            eq.cantidad    = nueva_cantidad
            eq.updated_at  = datetime.utcnow()
            db.add(MovimientoInventario(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                material_id=None, almacen_id=None,
                tipo="baja", cantidad=int(inc.cantidad_afectada or 1),
                referencia_id=str(inc.id), referencia_tipo="incidencia",
                responsable_id=str(emp.id) if emp else None,
                motivo=f"Dado de baja por incidencia – {inc.descripcion[:80]}",
                fecha=datetime.utcnow(),
            ))

    db.flush()
    _sincronizar_estado_equipo(db, str(inc.equipo_id), empresa_id)
    db.commit()
    db.refresh(inc)
    return _incidencia_out(db, inc)


@router.get("/incidencias/equipo/{equipo_id}/desglose", response_model=EquipoStockDesglose)
def desglose_stock_equipo(
    equipo_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """Desglose operativos vs en incidencia para el tooltip del inventario."""
    empresa_id = payload["empresa_id"]
    eq = db.query(Equipo).filter(Equipo.id == equipo_id, Equipo.empresa_id == empresa_id).first()
    if not eq:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    incidencias_activas = db.query(Incidencia).filter(
        Incidencia.equipo_id == equipo_id,
        Incidencia.estado.in_(["abierta", "en_reparacion"]),
    ).all()

    en_incidencia = sum(int(i.cantidad_afectada or 1) for i in incidencias_activas)
    total         = int(eq.cantidad or 0)
    operativos    = max(0, total - en_incidencia)

    return EquipoStockDesglose(
        equipoId=str(eq.id),
        cantidadTotal=total,
        operativos=operativos,
        enIncidencia=en_incidencia,
        incidenciasAbiertas=len(incidencias_activas),
    )
