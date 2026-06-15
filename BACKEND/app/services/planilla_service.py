"""
Servicio de planilla (Fase 8).

Flujo: calcular (sin contabilizar, permite revisión) → aprobar (asiento de
provisión) → marcar pagada (asiento de pago). El cálculo aplica los conceptos
remunerativos CONFIGURABLES por empleado; las fórmulas legales reales son datos
validados externamente (ver nota en models/planilla.py).

Asientos (cuentas de detalle del PCGE), balanceados por construcción:
  Provisión : Db 621 Remuneraciones (ingresos) + Db 627 Aportes empleador
              Cr 411 Remuneraciones por pagar (neto)
              Cr 4032 (descuentos/retenciones) + Cr 4031 (aportes empleador)
  Pago      : Db 411 (neto) + Db 4032 + Db 4031   /   Cr 101 Caja (total egreso)
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable, PeriodoContable
from app.models.empleado import Empleado
from app.models.planilla import (
    ConceptoRemunerativo, Planilla, BoletaPago, BoletaPagoDetalle, EmpleadoConcepto,
)
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")

CTA_GASTO_REMUN   = "621"   # Remuneraciones
CTA_GASTO_APORTES = "627"   # Seguridad, previsión social y otras contribuciones
CTA_REMUN_PAGAR   = "411"   # Remuneraciones por pagar
CTA_RETENCIONES   = "4032"  # ONP (retenciones a cargo del trabajador)
CTA_APORTES_PAGAR = "4031"  # EsSalud (aportes del empleador)
CTA_CAJA          = "101"


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


def _cuenta(db: Session, empresa_id: str, codigo: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == codigo)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422, detail=f"Falta la cuenta {codigo} en el plan.")
    return c


def get_planilla(db: Session, empresa_id: str, planilla_id: str) -> Planilla:
    p = db.query(Planilla).filter(Planilla.id == planilla_id, Planilla.empresa_id == empresa_id).first()
    if p is None:
        raise HTTPException(status_code=404, detail="Planilla no encontrada.")
    return p


# ── Calcular (sin contabilizar) ──────────────────────────────────────────────
def calcular_planilla(db: Session, empresa_id: str, periodo_id: str) -> Planilla:
    """Genera la planilla del periodo en estado 'calculada' aplicando los
    conceptos activos a cada empleado activo. No contabiliza todavía."""
    periodo = db.query(PeriodoContable).filter(
        PeriodoContable.id == periodo_id, PeriodoContable.empresa_id == empresa_id).first()
    if periodo is None:
        raise HTTPException(status_code=404, detail="Periodo no encontrado.")

    # Una planilla ANULADA no bloquea: el usuario puede recalcular el periodo.
    # Solo cuenta como duplicado una planilla vigente (calculada/aprobada/pagada).
    existe = db.query(Planilla).filter(
        Planilla.empresa_id == empresa_id,
        Planilla.periodo_id == periodo_id,
        Planilla.estado != "anulada",
    ).first()
    if existe:
        raise HTTPException(status_code=409, detail="Ya existe una planilla vigente para ese periodo.")

    conceptos = (
        db.query(ConceptoRemunerativo)
        .filter(ConceptoRemunerativo.empresa_id == empresa_id,
                ConceptoRemunerativo.activo == "true")
        .all()
    )
    if not conceptos:
        raise HTTPException(status_code=422, detail="No hay conceptos remunerativos configurados.")

    empleados = db.query(Empleado).filter(
        Empleado.empresa_id == empresa_id, Empleado.activo.is_(True)).all()
    if not empleados:
        raise HTTPException(status_code=422, detail="No hay empleados activos para procesar.")

    # Montos asignados por empleado (sueldos individuales). Si no hay asignación
    # para (empleado, concepto), se usa el monto_referencial del catálogo.
    overrides = {
        (a.empleado_id, a.concepto_id): a.monto
        for a in db.query(EmpleadoConcepto).filter(
            EmpleadoConcepto.empresa_id == empresa_id).all()
    }

    planilla = Planilla(
        empresa_id=empresa_id, periodo_id=periodo_id, fecha_proceso=date.today(),
        estado="calculada", total_ingresos=CERO, total_descuentos=CERO,
        total_aportes=CERO, total_neto=CERO,
    )
    db.add(planilla)
    db.flush()

    tot_ing = tot_desc = tot_apo = CERO
    for emp in empleados:
        b_ing = b_desc = b_apo = CERO
        detalles = []
        for c in conceptos:
            asignado = overrides.get((emp.id, c.id))
            monto = _d(asignado if asignado is not None else c.monto_referencial)
            if monto <= CERO:
                continue
            detalles.append((c.id, monto))
            if c.tipo == "ingreso":
                b_ing += monto
            elif c.tipo == "descuento":
                b_desc += monto
            else:  # aporte_empleador
                b_apo += monto
        if not detalles:
            continue
        b_neto = b_ing - b_desc
        boleta = BoletaPago(
            planilla_id=planilla.id, empleado_id=emp.id, total_ingresos=b_ing,
            total_descuentos=b_desc, total_aportes=b_apo, total_neto=b_neto,
        )
        db.add(boleta)
        db.flush()
        for concepto_id, monto in detalles:
            db.add(BoletaPagoDetalle(boleta_id=boleta.id, concepto_id=concepto_id, monto=monto))
        tot_ing += b_ing
        tot_desc += b_desc
        tot_apo += b_apo

    planilla.total_ingresos = tot_ing
    planilla.total_descuentos = tot_desc
    planilla.total_aportes = tot_apo
    planilla.total_neto = tot_ing - tot_desc
    db.commit()
    db.refresh(planilla)
    return planilla


# ── Aprobar (asiento de provisión) ───────────────────────────────────────────
def aprobar_planilla(db: Session, empresa_id: str, planilla_id: str, aprobado_por_id: str | None = None) -> Planilla:
    planilla = get_planilla(db, empresa_id, planilla_id)
    if planilla.estado != "calculada":
        raise HTTPException(status_code=409, detail=f"Solo se aprueba una planilla 'calculada' (actual: {planilla.estado}).")

    periodo = db.query(PeriodoContable).filter(PeriodoContable.id == planilla.periodo_id).first()
    fecha = date(periodo.anio, periodo.mes, 1)

    ingresos = _d(planilla.total_ingresos)
    descuentos = _d(planilla.total_descuentos)
    aportes = _d(planilla.total_aportes)
    neto = _d(planilla.total_neto)

    lineas = []
    if ingresos > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_GASTO_REMUN).id, debito=ingresos))
    if aportes > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_GASTO_APORTES).id, debito=aportes))
    if neto > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_REMUN_PAGAR).id, credito=neto))
    if descuentos > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_RETENCIONES).id, credito=descuentos))
    if aportes > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_APORTES_PAGAR).id, credito=aportes))

    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha,
            descripcion=f"Provisión de planilla {periodo.anio}-{periodo.mes:02d}",
            origen="planilla", lineas=lineas, referencia_id=planilla.id,
            creado_por_id=aprobado_por_id, commit=False,
        )
        planilla.asiento_provision_id = asiento.id
        planilla.estado = "aprobada"
        planilla.aprobado_por_id = aprobado_por_id
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo aprobar la planilla: {exc}") from exc

    db.refresh(planilla)
    return planilla


# ── Marcar pagada (asiento de pago) ──────────────────────────────────────────
def marcar_pagada(db: Session, empresa_id: str, planilla_id: str, creado_por_id: str | None = None) -> Planilla:
    planilla = get_planilla(db, empresa_id, planilla_id)
    if planilla.estado != "aprobada":
        raise HTTPException(status_code=409, detail=f"Solo se paga una planilla 'aprobada' (actual: {planilla.estado}).")

    periodo = db.query(PeriodoContable).filter(PeriodoContable.id == planilla.periodo_id).first()
    fecha = date(periodo.anio, periodo.mes, 1)

    neto = _d(planilla.total_neto)
    descuentos = _d(planilla.total_descuentos)
    aportes = _d(planilla.total_aportes)
    egreso = neto + descuentos + aportes  # se cancelan remuneraciones + retenciones + aportes

    lineas = []
    if neto > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_REMUN_PAGAR).id, debito=neto))
    if descuentos > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_RETENCIONES).id, debito=descuentos))
    if aportes > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_APORTES_PAGAR).id, debito=aportes))
    if egreso > CERO:
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_CAJA).id, credito=egreso))

    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha,
            descripcion=f"Pago de planilla {periodo.anio}-{periodo.mes:02d}",
            origen="planilla", lineas=lineas, referencia_id=planilla.id,
            creado_por_id=creado_por_id, commit=False,
        )
        planilla.asiento_pago_id = asiento.id
        planilla.estado = "pagada"
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo pagar la planilla: {exc}") from exc

    db.refresh(planilla)
    return planilla


# ── Anular (solo antes de aprobar) ───────────────────────────────────────────
def anular_planilla(db: Session, empresa_id: str, planilla_id: str) -> Planilla:
    planilla = get_planilla(db, empresa_id, planilla_id)
    if planilla.estado != "calculada":
        raise HTTPException(
            status_code=409,
            detail="Solo se anula una planilla 'calculada'; una aprobada requiere reversión contable.",
        )
    planilla.estado = "anulada"
    db.commit()
    db.refresh(planilla)
    return planilla
