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

import calendar as _cal

from app.models.contabilidad import CuentaContable, PeriodoContable
from app.models.empleado import Empleado
from app.models.empresa import Empresa
from app.models.planilla import (
    ConceptoRemunerativo, Planilla, BoletaPago, BoletaPagoDetalle, EmpleadoConcepto,
)
from app.services import contabilizacion_service as contab
from app.services import planilla_asistencia_service as pa
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")

# Conceptos de descuento auto-generados desde la asistencia (Fase 2).
COD_DESC_FALTA    = "DESC_FALTA"
COD_DESC_TARDANZA = "DESC_TARDANZA"


def _get_or_create_descuento(db: Session, empresa_id: str, codigo: str, nombre: str) -> ConceptoRemunerativo:
    """Concepto de descuento (tipo='descuento') sin monto fijo; el importe lo
    calcula la asistencia por boleta. Idempotente por (empresa, código)."""
    c = (
        db.query(ConceptoRemunerativo)
        .filter(ConceptoRemunerativo.empresa_id == empresa_id,
                ConceptoRemunerativo.codigo == codigo)
        .first()
    )
    if c is None:
        c = ConceptoRemunerativo(
            empresa_id=empresa_id, codigo=codigo, nombre=nombre,
            tipo="descuento", monto_referencial=None, activo="true", es_base="false",
        )
        db.add(c)
        db.flush()
    return c

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

    # Las planillas ANULADAS no bloquean por negocio, pero sí ocupan el cupo de
    # la restricción única (empresa_id, periodo_id). Como anular solo procede
    # desde 'calculada' (sin asientos contables), son desechables: se eliminan
    # con sus boletas para liberar el periodo y permitir recalcular.
    anuladas = db.query(Planilla).filter(
        Planilla.empresa_id == empresa_id,
        Planilla.periodo_id == periodo_id,
        Planilla.estado == "anulada",
    ).all()
    for pa in anuladas:
        boletas_ids = [b.id for b in db.query(BoletaPago).filter(
            BoletaPago.planilla_id == pa.id).all()]
        if boletas_ids:
            db.query(BoletaPagoDetalle).filter(
                BoletaPagoDetalle.boleta_id.in_(boletas_ids)).delete(synchronize_session=False)
            db.query(BoletaPago).filter(
                BoletaPago.planilla_id == pa.id).delete(synchronize_session=False)
        db.delete(pa)
    db.flush()

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

    # ── Asistencia → descuentos (Fase 2) ─────────────────────────────────────
    # valor_día = monto del concepto BASE (es_base) / 30. Si no hay concepto
    # base configurado, no se aplican descuentos automáticos por asistencia.
    empresa = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    desc_tardanza_auto = bool(getattr(empresa, "descuento_tardanza_auto", True)) if empresa else True
    base_concepto = next(
        (c for c in conceptos if str(getattr(c, "es_base", "false")).lower() == "true"), None)
    inicio_p = date(periodo.anio, periodo.mes, 1)
    fin_p = date(periodo.anio, periodo.mes, _cal.monthrange(periodo.anio, periodo.mes)[1])
    asistencia = pa.resumen_asistencia_periodo(db, empresa_id, inicio_p, fin_p)
    concepto_falta = _get_or_create_descuento(db, empresa_id, COD_DESC_FALTA, "Descuento por falta")
    concepto_tardanza = _get_or_create_descuento(db, empresa_id, COD_DESC_TARDANZA, "Descuento por tardanza")

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

        # ── Descuentos por asistencia (faltas/tardanzas) ─────────────────────
        res = asistencia.get(str(emp.id))
        if res and base_concepto is not None:
            base_asignado = overrides.get((emp.id, base_concepto.id))
            base_monto = _d(base_asignado if base_asignado is not None else base_concepto.monto_referencial)
            valor_dia = (base_monto / Decimal(30)) if base_monto > CERO else CERO
            if valor_dia > CERO:
                if res["faltas"] > 0:
                    m = _d(valor_dia * res["faltas"])
                    if m > CERO:
                        detalles.append((concepto_falta.id, m))
                        b_desc += m
                if (desc_tardanza_auto and res["minutos_tardanza"] > 0
                        and res["minutos_jornada"] > 0):
                    m = _d(valor_dia * Decimal(res["minutos_tardanza"]) / Decimal(res["minutos_jornada"]))
                    if m > CERO:
                        detalles.append((concepto_tardanza.id, m))
                        b_desc += m

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


