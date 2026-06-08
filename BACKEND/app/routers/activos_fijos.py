"""
Router: /activos-fijos — activos fijos y depreciación (Fase 7).

CRUD de activos, historial de depreciación y ejecución manual/forzada del
proceso de depreciación de un periodo (mismo guard de idempotencia que el job).
"""
from __future__ import annotations

from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.contabilidad import PeriodoContable
from ..models.activos_fijos import ActivoFijo, DepreciacionMensual
from ..schemas.activos_fijos import (
    ActivoFijoCreate, ActivoFijoUpdate, ActivoFijoOut,
    DepreciacionFilaOut, ProcesarDepreciacionOut,
)
from ..services import activos_fijos_service as af

router = APIRouter(prefix="/activos-fijos", tags=["activos-fijos"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


def _out(db: Session, a: ActivoFijo) -> ActivoFijoOut:
    return ActivoFijoOut(
        id=str(a.id), nombre=a.nombre, equipo_id=(str(a.equipo_id) if a.equipo_id else None),
        fecha_adquisicion=a.fecha_adquisicion, valor_adquisicion=a.valor_adquisicion,
        valor_residual=a.valor_residual, vida_util_meses=a.vida_util_meses,
        metodo_depreciacion=a.metodo_depreciacion,
        fecha_inicio_depreciacion=a.fecha_inicio_depreciacion, estado=a.estado,
        centro_costo_id=(str(a.centro_costo_id) if a.centro_costo_id else None),
        depreciacion_acumulada=af.depreciacion_acumulada(db, a.id),
        valor_en_libros=af.valor_en_libros(db, a),
    )


@router.get("", response_model=List[ActivoFijoOut])
def listar(
    estado: Optional[str] = Query(None), centro_costo: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "activos_fijos", "ver")
    q = db.query(ActivoFijo).filter(ActivoFijo.empresa_id == payload["empresa_id"])
    if estado:
        q = q.filter(ActivoFijo.estado == estado)
    if centro_costo:
        q = q.filter(ActivoFijo.centro_costo_id == centro_costo)
    return [_out(db, a) for a in q.order_by(ActivoFijo.nombre).all()]


@router.post("", response_model=ActivoFijoOut, status_code=201)
def crear(
    body: ActivoFijoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "activos_fijos", "gestionar")
    a = ActivoFijo(
        empresa_id=payload["empresa_id"], nombre=body.nombre, equipo_id=body.equipo_id,
        fecha_adquisicion=body.fecha_adquisicion, valor_adquisicion=body.valor_adquisicion,
        valor_residual=body.valor_residual, vida_util_meses=body.vida_util_meses,
        metodo_depreciacion="linea_recta",
        fecha_inicio_depreciacion=(body.fecha_inicio_depreciacion or body.fecha_adquisicion),
        estado="activo", centro_costo_id=body.centro_costo_id,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return _out(db, a)


def _get(db: Session, empresa_id: str, activo_id: str) -> ActivoFijo:
    a = db.query(ActivoFijo).filter(ActivoFijo.id == activo_id, ActivoFijo.empresa_id == empresa_id).first()
    if not a:
        raise HTTPException(status_code=404, detail="Activo fijo no encontrado.")
    return a


@router.put("/{activo_id}", response_model=ActivoFijoOut)
def actualizar(
    activo_id: str, body: ActivoFijoUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "activos_fijos", "gestionar")
    a = _get(db, payload["empresa_id"], activo_id)
    if body.nombre is not None:
        a.nombre = body.nombre
    if body.valor_residual is not None:
        a.valor_residual = body.valor_residual
    if body.centro_costo_id is not None:
        a.centro_costo_id = body.centro_costo_id
    db.commit()
    db.refresh(a)
    return _out(db, a)


@router.post("/{activo_id}/dar-de-baja", response_model=ActivoFijoOut)
def dar_de_baja(
    activo_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Detiene la depreciación futura sin afectar el historial ya generado."""
    exigir_permiso(db, payload, "activos_fijos", "dar_de_baja")
    a = _get(db, payload["empresa_id"], activo_id)
    a.estado = "dado_de_baja"
    db.commit()
    db.refresh(a)
    return _out(db, a)


@router.get("/{activo_id}/depreciacion", response_model=List[DepreciacionFilaOut])
def historial_depreciacion(
    activo_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "activos_fijos", "ver")
    _get(db, payload["empresa_id"], activo_id)
    filas = (
        db.query(DepreciacionMensual)
        .filter(DepreciacionMensual.activo_fijo_id == activo_id)
        .order_by(DepreciacionMensual.procesado_at)
        .all()
    )
    return [DepreciacionFilaOut(
        periodo_id=str(f.periodo_id), monto_depreciado=f.monto_depreciado,
        valor_en_libros_resultante=f.valor_en_libros_resultante,
        asiento_id=(str(f.asiento_id) if f.asiento_id else None)) for f in filas]


@router.post("/procesar-depreciacion", response_model=ProcesarDepreciacionOut)
def procesar_depreciacion(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "activos_fijos", "gestionar")
    try:
        anio, mes = (int(x) for x in periodo.split("-"))
    except Exception:
        raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")
    p = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == payload["empresa_id"],
        PeriodoContable.anio == anio, PeriodoContable.mes == mes).first()
    if not p:
        raise HTTPException(status_code=404, detail=f"No existe periodo {periodo}.")
    res = af.procesar_depreciacion_periodo(db, payload["empresa_id"], p.id, _empleado_id(db, payload))
    return ProcesarDepreciacionOut(**res)
