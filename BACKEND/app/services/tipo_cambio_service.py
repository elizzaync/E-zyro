"""
Tipo de cambio y multimoneda (feature opcional por empresa).

- `multimoneda_activa`: flag en la configuración contable de la empresa.
- `obtener_venta`: TC venta vigente para una fecha (exacta o la última
  publicada hasta 7 días antes — SUNAT no publica fines de semana/feriados).
- `fetch_tc_hoy`: trae el TC del día desde la API configurada (mismo token
  APIS_NET_PE_TOKEN de consultas: decolecta si empieza con sk_, apis.net.pe
  si no) y lo persiste. Lo invoca el scheduler cada mañana.
- Diferencia de cambio: cuentas PCGE 776 (ganancia) / 676 (pérdida),
  configurables en la configuración contable.
"""
from __future__ import annotations

import os
from datetime import date, timedelta
from decimal import Decimal

import requests
from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.tipo_cambio import TipoCambio

_TIMEOUT = 10


def multimoneda_activa(db: Session, empresa_id: str) -> bool:
    from app.services.cierre_ejercicio_service import obtener_config
    cfg = obtener_config(db, empresa_id)
    return bool(getattr(cfg, "multimoneda", False))


def cuentas_diferencia_cambio(db: Session, empresa_id: str) -> tuple[str, str]:
    """(codigo_ganancia, codigo_perdida) — PCGE 776 / 676 por defecto."""
    from app.services.cierre_ejercicio_service import obtener_config
    cfg = obtener_config(db, empresa_id)
    return (getattr(cfg, "cuenta_ganancia_cambio_codigo", None) or "776",
            getattr(cfg, "cuenta_perdida_cambio_codigo", None) or "676")


def obtener_venta(db: Session, fecha: date, moneda: str = "USD") -> Decimal:
    """TC venta vigente en `fecha` (o el último publicado hasta 7 días antes)."""
    tc = (
        db.query(TipoCambio)
        .filter(TipoCambio.moneda == moneda,
                TipoCambio.fecha <= fecha,
                TipoCambio.fecha >= fecha - timedelta(days=7))
        .order_by(TipoCambio.fecha.desc())
        .first()
    )
    if tc is None:
        raise HTTPException(
            status_code=422,
            detail=f"No hay tipo de cambio {moneda} para {fecha.isoformat()}. "
                   "Actualízalo desde Finanzas → Configuración o registra uno manual.",
        )
    return Decimal(str(tc.venta))


def registrar(db: Session, fecha: date, venta, compra=None,
              moneda: str = "USD", fuente: str = "manual") -> TipoCambio:
    """Upsert del TC de una fecha (idempotente)."""
    tc = db.query(TipoCambio).filter(
        TipoCambio.fecha == fecha, TipoCambio.moneda == moneda).first()
    if tc is None:
        tc = TipoCambio(fecha=fecha, moneda=moneda)
        db.add(tc)
    tc.venta = Decimal(str(venta))
    tc.compra = Decimal(str(compra)) if compra is not None else tc.compra
    tc.fuente = fuente
    db.commit()
    db.refresh(tc)
    return tc


def fetch_tc_hoy(db: Session) -> TipoCambio | None:
    """Trae el TC SUNAT del día desde la API externa y lo guarda. None si falla."""
    token = os.getenv("APIS_NET_PE_TOKEN", "").strip().strip('"').strip("'")
    if not token:
        return None
    if token.startswith("sk_"):
        url = "https://api.decolecta.com/v1/tipo-cambio/sunat"
    else:
        url = "https://api.apis.net.pe/v2/sunat/tipo-cambio"
    try:
        r = requests.get(url, headers={"Authorization": f"Bearer {token}"},
                         timeout=_TIMEOUT)
        if r.status_code != 200:
            return None
        d = r.json()
    except (requests.RequestException, ValueError):
        return None

    def g(*claves):
        for k in claves:
            if d.get(k) is not None:
                return d[k]
        return None

    venta = g("venta", "sell_price", "precioVenta")
    compra = g("compra", "buy_price", "precioCompra")
    if venta is None:
        return None
    return registrar(db, date.today(), venta, compra, fuente="SUNAT")
