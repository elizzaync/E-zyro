"""Saldos iniciales / asiento de apertura (Fase 11).

Cuando una empresa adopta el ERP a mitad de su vida, sus saldos reales (caja,
bancos, deudas, inventario, activos, capital) deben entrar al libro mayor UNA
vez, como asiento de apertura — si no, la contabilidad solo es correcta para
empresas que nacen dentro del sistema.

Diseño para usuario no contable:
  - Recibe [(cuenta_codigo, monto)] con montos POSITIVOS; el lado Db/Cr se
    deriva de la naturaleza de la cuenta (deudora→débito, acreedora→crédito).
  - Solo cuentas de BALANCE (activo/pasivo/patrimonio): ingresos y gastos
    empiezan siempre en cero.
  - La diferencia se completa automáticamente contra capital (501) — es el
    "plug" clásico de apertura; se devuelve explícito para mostrarlo en la app.
  - Una sola apertura vigente por empresa; se deshace con asiento espejo
    (origen `apertura`, neto cero), nunca borrando.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import (
    CuentaContable, PeriodoContable, AsientoContable, AsientoLinea,
)
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")
ORIGEN_APERTURA = "apertura"
CTA_CAPITAL = "501"


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


def _neto_apertura(db: Session, empresa_id: str) -> dict[str, Decimal]:
    """Neto (débito − crédito) por cuenta de los asientos de apertura. Vacío si
    nunca se cargó o si la apertura fue revertida (todo neteado a cero)."""
    filas = (
        db.query(AsientoLinea.cuenta_id,
                 func.coalesce(func.sum(AsientoLinea.debito), 0),
                 func.coalesce(func.sum(AsientoLinea.credito), 0))
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.origen == ORIGEN_APERTURA)
        .group_by(AsientoLinea.cuenta_id)
        .all()
    )
    return {str(cid): _d(td) - _d(tc) for cid, td, tc in filas
            if _d(td) - _d(tc) != CERO}


def estado_apertura(db: Session, empresa_id: str) -> dict:
    neto = _neto_apertura(db, empresa_id)
    asiento = (
        db.query(AsientoContable)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.origen == ORIGEN_APERTURA)
        .order_by(AsientoContable.created_at)
        .first()
    )
    return {
        "cargada": bool(neto),
        "fecha": asiento.fecha if asiento else None,
        "asiento_numero": asiento.numero if asiento else None,
    }


def cargar_apertura(db: Session, empresa_id: str, fecha: date,
                    lineas: list[dict], creado_por_id: str | None = None) -> dict:
    """Crea el asiento de apertura desde los saldos capturados."""
    if _neto_apertura(db, empresa_id):
        raise HTTPException(
            status_code=409,
            detail="Los saldos iniciales ya fueron cargados. Reviértalos para volver a cargarlos.")
    if not lineas:
        raise HTTPException(status_code=422, detail="Ingrese al menos un saldo inicial.")

    total_db = total_cr = CERO
    lineas_asiento: list[LineaAsiento] = []
    vistos: set[str] = set()
    for ln in lineas:
        codigo = str(ln.get("cuenta_codigo") or "").strip()
        monto = _d(ln.get("monto"))
        if monto <= CERO:
            continue  # campos en cero del formulario: se ignoran
        if codigo in vistos:
            raise HTTPException(status_code=422, detail=f"La cuenta {codigo} está repetida.")
        vistos.add(codigo)
        cuenta = (
            db.query(CuentaContable)
            .filter(CuentaContable.empresa_id == empresa_id,
                    CuentaContable.codigo == codigo)
            .first()
        )
        if cuenta is None or cuenta.nivel != "detalle" or not cuenta.activo:
            raise HTTPException(
                status_code=422,
                detail=f"La cuenta {codigo} no existe como cuenta de detalle activa.")
        if cuenta.tipo not in ("activo", "pasivo", "patrimonio"):
            raise HTTPException(
                status_code=422,
                detail=f"La cuenta {codigo} es de {cuenta.tipo}: los saldos iniciales "
                       "solo llevan cuentas de balance (activo/pasivo/patrimonio).")
        if cuenta.naturaleza == "deudora":
            lineas_asiento.append(LineaAsiento(cuenta_id=str(cuenta.id), debito=monto,
                                               glosa="Saldo inicial"))
            total_db += monto
        else:
            lineas_asiento.append(LineaAsiento(cuenta_id=str(cuenta.id), credito=monto,
                                               glosa="Saldo inicial"))
            total_cr += monto

    if not lineas_asiento:
        raise HTTPException(status_code=422, detail="Todos los montos están en cero.")

    # Diferencia → capital (501): completa la ecuación Activo = Pasivo + Patrimonio.
    diferencia = (total_db - total_cr).quantize(Q2)
    if diferencia != CERO:
        capital = (
            db.query(CuentaContable)
            .filter(CuentaContable.empresa_id == empresa_id,
                    CuentaContable.codigo == CTA_CAPITAL)
            .first()
        )
        if capital is None or capital.nivel != "detalle":
            raise HTTPException(
                status_code=422,
                detail=f"No hay cuenta {CTA_CAPITAL} (capital) para cuadrar la diferencia.")
        if diferencia > CERO:
            lineas_asiento.append(LineaAsiento(cuenta_id=str(capital.id), credito=diferencia,
                                               glosa="Diferencia de apertura contra capital"))
        else:
            lineas_asiento.append(LineaAsiento(cuenta_id=str(capital.id), debito=-diferencia,
                                               glosa="Diferencia de apertura contra capital"))

    # Periodo del mes de la fecha: se crea abierto si no existe.
    periodo = (
        db.query(PeriodoContable)
        .filter(PeriodoContable.empresa_id == empresa_id,
                PeriodoContable.anio == fecha.year,
                PeriodoContable.mes == fecha.month)
        .first()
    )
    if periodo is None:
        db.add(PeriodoContable(empresa_id=empresa_id, anio=fecha.year,
                               mes=fecha.month, estado="abierto"))
        db.flush()

    asiento = contab.registrar_asiento(
        db, empresa_id, fecha,
        "Asiento de apertura — saldos iniciales",
        ORIGEN_APERTURA, lineas_asiento, creado_por_id=creado_por_id, commit=False,
    )
    db.commit()
    return {
        "asiento_numero": asiento.numero,
        "fecha": fecha,
        "total_debe": (total_db if diferencia <= CERO else total_db).quantize(Q2),
        "ajuste_capital": diferencia,
    }


def revertir_apertura(db: Session, empresa_id: str,
                      creado_por_id: str | None = None) -> dict:
    """Deshace la apertura con un asiento espejo (mismo origen, neto cero)."""
    neto = _neto_apertura(db, empresa_id)
    if not neto:
        raise HTTPException(status_code=409, detail="No hay saldos iniciales cargados.")
    asiento_orig = (
        db.query(AsientoContable)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.origen == ORIGEN_APERTURA)
        .order_by(AsientoContable.created_at)
        .first()
    )
    lineas = []
    for cuenta_id, n in neto.items():
        if n > CERO:
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, credito=n,
                                       glosa="Reversión de apertura"))
        else:
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, debito=-n,
                                       glosa="Reversión de apertura"))
    asiento = contab.registrar_asiento(
        db, empresa_id, asiento_orig.fecha,
        "Reversión del asiento de apertura",
        ORIGEN_APERTURA, lineas, creado_por_id=creado_por_id, commit=False,
    )
    db.commit()
    return {"asiento_numero": asiento.numero}
