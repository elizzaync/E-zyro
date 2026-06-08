"""
Servicio de controlling / centros de costo (Fase 2).

SOLO LECTURA sobre el libro mayor: agrega las líneas de asiento imputadas a
un centro de costo. NUNCA genera ni modifica asientos — no importa
`registrar_asiento` a propósito (la imputación la pone el módulo de origen al
crear el asiento en la Fase 1; aquí solo se consulta).

Todos los montos en Decimal.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import AsientoContable, AsientoLinea, CentroCosto

CERO = Decimal("0.00")


def _d(valor) -> Decimal:
    return Decimal(str(valor if valor is not None else 0)).quantize(Decimal("0.01"))


def costo_real_por_centro(
    db: Session, empresa_id: str, centro_costo_id: str,
    periodo_desde: date | None = None, periodo_hasta: date | None = None,
) -> dict:
    """Agrega débitos y créditos de todas las líneas imputadas a un centro.

    `costo_real` = SUM(debito) - SUM(credito): para un centro que acumula
    gastos (lo habitual) el resultado es positivo y representa el costo neto
    cargado al centro en el rango de fechas.
    """
    q = (
        db.query(
            func.coalesce(func.sum(AsientoLinea.debito), 0),
            func.coalesce(func.sum(AsientoLinea.credito), 0),
        )
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(
            AsientoContable.empresa_id == empresa_id,
            AsientoLinea.centro_costo_id == centro_costo_id,
        )
    )
    if periodo_desde:
        q = q.filter(AsientoContable.fecha >= periodo_desde)
    if periodo_hasta:
        q = q.filter(AsientoContable.fecha <= periodo_hasta)
    deb, cre = q.first()
    deb, cre = _d(deb), _d(cre)
    return {
        "centro_costo_id": centro_costo_id,
        "total_debito": deb,
        "total_credito": cre,
        "costo_real": deb - cre,
    }


def comparativo_presupuesto_vs_real(
    db: Session, empresa_id: str, centro_costo_id: str,
    periodo_desde: date | None = None, periodo_hasta: date | None = None,
) -> dict:
    """Cruza el presupuesto referencial del centro contra su costo real."""
    cc = (
        db.query(CentroCosto)
        .filter(CentroCosto.id == centro_costo_id, CentroCosto.empresa_id == empresa_id)
        .first()
    )
    if cc is None:
        return {}
    real = costo_real_por_centro(db, empresa_id, centro_costo_id, periodo_desde, periodo_hasta)
    presupuesto = _d(cc.presupuesto_referencial) if cc.presupuesto_referencial is not None else None
    costo_real = real["costo_real"]
    desviacion = (costo_real - presupuesto) if presupuesto is not None else None
    return {
        "centro_costo_id": centro_costo_id,
        "codigo": cc.codigo,
        "nombre": cc.nombre,
        "presupuesto_referencial": presupuesto,
        "costo_real": costo_real,
        "desviacion": desviacion,  # >0: sobre-ejecutado; <0: bajo presupuesto
        "ejecucion_pct": (
            (costo_real / presupuesto * Decimal("100")).quantize(Decimal("0.01"))
            if presupuesto and presupuesto != CERO else None
        ),
    }
