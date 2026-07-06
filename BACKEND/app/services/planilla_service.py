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
from app.models.empleado_planilla_config import EmpleadoPlanillaConfig
from app.models.planilla import (
    ConceptoRemunerativo, Planilla, BoletaPago, BoletaPagoDetalle, EmpleadoConcepto,
)
from app.services import contabilizacion_service as contab
from app.services.planilla_asistencia_service import resumen_horas_periodo
from app.services.planilla_calculo_service import InsumoEmpleado, calcular_boleta_empleado
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")

# Conceptos de descuento auto-generados desde la asistencia (Fase 2).
COD_DESC_FALTA    = "DESC_FALTA"
COD_DESC_TARDANZA = "DESC_TARDANZA"

# Código del concepto que representa el Sueldo Base (es_base=true). El monto
# por empleado vive en EmpleadoConcepto — ver PUT /planilla/empleados/{id}/sueldo-base.
COD_SUELDO_BASE = "SUELDO_BASE"

# Catálogo estándar del motor de cálculo legal (Fase 8). Cada tupla:
# (codigo, nombre, tipo, es_base). Se siembra una sola vez por empresa
# (idempotente por UniqueConstraint(empresa_id, codigo)) — el motor de
# cálculo (planilla_calculo_service, Fase 2) escribe sus BoletaPagoDetalle
# usando estos códigos.
CATALOGO_ESTANDAR: list[tuple[str, str, str, bool]] = [
    (COD_SUELDO_BASE,   "Remuneración Básica",                   "ingreso",          True),
    ("HRS_EXTRA",       "Trabajo en Sobretiempo",                 "ingreso",          False),
    ("ASIG_FAMILIAR",   "Asignación Familiar",                    "ingreso",          False),
    (COD_DESC_FALTA,    "Descuento por falta",                    "descuento",        False),
    ("DESC_DOMINICAL",  "Descuento dominical (D.S. 001-96-TR)",   "descuento",        False),
    (COD_DESC_TARDANZA, "Descuento por tardanza",                 "descuento",        False),
    ("PENSION_ONP",     "Aporte ONP (13%)",                        "descuento",        False),
    ("AFP_APORTE",      "AFP - Aporte Obligatorio",                "descuento",        False),
    ("AFP_PRIMA",       "AFP - Prima de Seguro",                   "descuento",        False),
    ("AFP_COMISION",    "AFP - Comisión",                          "descuento",        False),
    ("RENTA_5TA",       "Retención Renta de 5ta Categoría",        "descuento",        False),
    ("ESSALUD",         "Aporte EsSalud (empleador)",              "aporte_empleador", False),
]


def _get_or_create_concepto(
    db: Session, empresa_id: str, codigo: str, nombre: str, tipo: str, *, es_base: bool = False,
) -> ConceptoRemunerativo:
    """Como `_get_or_create_descuento` pero genérico (cualquier tipo, con
    es_base) — usado por `asegurar_catalogo_estandar` y por el endpoint de
    Sueldo Base. Idempotente por (empresa_id, codigo). No modifica un
    concepto ya existente (si la empresa lo editó — p. ej. renombró — se
    respeta su versión)."""
    c = (
        db.query(ConceptoRemunerativo)
        .filter(ConceptoRemunerativo.empresa_id == empresa_id,
                ConceptoRemunerativo.codigo == codigo)
        .first()
    )
    if c is None:
        c = ConceptoRemunerativo(
            empresa_id=empresa_id, codigo=codigo, nombre=nombre, tipo=tipo,
            monto_referencial=None, activo="true",
            es_base="true" if es_base else "false",
        )
        db.add(c)
        db.flush()
    return c


def asegurar_catalogo_estandar(db: Session, empresa_id: str) -> list[ConceptoRemunerativo]:
    """Siembra el catálogo estándar de conceptos legales (Sueldo Base, Horas
    Extra, Asignación Familiar, descuentos por asistencia, ONP/AFP
    desglosado, Renta 5ta, EsSalud) para la empresa, si aún no existen.
    Idempotente — puede llamarse tantas veces como se quiera."""
    creados = []
    for codigo, nombre, tipo, es_base in CATALOGO_ESTANDAR:
        creados.append(_get_or_create_concepto(db, empresa_id, codigo, nombre, tipo, es_base=es_base))
    db.commit()
    for c in creados:
        db.refresh(c)
    return creados

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


# Códigos reservados del motor legal (Fase 8): se mapean 1:1 desde el
# DesgloseBoleta, nunca se recorren con el mecanismo genérico de
# monto_referencial/override (evita que, p. ej., "Descuento por falta" se
# aplique como monto fijo a todos — esos códigos quedan reservados para
# ajustes manuales puntuales vía editar_boleta_detalle).
_CODIGOS_MOTOR_LEGAL = frozenset({
    COD_SUELDO_BASE, "HRS_EXTRA", "ASIG_FAMILIAR",
    "PENSION_ONP", "AFP_APORTE", "AFP_PRIMA", "AFP_COMISION",
    "RENTA_5TA", "ESSALUD",
    COD_DESC_FALTA, "DESC_DOMINICAL", COD_DESC_TARDANZA,
})


