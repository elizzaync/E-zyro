"""
Router: /activo-cliente
Catálogo maestro de activos físicos del cliente (pozos a tierra, tableros, UPS, etc.).
Separado completamente de la tabla 'equipo' (herramientas internas de la empresa).
"""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import List, Optional, Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..models.activo_cliente import ActivoCliente
from ..models.tipo_equipo import TipoEquipo
from ..models.ubicacion import Ubicacion
from ..models.zona import Zona
from ..models.area import Area
from ..models.cliente import Cliente

router = APIRouter(prefix="/activo-cliente", tags=["activo-cliente"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class ActivoClienteIn(BaseModel):
    cliente_id:       Optional[str]  = None
    tipo_equipo_id:   Optional[str]  = None
    nombre:           str
    codigo:           Optional[str]  = None
    marca:            Optional[str]  = None
    modelo:           Optional[str]  = None
    numero_serie:     Optional[str]  = None
    ubicacion_id:     Optional[str]  = None
    zona_id:          Optional[str]  = None
    area_id:          Optional[str]  = None
    area_descripcion: Optional[str]  = None
    estado:           Optional[str]  = "operativo"
    fecha_instalacion: Optional[str] = None
    ficha_tecnica:    Optional[dict[str, Any]] = None
    observaciones:    Optional[str]  = None
    activo:           Optional[bool] = True


class ActivoClienteOut(BaseModel):
    id:               str
    empresa_id:       str
    cliente_id:       Optional[str]
    tipo_equipo_id:   Optional[str]
    tipo_nombre:      Optional[str] = None
    procedimientos_template: Optional[list] = None
    nombre:           str
    codigo:           Optional[str]
    marca:            Optional[str]
    modelo:           Optional[str]
    numero_serie:     Optional[str]
    ubicacion_id:     Optional[str]
    zona_id:          Optional[str]
    area_id:          Optional[str]
    area_descripcion: Optional[str]
    ubicacion_nombre: Optional[str] = None
    zona_nombre:      Optional[str] = None
    estado:           str
    activo:           bool
    created_at:       str


def _to_out(a: ActivoCliente, db: Session) -> ActivoClienteOut:
    tipo_nombre = None
    procedimientos_template = None
    ubicacion_nombre = None
    zona_nombre = None

    if a.tipo_equipo_id:
        te = db.query(TipoEquipo).filter(TipoEquipo.id == a.tipo_equipo_id).first()
        if te:
            tipo_nombre = te.nombre
            procedimientos_template = te.procedimientos_template
    if a.ubicacion_id:
        ub = db.query(Ubicacion).filter(Ubicacion.id == a.ubicacion_id).first()
        if ub:
            ubicacion_nombre = ub.nombre
    if a.zona_id:
        zo = db.query(Zona).filter(Zona.id == a.zona_id).first()
        if zo:
            zona_nombre = zo.nombre

    return ActivoClienteOut(
        id=str(a.id),
        empresa_id=str(a.empresa_id),
        cliente_id=str(a.cliente_id) if a.cliente_id else None,
        tipo_equipo_id=str(a.tipo_equipo_id) if a.tipo_equipo_id else None,
        tipo_nombre=tipo_nombre,
        procedimientos_template=procedimientos_template,
        nombre=a.nombre,
        codigo=a.codigo,
        marca=a.marca,
        modelo=a.modelo,
        numero_serie=a.numero_serie,
        ubicacion_id=str(a.ubicacion_id) if a.ubicacion_id else None,
        zona_id=str(a.zona_id) if a.zona_id else None,
        area_id=str(a.area_id) if a.area_id else None,
        area_descripcion=a.area_descripcion,
        ubicacion_nombre=ubicacion_nombre,
        zona_nombre=zona_nombre,
        estado=a.estado,
        activo=a.activo,
        created_at=a.created_at.isoformat() if a.created_at else "",
    )


# ── GET /activo-cliente ───────────────────────────────────────────────────────

@router.get("", response_model=List[ActivoClienteOut])
def listar(
    cliente_id:   Optional[str]  = Query(None),
    ubicacion_id: Optional[str]  = Query(None),
    zona_id:      Optional[str]  = Query(None),
    tipo_equipo_id: Optional[str] = Query(None),
    activo:       Optional[bool] = Query(None),
    q:            Optional[str]  = Query(None),
    payload: dict  = Depends(verificar_token),
    db: Session    = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    query = db.query(ActivoCliente).filter(ActivoCliente.empresa_id == empresa_id)

    if cliente_id:
        query = query.filter(ActivoCliente.cliente_id == cliente_id)
    if ubicacion_id:
        query = query.filter(ActivoCliente.ubicacion_id == ubicacion_id)
    if zona_id:
        query = query.filter(ActivoCliente.zona_id == zona_id)
    if tipo_equipo_id:
        query = query.filter(ActivoCliente.tipo_equipo_id == tipo_equipo_id)
    if activo is not None:
        query = query.filter(ActivoCliente.activo == activo)
    if q:
        query = query.filter(ActivoCliente.nombre.ilike(f"%{q}%"))

    return [_to_out(a, db) for a in query.order_by(ActivoCliente.nombre).all()]


# ── GET /activo-cliente/{id} ──────────────────────────────────────────────────

@router.get("/{activo_id}", response_model=ActivoClienteOut)
def obtener(
    activo_id: str,
    payload: dict  = Depends(verificar_token),
    db: Session    = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    a = db.query(ActivoCliente).filter(
        ActivoCliente.id == activo_id,
        ActivoCliente.empresa_id == empresa_id,
    ).first()
    if not a:
        raise HTTPException(status_code=404, detail="Activo no encontrado")
    return _to_out(a, db)


# ── POST /activo-cliente ──────────────────────────────────────────────────────

@router.post("", response_model=ActivoClienteOut, status_code=201)
def crear(
    body: ActivoClienteIn,
    payload: dict  = Depends(verificar_token),
    db: Session    = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    from datetime import date
    fecha_inst = None
    if body.fecha_instalacion:
        try:
            fecha_inst = date.fromisoformat(body.fecha_instalacion)
        except ValueError:
            raise HTTPException(status_code=422, detail="fecha_instalacion inválida (use yyyy-mm-dd)")

    a = ActivoCliente(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        cliente_id=body.cliente_id,
        tipo_equipo_id=body.tipo_equipo_id,
        nombre=body.nombre,
        codigo=body.codigo,
        marca=body.marca,
        modelo=body.modelo,
        numero_serie=body.numero_serie,
        ubicacion_id=body.ubicacion_id,
        zona_id=body.zona_id,
        area_id=body.area_id,
        area_descripcion=body.area_descripcion,
        estado=body.estado or "operativo",
        fecha_instalacion=fecha_inst,
        ficha_tecnica=body.ficha_tecnica,
        observaciones=body.observaciones,
        activo=body.activo if body.activo is not None else True,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return _to_out(a, db)


# ── PATCH /activo-cliente/{id} ────────────────────────────────────────────────

@router.patch("/{activo_id}", response_model=ActivoClienteOut)
def actualizar(
    activo_id: str,
    body: ActivoClienteIn,
    payload: dict  = Depends(verificar_token),
    db: Session    = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    a = db.query(ActivoCliente).filter(
        ActivoCliente.id == activo_id,
        ActivoCliente.empresa_id == empresa_id,
    ).first()
    if not a:
        raise HTTPException(status_code=404, detail="Activo no encontrado")

    for campo, valor in body.model_dump(exclude_unset=True).items():
        if campo == "fecha_instalacion" and valor:
            from datetime import date
            try:
                valor = date.fromisoformat(valor)
            except ValueError:
                raise HTTPException(status_code=422, detail="fecha_instalacion inválida")
        setattr(a, campo, valor)

    a.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(a)
    return _to_out(a, db)


# ── DELETE /activo-cliente/{id} ───────────────────────────────────────────────

@router.delete("/{activo_id}", status_code=204)
def eliminar(
    activo_id: str,
    payload: dict  = Depends(verificar_token),
    db: Session    = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    a = db.query(ActivoCliente).filter(
        ActivoCliente.id == activo_id,
        ActivoCliente.empresa_id == empresa_id,
    ).first()
    if not a:
        raise HTTPException(status_code=404, detail="Activo no encontrado")
    a.activo = False
    a.updated_at = datetime.utcnow()
    db.commit()
