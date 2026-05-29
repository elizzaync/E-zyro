"""
Router: /calibraciones y /equipos (estado operativo) — Fase 3.
Calibraciones por equipo (últ./próx. + certificado) y marcar inoperativo/reactivar.
Lecturas: empresa del token. Escrituras: RBAC ('calibracion' / 'equipo').
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.calibracion import Calibracion, EquipoEstadoMov
from ..models.equipo import Equipo
from ..services.cloudinary_service import subir_e_indexar, eliminar_imagen_cloudinary
from ..services.cloudinary_paths import carpeta_calibracion
from ..schemas.calibracion import (
    CalibracionIn, CalibracionOut, CertificadoIn,
    EstadoMovIn, EquipoEstadoOut,
)

router = APIRouter(prefix="/calibraciones", tags=["calibraciones"])
router_estado = APIRouter(prefix="/equipos", tags=["equipos-estado"])


def _equipo_or_404(db: Session, empresa_id: str, equipo_id: str) -> Equipo:
    e = db.query(Equipo).filter(Equipo.id == equipo_id, Equipo.empresa_id == empresa_id).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo no encontrado")
    return e


def _cal_out(c: Calibracion, nombre: Optional[str]) -> CalibracionOut:
    return CalibracionOut(
        id=str(c.id), equipo_id=str(c.equipo_id), equipo_nombre=nombre,
        fecha_ultima=(str(c.fecha_ultima) if c.fecha_ultima else None),
        fecha_proxima=(str(c.fecha_proxima) if c.fecha_proxima else None),
        empresa_responsable=c.empresa_responsable, certificado_url=c.certificado_url,
        observacion=c.observacion,
    )


# ── Calibraciones ────────────────────────────────────────────────────────────
@router.get("", response_model=List[CalibracionOut])
def listar(
    equipo_id: Optional[str] = Query(None),
    por_vencer: bool = Query(False, description="próximas en <=30 días o vencidas"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = (
        db.query(Calibracion, Equipo.nombre)
        .outerjoin(Equipo, Equipo.id == Calibracion.equipo_id)
        .filter(Calibracion.empresa_id == payload["empresa_id"])
    )
    if equipo_id:
        qry = qry.filter(Calibracion.equipo_id == equipo_id)
    if por_vencer:
        qry = qry.filter(Calibracion.fecha_proxima <= text("current_date + interval '30 day'"))
    return [_cal_out(c, nombre) for c, nombre in qry.order_by(Calibracion.fecha_proxima).all()]


@router.post("", response_model=CalibracionOut, status_code=201)
def crear(body: CalibracionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "calibracion", "crear")
    empresa_id = payload["empresa_id"]
    eq = _equipo_or_404(db, empresa_id, body.equipo_id)
    c = Calibracion(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, equipo_id=body.equipo_id,
        fecha_ultima=body.fecha_ultima or None, fecha_proxima=body.fecha_proxima or None,
        empresa_responsable=body.empresa_responsable, observacion=body.observacion,
    )
    db.add(c)
    db.commit()
    return _cal_out(c, eq.nombre)


@router.put("/{cal_id}", response_model=CalibracionOut)
def actualizar(cal_id: str, body: CalibracionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "calibracion", "editar")
    empresa_id = payload["empresa_id"]
    c = db.query(Calibracion).filter(Calibracion.id == cal_id, Calibracion.empresa_id == empresa_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Calibración no encontrada")
    c.fecha_ultima = body.fecha_ultima or None
    c.fecha_proxima = body.fecha_proxima or None
    c.empresa_responsable = body.empresa_responsable
    c.observacion = body.observacion
    db.commit()
    nombre = db.query(Equipo.nombre).filter(Equipo.id == c.equipo_id).scalar()
    return _cal_out(c, nombre)


@router.delete("/{cal_id}", status_code=204)
def eliminar(cal_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "calibracion", "eliminar")
    c = db.query(Calibracion).filter(Calibracion.id == cal_id, Calibracion.empresa_id == payload["empresa_id"]).first()
    if not c:
        raise HTTPException(status_code=404, detail="Calibración no encontrada")
    db.delete(c)
    db.commit()


@router.post("/{cal_id}/certificado", response_model=CalibracionOut)
def subir_certificado(cal_id: str, body: CertificadoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "calibracion", "editar")
    empresa_id = payload["empresa_id"]
    c = db.query(Calibracion).filter(Calibracion.id == cal_id, Calibracion.empresa_id == empresa_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Calibración no encontrada")
    if c.certificado_url:
        eliminar_imagen_cloudinary(c.certificado_url)
    rec = subir_e_indexar(
        db, empresa_id=empresa_id, base64_data=body.archivo_base64,
        folder=carpeta_calibracion(empresa_id, str(c.equipo_id)), public_id=f"cert_{cal_id}",
        entidad_tipo="calibracion", entidad_id=cal_id, creado_por_id=payload.get("id"),
    )
    c.certificado_url = rec.secure_url
    db.commit()
    nombre = db.query(Equipo.nombre).filter(Equipo.id == c.equipo_id).scalar()
    return _cal_out(c, nombre)


# ── Estado operativo de equipos ──────────────────────────────────────────────
def _estado_out(e: Equipo) -> EquipoEstadoOut:
    return EquipoEstadoOut(
        equipo_id=str(e.id), nombre=e.nombre, cantidad=int(e.cantidad or 0),
        cantidad_inoperativa=int(getattr(e, "cantidad_inoperativa", 0) or 0),
        estado_operativo=(getattr(e, "estado_operativo", None) or "operativo"),
    )


def _recalcular_estado(e: Equipo) -> None:
    total = int(e.cantidad or 0)
    inop = int(getattr(e, "cantidad_inoperativa", 0) or 0)
    if inop <= 0:
        e.estado_operativo = "operativo"
    elif inop >= total:
        e.estado_operativo = "inoperativo"
    else:
        e.estado_operativo = "parcial"


@router_estado.get("/estado", response_model=List[EquipoEstadoOut])
def listar_estado(
    solo: Optional[str] = Query(None, description="operativos|inoperativos"),
    q: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(Equipo).filter(Equipo.empresa_id == payload["empresa_id"])
    if q:
        from sqlalchemy import func
        qry = qry.filter(func.lower(Equipo.nombre).like(f"%{q.strip().lower()}%"))
    rows = qry.order_by(Equipo.nombre).limit(500).all()
    out = [_estado_out(e) for e in rows]
    if solo == "inoperativos":
        out = [o for o in out if o.cantidad_inoperativa > 0]
    elif solo == "operativos":
        out = [o for o in out if o.cantidad_inoperativa == 0]
    return out


@router_estado.post("/{equipo_id}/inoperativo", response_model=EquipoEstadoOut)
def marcar_inoperativo(equipo_id: str, body: EstadoMovIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "equipo", "marcar_inoperativo")
    empresa_id = payload["empresa_id"]
    e = _equipo_or_404(db, empresa_id, equipo_id)
    total = int(e.cantidad or 0)
    inop = int(getattr(e, "cantidad_inoperativa", 0) or 0)
    if inop + body.cantidad > total:
        raise HTTPException(status_code=409, detail=f"No puede marcar {body.cantidad}: disponibles {total - inop} de {total}")
    db.add(EquipoEstadoMov(id=str(_uuid.uuid4()), empresa_id=empresa_id, equipo_id=equipo_id,
                           accion="inoperativo", cantidad=body.cantidad, motivo=body.motivo,
                           fecha=date.today(), registrado_por_id=payload.get("id")))
    e.cantidad_inoperativa = inop + body.cantidad
    _recalcular_estado(e)
    db.commit()
    return _estado_out(e)


@router_estado.post("/{equipo_id}/reactivar", response_model=EquipoEstadoOut)
def reactivar(equipo_id: str, body: EstadoMovIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "equipo", "reactivar")
    empresa_id = payload["empresa_id"]
    e = _equipo_or_404(db, empresa_id, equipo_id)
    inop = int(getattr(e, "cantidad_inoperativa", 0) or 0)
    if body.cantidad > inop:
        raise HTTPException(status_code=409, detail=f"No puede reactivar {body.cantidad}: inoperativas {inop}")
    db.add(EquipoEstadoMov(id=str(_uuid.uuid4()), empresa_id=empresa_id, equipo_id=equipo_id,
                           accion="reactivar", cantidad=body.cantidad, motivo=body.motivo,
                           fecha=date.today(), registrado_por_id=payload.get("id")))
    e.cantidad_inoperativa = inop - body.cantidad
    _recalcular_estado(e)
    db.commit()
    return _estado_out(e)
