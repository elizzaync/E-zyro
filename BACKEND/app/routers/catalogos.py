"""
Router: /catalogos
Catálogos base compartidos: Ubicaciones, Zonas, Áreas.
Consumidos por EPP, ITSE, Inventario y RR.HH. Lecturas abiertas a la empresa;
escrituras protegidas por RBAC (módulo 'catalogos').

Toda escritura queda registrada por el listener global de auditoría.
"""
from __future__ import annotations

import uuid as _uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.ubicacion import Ubicacion
from ..models.zona import Zona
from ..models.area import Area
from ..schemas.catalogos import (
    UbicacionIn, UbicacionOut,
    ZonaIn, ZonaOut,
    AreaIn, AreaOut,
)

router = APIRouter(prefix="/catalogos", tags=["catalogos"])


# ──────────────────────────────────────────────────────────────────────────
# Ubicaciones
# ──────────────────────────────────────────────────────────────────────────
@router.get("/ubicaciones", response_model=List[UbicacionOut])
def listar_ubicaciones(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    rows = (
        db.query(Ubicacion)
        .filter(Ubicacion.empresa_id == payload["empresa_id"])
        .order_by(Ubicacion.nombre)
        .all()
    )
    return [UbicacionOut(id=str(r.id), nombre=r.nombre, region=r.region) for r in rows]


@router.post("/ubicaciones", response_model=UbicacionOut, status_code=201)
def crear_ubicacion(body: UbicacionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "crear")
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    existente = (
        db.query(Ubicacion)
        .filter(Ubicacion.empresa_id == empresa_id, func.lower(Ubicacion.nombre) == nombre.lower())
        .first()
    )
    if existente:
        return UbicacionOut(id=str(existente.id), nombre=existente.nombre, region=existente.region)
    u = Ubicacion(id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre, region=(body.region or None))
    db.add(u)
    db.commit()
    return UbicacionOut(id=str(u.id), nombre=u.nombre, region=u.region)


@router.put("/ubicaciones/{ubicacion_id}", response_model=UbicacionOut)
def actualizar_ubicacion(ubicacion_id: str, body: UbicacionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "editar")
    u = db.query(Ubicacion).filter(Ubicacion.id == ubicacion_id, Ubicacion.empresa_id == payload["empresa_id"]).first()
    if not u:
        raise HTTPException(status_code=404, detail="Ubicación no encontrada")
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    u.nombre = nombre
    u.region = body.region or None
    db.commit()
    return UbicacionOut(id=str(u.id), nombre=u.nombre, region=u.region)


@router.delete("/ubicaciones/{ubicacion_id}", status_code=204)
def eliminar_ubicacion(ubicacion_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "eliminar")
    u = db.query(Ubicacion).filter(Ubicacion.id == ubicacion_id, Ubicacion.empresa_id == payload["empresa_id"]).first()
    if not u:
        raise HTTPException(status_code=404, detail="Ubicación no encontrada")
    if db.query(Zona).filter(Zona.ubicacion_id == ubicacion_id).first():
        raise HTTPException(status_code=409, detail="No se puede eliminar: tiene zonas asociadas")
    db.delete(u)
    db.commit()


# ──────────────────────────────────────────────────────────────────────────
# Zonas
# ──────────────────────────────────────────────────────────────────────────
def _zona_out(z: Zona, ubic_nombre: Optional[str]) -> ZonaOut:
    return ZonaOut(
        id=str(z.id), nombre=z.nombre, tipo=z.tipo,
        ubicacion_id=(str(z.ubicacion_id) if z.ubicacion_id else None),
        ubicacion_nombre=ubic_nombre,
    )


@router.get("/zonas", response_model=List[ZonaOut])
def listar_zonas(
    ubicacion_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    q = (
        db.query(Zona, Ubicacion.nombre)
        .outerjoin(Ubicacion, Ubicacion.id == Zona.ubicacion_id)
        .filter(Zona.empresa_id == payload["empresa_id"])
    )
    if ubicacion_id:
        q = q.filter(Zona.ubicacion_id == ubicacion_id)
    rows = q.order_by(Zona.nombre).all()
    return [_zona_out(z, nombre) for z, nombre in rows]


@router.post("/zonas", response_model=ZonaOut, status_code=201)
def crear_zona(body: ZonaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "crear")
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    ubic_nombre = None
    if body.ubicacion_id:
        ubic = db.query(Ubicacion).filter(Ubicacion.id == body.ubicacion_id, Ubicacion.empresa_id == empresa_id).first()
        if not ubic:
            raise HTTPException(status_code=400, detail="Ubicación inválida")
        ubic_nombre = ubic.nombre
    z = Zona(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre,
        tipo=(body.tipo or None), ubicacion_id=(body.ubicacion_id or None),
    )
    db.add(z)
    db.commit()
    return _zona_out(z, ubic_nombre)


@router.put("/zonas/{zona_id}", response_model=ZonaOut)
def actualizar_zona(zona_id: str, body: ZonaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "editar")
    empresa_id = payload["empresa_id"]
    z = db.query(Zona).filter(Zona.id == zona_id, Zona.empresa_id == empresa_id).first()
    if not z:
        raise HTTPException(status_code=404, detail="Zona no encontrada")
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    ubic_nombre = None
    if body.ubicacion_id:
        ubic = db.query(Ubicacion).filter(Ubicacion.id == body.ubicacion_id, Ubicacion.empresa_id == empresa_id).first()
        if not ubic:
            raise HTTPException(status_code=400, detail="Ubicación inválida")
        ubic_nombre = ubic.nombre
    z.nombre = nombre
    z.tipo = body.tipo or None
    z.ubicacion_id = body.ubicacion_id or None
    db.commit()
    return _zona_out(z, ubic_nombre)


@router.delete("/zonas/{zona_id}", status_code=204)
def eliminar_zona(zona_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "eliminar")
    z = db.query(Zona).filter(Zona.id == zona_id, Zona.empresa_id == payload["empresa_id"]).first()
    if not z:
        raise HTTPException(status_code=404, detail="Zona no encontrada")
    db.delete(z)
    db.commit()


# ──────────────────────────────────────────────────────────────────────────
# Áreas
# ──────────────────────────────────────────────────────────────────────────
@router.get("/areas", response_model=List[AreaOut])
def listar_areas(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    rows = (
        db.query(Area)
        .filter(Area.empresa_id == payload["empresa_id"])
        .order_by(Area.nombre)
        .all()
    )
    return [AreaOut(id=str(r.id), nombre=r.nombre) for r in rows]


@router.post("/areas", response_model=AreaOut, status_code=201)
def crear_area(body: AreaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "crear")
    empresa_id = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    existente = (
        db.query(Area)
        .filter(Area.empresa_id == empresa_id, func.lower(Area.nombre) == nombre.lower())
        .first()
    )
    if existente:
        return AreaOut(id=str(existente.id), nombre=existente.nombre)
    a = Area(id=str(_uuid.uuid4()), empresa_id=empresa_id, nombre=nombre)
    db.add(a)
    db.commit()
    return AreaOut(id=str(a.id), nombre=a.nombre)


@router.put("/areas/{area_id}", response_model=AreaOut)
def actualizar_area(area_id: str, body: AreaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "editar")
    a = db.query(Area).filter(Area.id == area_id, Area.empresa_id == payload["empresa_id"]).first()
    if not a:
        raise HTTPException(status_code=404, detail="Área no encontrada")
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    a.nombre = nombre
    db.commit()
    return AreaOut(id=str(a.id), nombre=a.nombre)


@router.delete("/areas/{area_id}", status_code=204)
def eliminar_area(area_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "catalogos", "eliminar")
    a = db.query(Area).filter(Area.id == area_id, Area.empresa_id == payload["empresa_id"]).first()
    if not a:
        raise HTTPException(status_code=404, detail="Área no encontrada")
    db.delete(a)
    db.commit()
