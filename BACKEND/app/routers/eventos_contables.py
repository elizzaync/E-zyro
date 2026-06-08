"""
Router: /eventos-contables — bus de eventos / mapeos contables (Fase 10).

Gestión de la tabla de mapeo (configuración editable desde el aplicativo) y
consulta del historial de trazabilidad origen→evento→asiento.
"""
from __future__ import annotations

import json
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.eventos_contables import MapeoTransaccionContable, EventoContableHistorial

router = APIRouter(prefix="/eventos-contables", tags=["eventos-contables"])


class LineaPlantilla(BaseModel):
    cuenta_codigo: str
    tipo: str            # debito|credito
    origen_monto: str    # campo de datos_origen


class MapeoCreate(BaseModel):
    tipo_evento: str
    descripcion: Optional[str] = None
    plantilla_lineas: List[LineaPlantilla]
    activo: bool = True


class MapeoOut(BaseModel):
    id: str
    tipo_evento: str
    descripcion: Optional[str] = None
    plantilla_lineas: List[LineaPlantilla]
    activo: bool


class HistorialOut(BaseModel):
    id: str
    tipo_evento: str
    referencia_id: Optional[str] = None
    asiento_id: Optional[str] = None
    resultado: str
    created_at: str


def _mapeo_out(m: MapeoTransaccionContable) -> MapeoOut:
    try:
        plantilla = json.loads(m.plantilla_lineas or "[]")
    except json.JSONDecodeError:
        plantilla = []
    return MapeoOut(
        id=str(m.id), tipo_evento=m.tipo_evento, descripcion=m.descripcion,
        plantilla_lineas=[LineaPlantilla(**l) for l in plantilla], activo=bool(m.activo),
    )


@router.get("/mapeos", response_model=List[MapeoOut])
def listar_mapeos(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "eventos_contables", "ver")
    filas = db.query(MapeoTransaccionContable).filter(
        MapeoTransaccionContable.empresa_id == payload["empresa_id"]).order_by(
        MapeoTransaccionContable.tipo_evento).all()
    return [_mapeo_out(m) for m in filas]


@router.post("/mapeos", response_model=MapeoOut, status_code=201)
def crear_mapeo(
    body: MapeoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "eventos_contables", "configurar_mapeos")
    dup = db.query(MapeoTransaccionContable).filter(
        MapeoTransaccionContable.empresa_id == payload["empresa_id"],
        MapeoTransaccionContable.tipo_evento == body.tipo_evento).first()
    if dup:
        raise HTTPException(status_code=409, detail="Ya existe un mapeo para ese tipo de evento.")
    m = MapeoTransaccionContable(
        empresa_id=payload["empresa_id"], tipo_evento=body.tipo_evento, descripcion=body.descripcion,
        plantilla_lineas=json.dumps([l.model_dump() for l in body.plantilla_lineas]),
        activo=body.activo,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return _mapeo_out(m)


@router.put("/mapeos/{mapeo_id}", response_model=MapeoOut)
def actualizar_mapeo(
    mapeo_id: str, body: MapeoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "eventos_contables", "configurar_mapeos")
    m = db.query(MapeoTransaccionContable).filter(
        MapeoTransaccionContable.id == mapeo_id,
        MapeoTransaccionContable.empresa_id == payload["empresa_id"]).first()
    if not m:
        raise HTTPException(status_code=404, detail="Mapeo no encontrado.")
    m.tipo_evento = body.tipo_evento
    m.descripcion = body.descripcion
    m.plantilla_lineas = json.dumps([l.model_dump() for l in body.plantilla_lineas])
    m.activo = body.activo
    db.commit()
    db.refresh(m)
    return _mapeo_out(m)


@router.get("/historial", response_model=List[HistorialOut])
def historial(
    tipo_evento: Optional[str] = Query(None),
    desde: Optional[date] = Query(None),
    hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "eventos_contables", "ver")
    q = db.query(EventoContableHistorial).filter(
        EventoContableHistorial.empresa_id == payload["empresa_id"])
    if tipo_evento:
        q = q.filter(EventoContableHistorial.tipo_evento == tipo_evento)
    if desde:
        q = q.filter(EventoContableHistorial.created_at >= desde)
    if hasta:
        q = q.filter(EventoContableHistorial.created_at <= hasta)
    filas = q.order_by(EventoContableHistorial.created_at.desc()).limit(500).all()
    return [HistorialOut(
        id=str(h.id), tipo_evento=h.tipo_evento,
        referencia_id=(str(h.referencia_id) if h.referencia_id else None),
        asiento_id=(str(h.asiento_id) if h.asiento_id else None),
        resultado=h.resultado, created_at=h.created_at.isoformat()) for h in filas]
