"""Cierre de ejercicio anual (Fase 11 — cierre de resultados).

Al 31/12 cancela todas las cuentas de resultados (elementos 6 y 7) contra la
cuenta puente del elemento 8 (891 por defecto) y traslada el neto a patrimonio
(591 utilidades / 592 pérdidas). Dos asientos con origen `cierre_ejercicio`,
generados — nunca digitados — desde los saldos reales del libro mayor.

Decisiones de diseño:
  - NO se genera asiento de apertura: el libro mayor de este sistema es
    continuo (los reportes acumulan saldos desde el origen), así que las
    cuentas de balance arrastran su saldo solas; una "apertura" los duplicaría.
  - El estado de resultados EXCLUYE el origen `cierre_ejercicio` (ver
    reportes_financieros_service): cerrar un año no borra su historia.
  - Revertir el cierre genera el asiento espejo con el MISMO origen, para que
    esa exclusión siga neteando a cero.
  - Las cuentas del cierre (891/591/592) son configuración por empresa
    (ConfiguracionContableEmpresa), nunca código.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import (
    CuentaContable, PeriodoContable, AsientoContable, AsientoLinea,
)
from app.models.configuracion_contable import ConfiguracionContableEmpresa
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")
ORIGEN_CIERRE = "cierre_ejercicio"


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


# ── Configuración contable ───────────────────────────────────────────────────
def obtener_config(db: Session, empresa_id: str) -> ConfiguracionContableEmpresa:
    """Config de la empresa; si no existe se crea con los defaults PCGE."""
    cfg = (
        db.query(ConfiguracionContableEmpresa)
        .filter(ConfiguracionContableEmpresa.empresa_id == empresa_id)
        .first()
    )
    if cfg is None:
        cfg = ConfiguracionContableEmpresa(empresa_id=empresa_id)
        db.add(cfg)
        db.commit()
        db.refresh(cfg)
    return cfg


def actualizar_config(db: Session, empresa_id: str, datos: dict) -> ConfiguracionContableEmpresa:
    """Actualiza las cuentas del cierre validando que existan como detalle activo."""
    cfg = obtener_config(db, empresa_id)
    for campo in ("cuenta_cierre_codigo", "cuenta_utilidad_codigo", "cuenta_perdida_codigo",
                  "cuenta_ganancia_cambio_codigo", "cuenta_perdida_cambio_codigo"):
        codigo = datos.get(campo)
        if codigo:
            _cuenta_detalle(db, empresa_id, codigo)  # valida o lanza 422
            setattr(cfg, campo, codigo)
    if datos.get("multimoneda") is not None:
        cfg.multimoneda = bool(datos["multimoneda"])
    db.commit()
    db.refresh(cfg)
    return cfg


def _cuenta_detalle(db: Session, empresa_id: str, codigo: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id,
                CuentaContable.codigo == codigo)
        .first()
    )
    if c is None or c.nivel != "detalle" or not c.activo:
        raise HTTPException(
            status_code=422,
            detail=f"La cuenta {codigo} no existe como cuenta de detalle activa. "
                   "Revise la Configuración contable.",
        )
    return c


# ── Consultas de estado ──────────────────────────────────────────────────────
def _saldos_resultado(db: Session, empresa_id: str, anio: int) -> list[tuple[str, str, Decimal]]:
    """[(cuenta_id, codigo, neto_deudor)] de cuentas de resultados (6x/7x) con
    movimiento en el año, excluyendo los propios asientos de cierre."""
    filas = (
        db.query(CuentaContable.id, CuentaContable.codigo,
                 func.coalesce(func.sum(AsientoLinea.debito), 0),
                 func.coalesce(func.sum(AsientoLinea.credito), 0))
        .join(AsientoLinea, AsientoLinea.cuenta_id == CuentaContable.id)
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.fecha >= date(anio, 1, 1),
                AsientoContable.fecha <= date(anio, 12, 31),
                AsientoContable.origen != ORIGEN_CIERRE,
                CuentaContable.tipo.in_(("ingreso", "gasto")))
        .group_by(CuentaContable.id, CuentaContable.codigo)
        .all()
    )
    resultado = []
    for cid, codigo, td, tc in filas:
        neto = _d(td) - _d(tc)
        if neto != CERO:
            resultado.append((str(cid), codigo, neto))
    return resultado


def _neto_cierre_por_cuenta(db: Session, empresa_id: str, anio: int) -> dict[str, Decimal]:
    """Neto (débito − crédito) por cuenta de los asientos con origen
    `cierre_ejercicio` del año. Si todos los netos son cero, el ejercicio se
    considera NO cerrado (nunca se cerró, o el cierre fue revertido)."""
    filas = (
        db.query(AsientoLinea.cuenta_id,
                 func.coalesce(func.sum(AsientoLinea.debito), 0),
                 func.coalesce(func.sum(AsientoLinea.credito), 0))
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.origen == ORIGEN_CIERRE,
                AsientoContable.fecha >= date(anio, 1, 1),
                AsientoContable.fecha <= date(anio, 12, 31))
        .group_by(AsientoLinea.cuenta_id)
        .all()
    )
    return {str(cid): _d(td) - _d(tc) for cid, td, tc in filas
            if _d(td) - _d(tc) != CERO}


def esta_cerrado(db: Session, empresa_id: str, anio: int) -> bool:
    return bool(_neto_cierre_por_cuenta(db, empresa_id, anio))


def estado_ejercicio(db: Session, empresa_id: str, anio: int) -> dict:
    """Foto del ejercicio para la pantalla: periodos, preview del resultado y
    si ya puede cerrarse (con el motivo si aún no)."""
    periodos = (
        db.query(PeriodoContable)
        .filter(PeriodoContable.empresa_id == empresa_id,
                PeriodoContable.anio == anio)
        .all()
    )
    estados = {p.mes: p.estado for p in periodos}
    saldos = _saldos_resultado(db, empresa_id, anio)
    ingresos = sum((-n for _, _, n in saldos if n < CERO), CERO)
    gastos = sum((n for _, _, n in saldos if n > CERO), CERO)
    cerrado = esta_cerrado(db, empresa_id, anio)

    abiertos_previos = sorted(m for m, e in estados.items() if e == "abierto" and m < 12)
    motivo = None
    if cerrado:
        motivo = "El ejercicio ya está cerrado."
    elif abiertos_previos:
        motivo = ("Cierre mensual pendiente: " +
                  ", ".join(f"{anio}-{m:02d}" for m in abiertos_previos))
    elif not saldos:
        motivo = "No hay movimientos de ingresos/gastos que cerrar."

    return {
        "anio": anio,
        "cerrado": cerrado,
        "periodos": [{"mes": m, "estado": estados.get(m)} for m in range(1, 13)],
        "resultado_preview": {
            "ingresos": ingresos.quantize(Q2),
            "gastos": gastos.quantize(Q2),
            "resultado": (ingresos - gastos).quantize(Q2),
        },
        "puede_cerrar": motivo is None,
        "motivo": motivo,
    }


# ── Acciones ─────────────────────────────────────────────────────────────────
def cerrar_ejercicio(db: Session, empresa_id: str, anio: int,
                     creado_por_id: str | None = None) -> dict:
    """Genera los asientos de cierre del año y deja diciembre cerrado.

    Exige que enero–noviembre (los periodos que existan) estén cerrados. Si
    diciembre está cerrado se reabre solo dentro de esta transacción para
    postear el cierre, y vuelve a quedar cerrado: el usuario no necesita
    conocer esa mecánica contable.
    """
    if esta_cerrado(db, empresa_id, anio):
        raise HTTPException(status_code=409, detail=f"El ejercicio {anio} ya está cerrado.")

    estado = estado_ejercicio(db, empresa_id, anio)
    if not estado["puede_cerrar"]:
        raise HTTPException(status_code=409, detail=estado["motivo"])

    cfg = obtener_config(db, empresa_id)
    cta_cierre = _cuenta_detalle(db, empresa_id, cfg.cuenta_cierre_codigo)
    cta_utilidad = _cuenta_detalle(db, empresa_id, cfg.cuenta_utilidad_codigo)
    cta_perdida = _cuenta_detalle(db, empresa_id, cfg.cuenta_perdida_codigo)

    # Periodo de diciembre: crear si falta; reabrir en-sesión si está cerrado.
    fecha_cierre = date(anio, 12, 31)
    dic = (
        db.query(PeriodoContable)
        .filter(PeriodoContable.empresa_id == empresa_id,
                PeriodoContable.anio == anio, PeriodoContable.mes == 12)
        .first()
    )
    if dic is None:
        dic = PeriodoContable(empresa_id=empresa_id, anio=anio, mes=12, estado="abierto")
        db.add(dic)
        db.flush()
    elif dic.estado != "abierto":
        dic.estado = "abierto"
        db.flush()

    # Asiento 1: cancelar 6x/7x contra la cuenta puente (891).
    saldos = _saldos_resultado(db, empresa_id, anio)
    lineas: list[LineaAsiento] = []
    for cuenta_id, _codigo, neto in saldos:
        if neto > CERO:      # saldo deudor (gastos): se cancela con crédito
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, credito=neto,
                                       glosa=f"Cierre {anio}"))
        else:                # saldo acreedor (ingresos): se cancela con débito
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, debito=-neto,
                                       glosa=f"Cierre {anio}"))
    ingresos = estado["resultado_preview"]["ingresos"]
    gastos = estado["resultado_preview"]["gastos"]
    resultado = ingresos - gastos
    if resultado > CERO:
        lineas.append(LineaAsiento(cuenta_id=str(cta_cierre.id), credito=resultado,
                                   glosa=f"Resultado del ejercicio {anio}"))
    elif resultado < CERO:
        lineas.append(LineaAsiento(cuenta_id=str(cta_cierre.id), debito=-resultado,
                                   glosa=f"Resultado del ejercicio {anio}"))

    asiento1 = contab.registrar_asiento(
        db, empresa_id, fecha_cierre,
        f"Cierre del ejercicio {anio}: cancelación de ingresos y gastos",
        ORIGEN_CIERRE, lineas, creado_por_id=creado_por_id, commit=False,
    )

    # Asiento 2: trasladar el resultado de la cuenta puente a patrimonio.
    asiento2 = None
    if resultado > CERO:
        lineas2 = [
            LineaAsiento(cuenta_id=str(cta_cierre.id), debito=resultado),
            LineaAsiento(cuenta_id=str(cta_utilidad.id), credito=resultado,
                         glosa=f"Utilidad del ejercicio {anio}"),
        ]
    elif resultado < CERO:
        lineas2 = [
            LineaAsiento(cuenta_id=str(cta_perdida.id), debito=-resultado,
                         glosa=f"Pérdida del ejercicio {anio}"),
            LineaAsiento(cuenta_id=str(cta_cierre.id), credito=-resultado),
        ]
    else:
        lineas2 = None
    if lineas2:
        asiento2 = contab.registrar_asiento(
            db, empresa_id, fecha_cierre,
            f"Cierre del ejercicio {anio}: traslado del resultado a patrimonio",
            ORIGEN_CIERRE, lineas2, creado_por_id=creado_por_id, commit=False,
        )

    # Diciembre queda cerrado junto con el cierre, en la misma transacción.
    dic.estado = "cerrado"
    dic.cerrado_por_id = creado_por_id
    dic.cerrado_at = datetime.utcnow()
    db.commit()

    return {
        "anio": anio,
        "resultado": resultado.quantize(Q2),
        "tipo_resultado": ("utilidad" if resultado > CERO
                           else "perdida" if resultado < CERO else "equilibrio"),
        "asientos": [a.numero for a in (asiento1, asiento2) if a is not None],
    }


def revertir_cierre(db: Session, empresa_id: str, anio: int,
                    creado_por_id: str | None = None) -> dict:
    """Deshace el cierre con UN asiento espejo (mismo origen, neto cero) y deja
    diciembre abierto para corregir y volver a cerrar. Nada se borra."""
    netos = _neto_cierre_por_cuenta(db, empresa_id, anio)
    if not netos:
        raise HTTPException(status_code=409, detail=f"El ejercicio {anio} no está cerrado.")

    dic = (
        db.query(PeriodoContable)
        .filter(PeriodoContable.empresa_id == empresa_id,
                PeriodoContable.anio == anio, PeriodoContable.mes == 12)
        .first()
    )
    if dic is not None and dic.estado != "abierto":
        dic.estado = "abierto"
        db.flush()

    lineas = []
    for cuenta_id, neto in netos.items():
        if neto > CERO:
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, credito=neto,
                                       glosa=f"Reversión del cierre {anio}"))
        else:
            lineas.append(LineaAsiento(cuenta_id=cuenta_id, debito=-neto,
                                       glosa=f"Reversión del cierre {anio}"))
    asiento = contab.registrar_asiento(
        db, empresa_id, date(anio, 12, 31),
        f"Reversión del cierre del ejercicio {anio}",
        ORIGEN_CIERRE, lineas, creado_por_id=creado_por_id, commit=False,
    )
    db.commit()
    return {"anio": anio, "asiento": asiento.numero, "diciembre_reabierto": True}
