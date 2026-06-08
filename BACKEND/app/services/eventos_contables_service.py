"""
Servicio del bus de eventos contables (Fase 10).

`emitir_evento_contable` traduce un hecho económico a su asiento según la
plantilla configurada en `mapeo_transaccion_contable`, de forma síncrona y
atómica. Graceful degradation: si no hay mapeo para el tipo de evento, NO rompe
el flujo operativo — registra el evento como 'sin_mapeo' y retorna None.

Decisión de arquitectura (documentada en el plan 11): las Fases 3-9 usan el
patrón directo (cada servicio arma sus líneas y llama a registrar_asiento). Este
bus es la alternativa configurable disponible para nuevos módulos o para
migrar conectores uno a uno sin cambiar los asientos generados.
"""
from __future__ import annotations

import json
from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable
from app.models.eventos_contables import MapeoTransaccionContable, EventoContableHistorial
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Decimal("0.01"))


def _cuenta_id(db: Session, empresa_id: str, codigo: str) -> str:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == codigo)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422, detail=f"La cuenta {codigo} del mapeo no existe en el plan.")
    return c.id


def _registrar_historial(db: Session, empresa_id, tipo_evento, referencia_id,
                         asiento_id, resultado, detalle):
    db.add(EventoContableHistorial(
        empresa_id=empresa_id, tipo_evento=tipo_evento, referencia_id=referencia_id,
        asiento_id=asiento_id, resultado=resultado, detalle=detalle))


def emitir_evento_contable(
    db: Session, empresa_id: str, tipo_evento: str, datos_origen: dict,
    referencia_id: str | None = None, fecha: date | None = None,
    creado_por_id: str | None = None, commit: bool = True,
):
    """Genera el asiento mapeado para `tipo_evento`. Retorna el asiento o None
    (sin mapeo). Lanza HTTPException solo ante datos/cuentas inválidos."""
    fecha = fecha or date.today()
    mapeo = (
        db.query(MapeoTransaccionContable)
        .filter(MapeoTransaccionContable.empresa_id == empresa_id,
                MapeoTransaccionContable.tipo_evento == tipo_evento,
                MapeoTransaccionContable.activo.is_(True))
        .first()
    )
    if mapeo is None:
        _registrar_historial(db, empresa_id, tipo_evento, referencia_id, None,
                             "sin_mapeo", "No hay mapeo configurado para el evento.")
        if commit:
            db.commit()
        return None

    try:
        plantilla = json.loads(mapeo.plantilla_lineas or "[]")
    except json.JSONDecodeError:
        raise HTTPException(status_code=422, detail="La plantilla del mapeo no es JSON válido.")

    lineas: list[LineaAsiento] = []
    for regla in plantilla:
        campo = regla.get("origen_monto")
        monto = _d(datos_origen.get(campo)) if campo else CERO
        if monto <= CERO:
            continue
        cuenta_id = _cuenta_id(db, empresa_id, regla["cuenta_codigo"])
        if regla.get("tipo") == "debito":
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, debito=monto))
        else:
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, credito=monto))

    if not lineas:
        _registrar_historial(db, empresa_id, tipo_evento, referencia_id, None,
                             "sin_mapeo", "El mapeo no produjo líneas (montos en cero).")
        if commit:
            db.commit()
        return None

    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha,
            descripcion=mapeo.descripcion or f"Evento contable: {tipo_evento}",
            origen=tipo_evento, lineas=lineas, referencia_id=referencia_id,
            creado_por_id=creado_por_id, commit=False,
        )
        _registrar_historial(db, empresa_id, tipo_evento, referencia_id, asiento.id,
                             "generado", None)
        if commit:
            db.commit()
            db.refresh(asiento)
        return asiento
    except HTTPException:
        db.rollback()
        _registrar_historial(db, empresa_id, tipo_evento, referencia_id, None, "error",
                             "Fallo al registrar el asiento del evento.")
        db.commit()
        raise
