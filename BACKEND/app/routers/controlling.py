"""
Router: /controlling — centros de costo / controlling básico (Fase 2).

CRUD de centros de costo (soft-delete vía activo=false) y reportes de costo
real vs. presupuesto. Los reportes leen el libro mayor mediante
controlling_service (solo lectura): nunca tocan asientos.
"""
from __future__ import annotations

from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.contabilidad import CentroCosto
from ..schemas.controlling import (
    CentroCostoCreate, CentroCostoUpdate, CentroCostoOut,
    CostoRealOut, ComparativoOut, RentabilidadProyectoOut,
)
from ..services import controlling_service as controlling

router = APIRouter(prefix="/controlling", tags=["controlling"])


def _out(c: CentroCosto) -> CentroCostoOut:
    return CentroCostoOut(
        id=str(c.id), codigo=c.codigo, nombre=c.nombre,
        tipo_referencia=c.tipo_referencia,
        referencia_id=(str(c.referencia_id) if c.referencia_id else None),
        presupuesto_referencial=c.presupuesto_referencial,
        activo=bool(c.activo),
    )


@router.get("/centros-costo", response_model=List[CentroCostoOut])
def listar_centros(
    tipo_referencia: Optional[str] = Query(None),
    activo: Optional[bool] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "controlling", "ver")
    q = db.query(CentroCosto).filter(CentroCosto.empresa_id == payload["empresa_id"])
    if tipo_referencia:
        q = q.filter(CentroCosto.tipo_referencia == tipo_referencia)
    if activo is not None:
        q = q.filter(CentroCosto.activo.is_(activo))
    return [_out(c) for c in q.order_by(CentroCosto.codigo).all()]


@router.post("/centros-costo", response_model=CentroCostoOut, status_code=201)
def crear_centro(
    body: CentroCostoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "controlling", "gestionar_centros_costo")
    existe = db.query(CentroCosto).filter(
        CentroCosto.empresa_id == payload["empresa_id"], CentroCosto.codigo == body.codigo,
    ).first()
    if existe:
        raise HTTPException(status_code=409, detail="Ya existe un centro de costo con ese código")
    c = CentroCosto(
        empresa_id=payload["empresa_id"], codigo=body.codigo, nombre=body.nombre,
        tipo_referencia=body.tipo_referencia, referencia_id=body.referencia_id,
        presupuesto_referencial=body.presupuesto_referencial, activo=True,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return _out(c)


def _get_centro(db: Session, empresa_id: str, centro_id: str) -> CentroCosto:
    c = db.query(CentroCosto).filter(
        CentroCosto.id == centro_id, CentroCosto.empresa_id == empresa_id,
    ).first()
    if not c:
        raise HTTPException(status_code=404, detail="Centro de costo no encontrado")
    return c


@router.put("/centros-costo/{centro_id}", response_model=CentroCostoOut)
def actualizar_centro(
    centro_id: str, body: CentroCostoUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "controlling", "gestionar_centros_costo")
    c = _get_centro(db, payload["empresa_id"], centro_id)
    if body.nombre is not None:
        c.nombre = body.nombre
    if body.tipo_referencia is not None:
        c.tipo_referencia = body.tipo_referencia
    if body.referencia_id is not None:
        c.referencia_id = body.referencia_id
    if body.presupuesto_referencial is not None:
        c.presupuesto_referencial = body.presupuesto_referencial
    if body.activo is not None:
        c.activo = body.activo
    db.commit()
    db.refresh(c)
    return _out(c)


@router.delete("/centros-costo/{centro_id}", response_model=CentroCostoOut)
def desactivar_centro(
    centro_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Soft-delete: desactiva el centro (conserva su historial de imputaciones)."""
    exigir_permiso(db, payload, "controlling", "gestionar_centros_costo")
    c = _get_centro(db, payload["empresa_id"], centro_id)
    c.activo = False
    db.commit()
    db.refresh(c)
    return _out(c)


@router.get("/centros-costo/{centro_id}/costo-real", response_model=CostoRealOut)
def costo_real(
    centro_id: str,
    desde: Optional[date] = Query(None), hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "controlling", "ver")
    _get_centro(db, payload["empresa_id"], centro_id)
    return CostoRealOut(**controlling.costo_real_por_centro(
        db, payload["empresa_id"], centro_id, desde, hasta))


@router.get("/centros-costo/{centro_id}/comparativo", response_model=ComparativoOut)
def comparativo(
    centro_id: str,
    desde: Optional[date] = Query(None), hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "controlling", "ver")
    _get_centro(db, payload["empresa_id"], centro_id)
    data = controlling.comparativo_presupuesto_vs_real(
        db, payload["empresa_id"], centro_id, desde, hasta)
    return ComparativoOut(**data)


# ── Rentabilidad por proyecto ────────────────────────────────────────────────
@router.get("/rentabilidad", response_model=List[RentabilidadProyectoOut])
def rentabilidad(
    desde: Optional[date] = Query(None), hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Ingresos − costos imputados − mano de obra estimada, por proyecto."""
    exigir_permiso(db, payload, "controlling", "ver")
    return controlling.rentabilidad_proyectos(db, payload["empresa_id"], desde, hasta)


@router.get("/rentabilidad/{proyecto_id}", response_model=RentabilidadProyectoOut)
def rentabilidad_detalle(
    proyecto_id: str,
    desde: Optional[date] = Query(None), hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Detalle de un proyecto con desglose por centro de costo y por empleado."""
    exigir_permiso(db, payload, "controlling", "ver")
    filas = controlling.rentabilidad_proyectos(
        db, payload["empresa_id"], desde, hasta, proyecto_id=proyecto_id)
    if not filas:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")
    return filas[0]