# ── Override manual de un detalle de boleta (antes de aprobar) ────────────────
def _recompute_boleta(db: Session, boleta: BoletaPago) -> None:
    """Recalcula los totales de una boleta desde sus detalles."""
    dets = db.query(BoletaPagoDetalle).filter(BoletaPagoDetalle.boleta_id == boleta.id).all()
    ids = {d.concepto_id for d in dets}
    tipos = {}
    if ids:
        tipos = {str(c.id): c.tipo for c in db.query(ConceptoRemunerativo).filter(
            ConceptoRemunerativo.id.in_(ids)).all()}
    ing = desc = apo = CERO
    for d in dets:
        t = tipos.get(str(d.concepto_id))
        if t == "ingreso":
            ing += _d(d.monto)
        elif t == "descuento":
            desc += _d(d.monto)
        else:
            apo += _d(d.monto)
    boleta.total_ingresos = ing
    boleta.total_descuentos = desc
    boleta.total_aportes = apo
    boleta.total_neto = ing - desc


def _recompute_planilla(db: Session, planilla: Planilla) -> None:
    """Recalcula los totales de la planilla desde sus boletas."""
    bs = db.query(BoletaPago).filter(BoletaPago.planilla_id == planilla.id).all()
    planilla.total_ingresos = sum((_d(b.total_ingresos) for b in bs), CERO)
    planilla.total_descuentos = sum((_d(b.total_descuentos) for b in bs), CERO)
    planilla.total_aportes = sum((_d(b.total_aportes) for b in bs), CERO)
    planilla.total_neto = planilla.total_ingresos - planilla.total_descuentos


def editar_boleta_detalle(db: Session, empresa_id: str, planilla_id: str,
                          boleta_id: str, concepto_id: str, monto) -> Planilla:
    """Ajuste manual (override) de un concepto en una boleta mientras la planilla
    está 'calculada'. monto<=0 elimina el detalle. Recalcula boleta y planilla.
    Permite corregir los descuentos automáticos por asistencia antes de aprobar."""
    planilla = get_planilla(db, empresa_id, planilla_id)
    if planilla.estado != "calculada":
        raise HTTPException(status_code=409,
                            detail=f"Solo se edita una planilla 'calculada' (actual: {planilla.estado}).")
    boleta = db.query(BoletaPago).filter(
        BoletaPago.id == boleta_id, BoletaPago.planilla_id == planilla_id).first()
    if boleta is None:
        raise HTTPException(status_code=404, detail="Boleta no encontrada.")
    concepto = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.id == concepto_id,
        ConceptoRemunerativo.empresa_id == empresa_id).first()
    if concepto is None:
        raise HTTPException(status_code=404, detail="Concepto no encontrado.")

    m = _d(monto)
    det = db.query(BoletaPagoDetalle).filter(
        BoletaPagoDetalle.boleta_id == boleta.id,
        BoletaPagoDetalle.concepto_id == concepto_id).first()
    if m <= CERO:
        if det is not None:
            db.delete(det)
    elif det is not None:
        det.monto = m
    else:
        db.add(BoletaPagoDetalle(boleta_id=boleta.id, concepto_id=concepto_id, monto=m))
    db.flush()

    _recompute_boleta(db, boleta)
    _recompute_planilla(db, planilla)
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
