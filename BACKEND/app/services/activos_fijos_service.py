"""
Servicio de activos fijos y depreciación (Fase 7) — método de línea recta.

`procesar_depreciacion_periodo` es idempotente: la UNIQUE(activo, periodo) de
`depreciacion_mensual` y la verificación previa garantizan que ejecutar dos
veces el mismo periodo NO duplica asientos. Nunca deprecia por debajo del valor
residual ni en periodos cerrados.

Mapeo contable: Db 6814 Depreciación (gasto) / Cr 391 Depreciación acumulada.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable, PeriodoContable
from app.models.activos_fijos import ActivoFijo, DepreciacionMensual
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")

CTA_GASTO_DEPREC = "6814"  # Depreciación de inmuebles, maquinaria y equipo - costo
CTA_DEPREC_ACUM  = "391"   # Depreciación acumulada


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


def calcular_depreciacion_mensual(activo: ActivoFijo) -> Decimal:
    """Cuota lineal mensual = (valor_adquisicion − valor_residual) / vida_util_meses."""
    base = _d(activo.valor_adquisicion) - _d(activo.valor_residual)
    if base <= CERO or not activo.vida_util_meses:
        return CERO
    return (base / Decimal(activo.vida_util_meses)).quantize(Q2)


def depreciacion_acumulada(db: Session, activo_fijo_id: str) -> Decimal:
    total = (
        db.query(func.coalesce(func.sum(DepreciacionMensual.monto_depreciado), 0))
        .filter(DepreciacionMensual.activo_fijo_id == activo_fijo_id)
        .scalar()
    ) or 0
    return _d(total)


def valor_en_libros(db: Session, activo: ActivoFijo) -> Decimal:
    return _d(activo.valor_adquisicion) - depreciacion_acumulada(db, activo.id)


def procesar_depreciacion_periodo(db: Session, empresa_id: str, periodo_id: str,
                                  creado_por_id: str | None = None) -> dict:
    """Procesa la depreciación de todos los activos 'activo' de la empresa para el
    periodo. Idempotente. Devuelve un resumen {procesados, omitidos, total_depreciado}."""
    periodo = (
        db.query(PeriodoContable)
        .filter(PeriodoContable.id == periodo_id, PeriodoContable.empresa_id == empresa_id)
        .first()
    )
    if periodo is None:
        raise HTTPException(status_code=404, detail="Periodo no encontrado.")
    if periodo.estado != "abierto":
        raise HTTPException(status_code=409, detail="El periodo está cerrado; no se puede depreciar.")

    fecha_asiento = date(periodo.anio, periodo.mes, 1)
    activos = (
        db.query(ActivoFijo)
        .filter(ActivoFijo.empresa_id == empresa_id, ActivoFijo.estado == "activo")
        .all()
    )

    procesados = 0
    omitidos = 0
    total_depreciado = CERO

    for activo in activos:
        # Guard de idempotencia explícito (además de la UNIQUE)
        ya = (
            db.query(DepreciacionMensual)
            .filter(DepreciacionMensual.activo_fijo_id == activo.id,
                    DepreciacionMensual.periodo_id == periodo_id)
            .first()
        )
        if ya:
            omitidos += 1
            continue

        # La depreciación no empieza antes de su fecha de inicio
        if activo.fecha_inicio_depreciacion > date(periodo.anio, periodo.mes,
                                                   _ultimo_dia(periodo.anio, periodo.mes)):
            omitidos += 1
            continue

        cuota = calcular_depreciacion_mensual(activo)
        libros = valor_en_libros(db, activo)
        depreciable_restante = libros - _d(activo.valor_residual)
        if depreciable_restante <= CERO:
            activo.estado = "depreciado_total"
            omitidos += 1
            continue
        # Nunca depreciar por debajo del valor residual (última cuota se ajusta)
        monto = min(cuota, depreciable_restante)
        if monto <= CERO:
            omitidos += 1
            continue

        libros_resultante = libros - monto

        lineas = [
            LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_GASTO_DEPREC).id, debito=monto,
                         centro_costo_id=(str(activo.centro_costo_id) if activo.centro_costo_id else None)),
            LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_DEPREC_ACUM).id, credito=monto),
        ]
        try:
            asiento = contab.registrar_asiento(
                db, empresa_id=empresa_id, fecha=fecha_asiento,
                descripcion=f"Depreciación {activo.nombre} {periodo.anio}-{periodo.mes:02d}",
                origen="depreciacion", lineas=lineas, referencia_id=activo.id,
                creado_por_id=creado_por_id, commit=False,
            )
            db.add(DepreciacionMensual(
                activo_fijo_id=activo.id, periodo_id=periodo_id, monto_depreciado=monto,
                valor_en_libros_resultante=libros_resultante, asiento_id=asiento.id,
            ))
            if libros_resultante <= _d(activo.valor_residual):
                activo.estado = "depreciado_total"
            db.commit()
            procesados += 1
            total_depreciado += monto
        except HTTPException:
            db.rollback()
            raise
        except Exception as exc:
            db.rollback()
            raise HTTPException(status_code=422, detail=f"Error al depreciar {activo.nombre}: {exc}") from exc

    return {"procesados": procesados, "omitidos": omitidos, "total_depreciado": total_depreciado}


def _ultimo_dia(anio: int, mes: int) -> int:
    import calendar
    return calendar.monthrange(anio, mes)[1]
