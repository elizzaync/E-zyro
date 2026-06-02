"""
Router: /equipos-intervenidos
Equipos del cliente que E-System TIC instala o mantiene, vinculados a proyecto y ubicacion.
Lecturas: cualquier autenticado de la empresa.
Escrituras: permiso 'equipo_intervenido:crear' / 'editar' / 'eliminar'.
"""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.equipo_intervenido import EquipoIntervenido
from ..models.proyecto import Proyecto
from ..models.cliente import Cliente
from ..models.ubicacion import Ubicacion
from ..models.zona import Zona
from ..models.area import Area
from ..models.tipo_equipo import TipoEquipo
from ..schemas.equipo_intervenido import EquipoIntervenidoIn, EquipoIntervenidoOut

router = APIRouter(prefix="/equipos-intervenidos", tags=["equipos-intervenidos"])

ESTADOS_VALIDOS = {"operativo", "inoperativo", "mantenimiento", "en_revision"}


def _to_out(e: EquipoIntervenido, db: Session) -> EquipoIntervenidoOut:
    proyecto_nombre   = None
    cliente_nombre    = None
    ubicacion_nombre  = None
    zona_nombre       = None
    area_nombre       = None
    tipo_equipo_nombre = None

    if e.proyecto_id:
        p = db.query(Proyecto).filter(Proyecto.id == e.proyecto_id).first()
        if p:
            proyecto_nombre = p.nombre_proyecto
    if e.cliente_id:
        c = db.query(Cliente).filter(Cliente.id == e.cliente_id).first()
        if c:
            cliente_nombre = c.razon_social
    if e.ubicacion_id:
        u = db.query(Ubicacion).filter(Ubicacion.id == e.ubicacion_id).first()
        if u:
            ubicacion_nombre = u.nombre
    if e.zona_id:
        z = db.query(Zona).filter(Zona.id == e.zona_id).first()
        if z:
            zona_nombre = z.nombre
    if e.area_id:
        a = db.query(Area).filter(Area.id == e.area_id).first()
        if a:
            area_nombre = a.nombre
    if e.tipo_equipo_id:
        t = db.query(TipoEquipo).filter(TipoEquipo.id == e.tipo_equipo_id).first()
        if t:
            tipo_equipo_nombre = t.nombre

    return EquipoIntervenidoOut(
        id=str(e.id), empresa_id=str(e.empresa_id),
        proyecto_id=str(e.proyecto_id) if e.proyecto_id else None,
        cliente_id=str(e.cliente_id) if e.cliente_id else None,
        ubicacion_id=str(e.ubicacion_id) if e.ubicacion_id else None,
        zona_id=str(e.zona_id) if e.zona_id else None,
        area_id=str(e.area_id) if e.area_id else None,
        area_descripcion=e.area_descripcion,
        nombre=e.nombre, codigo=e.codigo,
        tipo_equipo_id=str(e.tipo_equipo_id) if e.tipo_equipo_id else None,
        marca=e.marca, modelo=e.modelo, numero_serie=e.numero_serie,
        estado=e.estado, fecha_instalacion=e.fecha_instalacion,
        ficha_tecnica=e.ficha_tecnica, observaciones=e.observaciones,
        activo=e.activo, created_at=e.created_at, updated_at=e.updated_at,
        proyecto_nombre=proyecto_nombre, cliente_nombre=cliente_nombre,
        ubicacion_nombre=ubicacion_nombre, zona_nombre=zona_nombre,
        area_nombre=area_nombre,
        tipo_equipo_nombre=tipo_equipo_nombre,
    )


# ── GET /equipos-intervenidos ─────────────────────────────────────────────────
@router.get("", response_model=List[EquipoIntervenidoOut])
def listar(
    proyecto_id:  Optional[str] = Query(None),
    cliente_id:   Optional[str] = Query(None),
    ubicacion_id: Optional[str] = Query(None),
    zona_id:      Optional[str] = Query(None),
    area_id:      Optional[str] = Query(None),
    estado:       Optional[str] = Query(None),
    activo:       Optional[bool] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    q = db.query(EquipoIntervenido).filter(EquipoIntervenido.empresa_id == empresa_id)
    if proyecto_id:
        q = q.filter(EquipoIntervenido.proyecto_id == proyecto_id)
    if cliente_id:
        q = q.filter(EquipoIntervenido.cliente_id == cliente_id)
    # Filtros geográficos (jerarquía ubicacion → zona → area)
    if ubicacion_id:
        q = q.filter(EquipoIntervenido.ubicacion_id == ubicacion_id)
    if zona_id:
        q = q.filter(EquipoIntervenido.zona_id == zona_id)
    if area_id:
        q = q.filter(EquipoIntervenido.area_id == area_id)
    if estado:
        q = q.filter(EquipoIntervenido.estado == estado)
    if activo is not None:
        q = q.filter(EquipoIntervenido.activo == activo)
    return [_to_out(e, db) for e in q.order_by(EquipoIntervenido.nombre).all()]


# ── GET /equipos-intervenidos/{id} ───────────────────────────────────────────
@router.get("/{equipo_id}", response_model=EquipoIntervenidoOut)
def detalle(
    equipo_id: str,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")
    return _to_out(e, db)


# ── POST /equipos-intervenidos ────────────────────────────────────────────────
@router.post("", response_model=EquipoIntervenidoOut, status_code=201)
def crear(
    body: EquipoIntervenidoIn,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    exigir_permiso(db, payload, "equipo_intervenido", "crear")
    empresa_id = payload["empresa_id"]

    if body.estado and body.estado not in ESTADOS_VALIDOS:
        raise HTTPException(status_code=422, detail=f"Estado invalido. Usar: {ESTADOS_VALIDOS}")

    e = EquipoIntervenido(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        **body.model_dump(exclude_none=True),
    )
    db.add(e)
    db.commit()
    db.refresh(e)
    return _to_out(e, db)


# ── PATCH /equipos-intervenidos/{id} ─────────────────────────────────────────
@router.patch("/{equipo_id}", response_model=EquipoIntervenidoOut)
def actualizar(
    equipo_id: str,
    body: EquipoIntervenidoIn,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    exigir_permiso(db, payload, "equipo_intervenido", "editar")
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")

    if body.estado and body.estado not in ESTADOS_VALIDOS:
        raise HTTPException(status_code=422, detail=f"Estado invalido. Usar: {ESTADOS_VALIDOS}")

    for campo, valor in body.model_dump(exclude_unset=True).items():
        setattr(e, campo, valor)
    e.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(e)
    return _to_out(e, db)


# ── DELETE /equipos-intervenidos/{id} ────────────────────────────────────────
@router.delete("/{equipo_id}", status_code=204)
def eliminar(
    equipo_id: str,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    exigir_permiso(db, payload, "equipo_intervenido", "eliminar")
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")
    db.delete(e)
    db.commit()