# ── Calcular (sin contabilizar) ──────────────────────────────────────────────
def calcular_planilla(db: Session, empresa_id: str, periodo_id: str) -> Planilla:
    """Genera la planilla del periodo en estado 'calculada'. El motor legal
    (planilla_calculo_service) calcula ONP/AFP/horas extra/asignación
    familiar/renta 5ta de cada empleado dependiente a partir de su asistencia
    real (resumen_horas_periodo) y su sueldo base (EmpleadoConcepto
    SUELDO_BASE); el sueldo devengado ya sale proporcional a lo asistido (ver
    planilla_calculo_service — 0% de asistencia ⇒ 0 de sueldo). Cualquier
    concepto ADICIONAL configurado manualmente (ajeno al motor legal, p. ej.
    un bono) se sigue aplicando con el mecanismo genérico original
    (monto_referencial u override por empleado). No contabiliza todavía (eso
    es aprobar_planilla)."""
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
    for p_anulada in anuladas:
        boletas_ids = [b.id for b in db.query(BoletaPago).filter(
            BoletaPago.planilla_id == p_anulada.id).all()]
        if boletas_ids:
            db.query(BoletaPagoDetalle).filter(
                BoletaPagoDetalle.boleta_id.in_(boletas_ids)).delete(synchronize_session=False)
            db.query(BoletaPago).filter(
                BoletaPago.planilla_id == p_anulada.id).delete(synchronize_session=False)
        db.delete(p_anulada)
    db.flush()

    empleados = db.query(Empleado).filter(
        Empleado.empresa_id == empresa_id, Empleado.activo.is_(True)).all()
    if not empleados:
        raise HTTPException(status_code=422, detail="No hay empleados activos para procesar.")

    # Catálogo estándar del motor legal, siempre presente (idempotente).
    asegurar_catalogo_estandar(db, empresa_id)
    conceptos = (
        db.query(ConceptoRemunerativo)
        .filter(ConceptoRemunerativo.empresa_id == empresa_id, ConceptoRemunerativo.activo == "true")
        .all()
    )
    conceptos_por_codigo = {c.codigo: c for c in conceptos}
    conceptos_extra = [c for c in conceptos if c.codigo not in _CODIGOS_MOTOR_LEGAL]

    # Montos asignados por empleado (sueldo base + cualquier concepto extra).
    overrides = {
        (a.empleado_id, a.concepto_id): a.monto
        for a in db.query(EmpleadoConcepto).filter(
            EmpleadoConcepto.empresa_id == empresa_id).all()
    }
    config_por_emp = {
        str(c.empleado_id): c
        for c in db.query(EmpleadoPlanillaConfig).filter(
            EmpleadoPlanillaConfig.empresa_id == empresa_id).all()
    }

    empresa = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    regimen_empresa = getattr(empresa, "regimen_laboral", None) or "micro"
    descuento_tardanza_auto = bool(getattr(empresa, "descuento_tardanza_auto", True)) if empresa else True

    inicio_p = date(periodo.anio, periodo.mes, 1)
    fin_p = date(periodo.anio, periodo.mes, _cal.monthrange(periodo.anio, periodo.mes)[1])
    filas_asistencia = {
        str(f["id"]): f for f in resumen_horas_periodo(db, empresa_id, inicio_p, fin_p)
    }

    concepto_sueldo_base = conceptos_por_codigo.get(COD_SUELDO_BASE)

    planilla = Planilla(
        empresa_id=empresa_id, periodo_id=periodo_id, fecha_proceso=date.today(),
        estado="calculada", total_ingresos=CERO, total_descuentos=CERO,
        total_aportes=CERO, total_neto=CERO,
    )
    db.add(planilla)
    db.flush()

    for emp in empleados:
        emp_id = str(emp.id)
        fila_asist = filas_asistencia.get(emp_id)
        if fila_asist is None:
            continue  # sin registro de asistencia para el período (p.ej. alta posterior)

        cfg = config_por_emp.get(emp_id)
        sueldo_base = CERO
        if concepto_sueldo_base is not None:
            monto_asignado = overrides.get((emp.id, concepto_sueldo_base.id))
            sueldo_base = _d(
                monto_asignado if monto_asignado is not None else concepto_sueldo_base.monto_referencial
            )

        insumo = InsumoEmpleado(
            empleado_id=emp_id, tipo_contrato=emp.tipo, sueldo_base=sueldo_base,
            horas_reales=Decimal(str(fila_asist["horas_reales"])),
            horas_faltantes=Decimal(str(fila_asist["horas_faltantes"])),
            meta_horas=Decimal(str(fila_asist["meta_horas"])),
            sistema_pension=(cfg.sistema_pension if cfg else "onp"),
            entidad_afp=(cfg.entidad_afp if cfg else None),
            comision_afp_personalizada=(cfg.comision_afp_personalizada if cfg else None),
            tiene_asignacion_familiar=(bool(cfg.tiene_asignacion_familiar) if cfg else False),
        )
        desglose = calcular_boleta_empleado(
            insumo, regimen_empresa=regimen_empresa, periodo_pago="mes",
            descuento_tardanza_auto=descuento_tardanza_auto,
        )

        detalles: list[tuple[str, Decimal]] = []

        def _agregar(codigo: str, monto) -> None:
            monto = _d(monto)
            if monto <= CERO:
                return
            concepto = conceptos_por_codigo.get(codigo)
            if concepto is None:
                return
            detalles.append((concepto.id, monto))

        _agregar(COD_SUELDO_BASE, desglose.sueldo_devengado)
        _agregar("HRS_EXTRA", desglose.pago_horas_extra)
        _agregar("ASIG_FAMILIAR", desglose.asignacion_familiar)
        if insumo.sistema_pension == "onp":
            _agregar("PENSION_ONP", desglose.descuento_pension)
        else:
            _agregar("AFP_APORTE", desglose.afp_aporte_obligatorio)
            _agregar("AFP_PRIMA", desglose.afp_prima_seguro)
            _agregar("AFP_COMISION", desglose.afp_comision)
        _agregar("RENTA_5TA", desglose.renta_5ta)
        _agregar("ESSALUD", desglose.aporte_essalud)

        # Conceptos EXTRA configurados manualmente (fuera del motor legal):
        # mismo mecanismo genérico original (override por empleado o
        # monto_referencial del catálogo).
        for c in conceptos_extra:
            asignado = overrides.get((emp.id, c.id))
            monto = _d(asignado if asignado is not None else c.monto_referencial)
            if monto > CERO:
                detalles.append((c.id, monto))

        if not detalles:
            continue

        boleta = BoletaPago(
            planilla_id=planilla.id, empleado_id=emp.id,
            total_ingresos=CERO, total_descuentos=CERO, total_aportes=CERO, total_neto=CERO,
            total_cts=_d(desglose.provision_cts), total_gratificacion=_d(desglose.provision_gratificacion),
            total_vacaciones=_d(desglose.provision_vacaciones),
        )
        db.add(boleta)
        db.flush()
        for concepto_id, monto in detalles:
            db.add(BoletaPagoDetalle(boleta_id=boleta.id, concepto_id=concepto_id, monto=monto))
        db.flush()
        _recompute_boleta(db, boleta)
        # IMPORTANTE: flush inmediato tras mutar boleta.total_*. `boleta` es un
        # objeto RECIÉN CREADO cuyo PK Python es un str (default `_uuid()`),
        # pero la columna real en Postgres es `uuid`; una consulta posterior
        # en la MISMA transacción (p. ej. `_recompute_planilla`) recibe ese PK
        # de vuelta como `uuid.UUID` (tipo distinto, distinto hash), por lo
        # que el identity map de SQLAlchemy NO reconoce el objeto y construye
        # una instancia nueva cargada desde BD — perdiendo silenciosamente
        # cualquier atributo mutado en memoria que no se haya flusheado ya
        # (visto y confirmado en pruebas: sin este flush, total_ingresos de
        # toda la planilla salía en 0 aunque cada boleta individual quedara
        # bien calculada). El flush aquí garantiza que la query posterior lea
        # el valor correcto sin depender de la deduplicación del identity map.
        db.flush()

    _recompute_planilla(db, planilla)
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
    # Piso de seguridad: el neto de una boleta NUNCA debe ser negativo, sin
    # importar qué combinación de conceptos lo produzca (ej. una retención
    # calculada sobre una base que luego resultó reducida a 0 por asistencia,
    # o un descuento manual mal configurado vía editar_boleta_detalle). Un
    # pago negativo no tiene sentido en una boleta real.
    boleta.total_neto = max(CERO, ing - desc)


def _recompute_planilla(db: Session, planilla: Planilla) -> None:
    """Recalcula los totales de la planilla desde sus boletas."""
    bs = db.query(BoletaPago).filter(BoletaPago.planilla_id == planilla.id).all()
    planilla.total_ingresos = sum((_d(b.total_ingresos) for b in bs), CERO)
    planilla.total_descuentos = sum((_d(b.total_descuentos) for b in bs), CERO)
    planilla.total_aportes = sum((_d(b.total_aportes) for b in bs), CERO)
    # Mismo piso de seguridad a nivel planilla (suma de netos ya no-negativos
    # de boleta; se recalcula aquí también por si total_ingresos/descuentos
    # llegaran desbalanceados desde otra vía).
    planilla.total_neto = max(CERO, planilla.total_ingresos - planilla.total_descuentos)


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
