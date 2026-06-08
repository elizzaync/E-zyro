"""
Router: /planilla — nómina / planilla (Fase 8).

Flujo: calcular → aprobar (provisión) → marcar-pagada (pago). Gestión del
catálogo de conceptos remunerativos. Todo el efecto contable pasa por
planilla_service → registrar_asiento. RBAC (modulo='planilla').
"""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.contabilidad import PeriodoContable
from ..models.planilla import (
    ConceptoRemunerativo, Planilla, BoletaPago, BoletaPagoDetalle,
)
from ..schemas.planilla import (
    ConceptoCreate, ConceptoOut, PlanillaOut, BoletaOut, BoletaDetalleOut,
)
from ..services import planilla_service as planilla_svc

router = APIRouter(prefix="/planilla", tags=["planilla"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


def _planilla_out(p: Planilla) -> PlanillaOut:
    return PlanillaOut(
        id=str(p.id), periodo_id=str(p.periodo_id), fecha_proceso=p.fecha_proceso,
        estado=p.estado, total_ingresos=p.total_ingresos, total_descuentos=p.total_descuentos,
        total_aportes=p.total_aportes, total_neto=p.total_neto,
        asiento_provision_id=(str(p.asiento_provision_id) if p.asiento_provision_id else None),
        asiento_pago_id=(str(p.asiento_pago_id) if p.asiento_pago_id else None),
    )


# ── Conceptos remunerativos (catálogo configurable) ──────────────────────────
@router.get("/conceptos", response_model=List[ConceptoOut])
def listar_conceptos(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    filas = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.empresa_id == payload["empresa_id"]).order_by(ConceptoRemunerativo.codigo).all()
    return [ConceptoOut(id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
                        monto_referencial=c.monto_referencial, activo=(c.activo == "true")) for c in filas]


@router.post("/conceptos", response_model=ConceptoOut, status_code=201)
def crear_concepto(
    body: ConceptoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "calcular")
    dup = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.empresa_id == payload["empresa_id"],
        ConceptoRemunerativo.codigo == body.codigo).first()
    if dup:
        raise HTTPException(status_code=409, detail="Ya existe un concepto con ese código.")
    c = ConceptoRemunerativo(
        empresa_id=payload["empresa_id"], codigo=body.codigo, nombre=body.nombre, tipo=body.tipo,
        monto_referencial=body.monto_referencial, formula_referencial=body.formula_referencial,
        cuenta_contable_id=body.cuenta_contable_id, activo="true",
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return ConceptoOut(id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
                       monto_referencial=c.monto_referencial, activo=True)


# ── Planilla ─────────────────────────────────────────────────────────────────
@router.get("", response_model=List[PlanillaOut])
def listar_planillas(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    filas = db.query(Planilla).filter(Planilla.empresa_id == payload["empresa_id"]).order_by(Planilla.created_at.desc()).all()
    return [_planilla_out(p) for p in filas]


def _periodo(db: Session, empresa_id: str, periodo: str) -> PeriodoContable:
    try:
        anio, mes = (int(x) for x in periodo.split("-"))
    except Exception:
        raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")
    p = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == empresa_id, PeriodoContable.anio == anio,
        PeriodoContable.mes == mes).first()
    if not p:
        raise HTTPException(status_code=404, detail=f"No existe periodo {periodo}.")
    return p


@router.post("/calcular", response_model=PlanillaOut, status_code=201)
def calcular(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "calcular")
    p = _periodo(db, payload["empresa_id"], periodo)
    return _planilla_out(planilla_svc.calcular_planilla(db, payload["empresa_id"], p.id))


@router.get("/{planilla_id}", response_model=PlanillaOut)
def obtener(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    return _planilla_out(planilla_svc.get_planilla(db, payload["empresa_id"], planilla_id))


@router.post("/{planilla_id}/aprobar", response_model=PlanillaOut)
def aprobar(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "aprobar")
    return _planilla_out(planilla_svc.aprobar_planilla(db, payload["empresa_id"], planilla_id, _empleado_id(db, payload)))


@router.post("/{planilla_id}/marcar-pagada", response_model=PlanillaOut)
def marcar_pagada(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "aprobar")
    return _planilla_out(planilla_svc.marcar_pagada(db, payload["empresa_id"], planilla_id, _empleado_id(db, payload)))


@router.post("/{planilla_id}/anular", response_model=PlanillaOut)
def anular(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "anular")
    return _planilla_out(planilla_svc.anular_planilla(db, payload["empresa_id"], planilla_id))


@router.get("/{planilla_id}/boletas", response_model=List[BoletaOut])
def listar_boletas(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    planilla_svc.get_planilla(db, payload["empresa_id"], planilla_id)  # valida pertenencia
    boletas = db.query(BoletaPago).filter(BoletaPago.planilla_id == planilla_id).all()
    salida = []
    for b in boletas:
        detalles = db.query(BoletaPagoDetalle).filter(BoletaPagoDetalle.boleta_id == b.id).all()
        salida.append(BoletaOut(
            id=str(b.id), empleado_id=str(b.empleado_id), total_ingresos=b.total_ingresos,
            total_descuentos=b.total_descuentos, total_aportes=b.total_aportes, total_neto=b.total_neto,
            detalles=[BoletaDetalleOut(concepto_id=str(d.concepto_id), monto=d.monto) for d in detalles],
        ))
    return salida
