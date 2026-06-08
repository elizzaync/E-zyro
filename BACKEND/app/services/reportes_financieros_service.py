"""
Reportes financieros (Fase 9) — capa de SOLO LECTURA sobre el libro mayor.

No genera asientos ni modifica datos: cada reporte es una agregación pura sobre
cuenta_contable / asiento_contable / asiento_linea / periodo_contable. Los
reportes se calculan SIEMPRE en vivo (nunca se persisten) — guardar un reporte
es la receta para que un día no cuadre con el libro mayor.

Determinismo: el mismo rango de fechas produce siempre el mismo resultado; no
hay dependencia de hora/zona horaria del servidor.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import (
    CuentaContable, AsientoContable, AsientoLinea, PeriodoContable,
)

CERO = Decimal("0.00")
Q2 = Decimal("0.01")


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


def _rango_periodo(periodo: str) -> tuple[date, date]:
    """'YYYY-MM' → (primer día, último día) del mes."""
    from datetime import timedelta
    try:
        anio, mes = (int(x) for x in periodo.split("-"))
        ini = date(anio, mes, 1)
        fin = date(anio + (mes == 12), (mes % 12) + 1, 1) - timedelta(days=1)
        return ini, fin
    except Exception:
        raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")


def _saldos_por_cuenta(db: Session, empresa_id: str, hasta: date | None = None,
                       desde: date | None = None) -> list[tuple]:
    """(codigo, nombre, tipo, naturaleza, total_debito, total_credito) por cuenta
    de detalle con movimiento en el rango."""
    q = (
        db.query(
            CuentaContable.codigo, CuentaContable.nombre, CuentaContable.tipo,
            CuentaContable.naturaleza,
            func.coalesce(func.sum(AsientoLinea.debito), 0).label("td"),
            func.coalesce(func.sum(AsientoLinea.credito), 0).label("tc"),
        )
        .join(AsientoLinea, AsientoLinea.cuenta_id == CuentaContable.id)
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id)
    )
    if desde:
        q = q.filter(AsientoContable.fecha >= desde)
    if hasta:
        q = q.filter(AsientoContable.fecha <= hasta)
    q = q.group_by(CuentaContable.codigo, CuentaContable.nombre,
                   CuentaContable.tipo, CuentaContable.naturaleza).order_by(CuentaContable.codigo)
    return q.all()


# ── 1) Balance de comprobación ───────────────────────────────────────────────
def balance_comprobacion(db: Session, empresa_id: str, periodo: str) -> dict:
    ini, fin = _rango_periodo(periodo)
    filas = _saldos_por_cuenta(db, empresa_id, hasta=fin, desde=ini)
    cuentas = []
    tot_deudor = tot_acreedor = CERO
    for codigo, nombre, _tipo, _nat, td, tc in filas:
        td, tc = _d(td), _d(tc)
        saldo = td - tc
        deudor = saldo if saldo > 0 else CERO
        acreedor = -saldo if saldo < 0 else CERO
        tot_deudor += deudor
        tot_acreedor += acreedor
        cuentas.append({"codigo": codigo, "nombre": nombre, "total_debito": td,
                        "total_credito": tc, "saldo_deudor": deudor, "saldo_acreedor": acreedor})
    return {"periodo": periodo, "cuentas": cuentas,
            "total_deudor": tot_deudor, "total_acreedor": tot_acreedor,
            "cuadrado": tot_deudor == tot_acreedor}


# ── 2) Balance general (situación financiera) ────────────────────────────────
def balance_general(db: Session, empresa_id: str, fecha: date) -> dict:
    """Agrupa saldos acumulados hasta `fecha` por tipo. Activo = Pasivo + Patrimonio."""
    filas = _saldos_por_cuenta(db, empresa_id, hasta=fecha)
    activo = pasivo = patrimonio = CERO
    det_activo, det_pasivo, det_patrimonio = [], [], []
    # Resultado del ejercicio (ingresos − gastos) integra al patrimonio
    ingresos = gastos = CERO
    for codigo, nombre, tipo, _nat, td, tc in filas:
        saldo = _d(td) - _d(tc)  # deudor positivo
        if tipo == "activo":
            activo += saldo
            det_activo.append({"codigo": codigo, "nombre": nombre, "saldo": saldo})
        elif tipo == "pasivo":
            pasivo += -saldo  # acreedor positivo
            det_pasivo.append({"codigo": codigo, "nombre": nombre, "saldo": -saldo})
        elif tipo == "patrimonio":
            patrimonio += -saldo
            det_patrimonio.append({"codigo": codigo, "nombre": nombre, "saldo": -saldo})
        elif tipo == "ingreso":
            ingresos += -saldo
        elif tipo == "gasto":
            gastos += saldo
    resultado_ejercicio = (ingresos - gastos).quantize(Q2)
    patrimonio_total = (patrimonio + resultado_ejercicio).quantize(Q2)
    if resultado_ejercicio != CERO:
        det_patrimonio.append({"codigo": "RESULT", "nombre": "Resultado del ejercicio",
                               "saldo": resultado_ejercicio})
    pasivo_patrimonio = (pasivo + patrimonio_total).quantize(Q2)
    return {
        "fecha": fecha, "activo": det_activo, "pasivo": det_pasivo, "patrimonio": det_patrimonio,
        "total_activo": activo.quantize(Q2), "total_pasivo": pasivo.quantize(Q2),
        "total_patrimonio": patrimonio_total, "total_pasivo_patrimonio": pasivo_patrimonio,
        "cuadrado": activo.quantize(Q2) == pasivo_patrimonio,
    }


# ── 3) Estado de resultados ──────────────────────────────────────────────────
def estado_resultados(db: Session, empresa_id: str, desde: date, hasta: date) -> dict:
    filas = _saldos_por_cuenta(db, empresa_id, hasta=hasta, desde=desde)
    ingresos, gastos = [], []
    tot_ing = tot_gas = CERO
    for codigo, nombre, tipo, _nat, td, tc in filas:
        if tipo == "ingreso":
            monto = (_d(tc) - _d(td)).quantize(Q2)
            tot_ing += monto
            ingresos.append({"codigo": codigo, "nombre": nombre, "monto": monto})
        elif tipo == "gasto":
            monto = (_d(td) - _d(tc)).quantize(Q2)
            tot_gas += monto
            gastos.append({"codigo": codigo, "nombre": nombre, "monto": monto})
    return {"desde": desde, "hasta": hasta, "ingresos": ingresos, "gastos": gastos,
            "total_ingresos": tot_ing.quantize(Q2), "total_gastos": tot_gas.quantize(Q2),
            "resultado": (tot_ing - tot_gas).quantize(Q2)}


# ── 4) Flujo de efectivo (sobre cuentas de efectivo, elemento 10) ────────────
def flujo_efectivo(db: Session, empresa_id: str, periodo: str) -> dict:
    ini, fin = _rango_periodo(periodo)
    # Movimientos de cuentas cuyo código empieza por '10' (efectivo)
    filas = (
        db.query(
            AsientoContable.origen,
            func.coalesce(func.sum(AsientoLinea.debito), 0),
            func.coalesce(func.sum(AsientoLinea.credito), 0),
        )
        .join(AsientoLinea, AsientoLinea.asiento_id == AsientoContable.id)
        .join(CuentaContable, AsientoLinea.cuenta_id == CuentaContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.fecha >= ini, AsientoContable.fecha <= fin,
                CuentaContable.codigo.like("10%"))
        .group_by(AsientoContable.origen)
        .all()
    )
    detalle = []
    entradas = salidas = CERO
    for origen, td, tc in filas:
        td, tc = _d(td), _d(tc)  # td = entrada de efectivo, tc = salida
        entradas += td
        salidas += tc
        detalle.append({"origen": origen, "entradas": td, "salidas": tc, "neto": (td - tc).quantize(Q2)})
    return {"periodo": periodo, "detalle": detalle, "total_entradas": entradas.quantize(Q2),
            "total_salidas": salidas.quantize(Q2), "flujo_neto": (entradas - salidas).quantize(Q2)}


# ── 5) Libros auxiliares ─────────────────────────────────────────────────────
def libro_diario(db: Session, empresa_id: str, periodo: str) -> list[dict]:
    ini, fin = _rango_periodo(periodo)
    asientos = (
        db.query(AsientoContable)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.fecha >= ini, AsientoContable.fecha <= fin)
        .order_by(AsientoContable.fecha, AsientoContable.numero)
        .all()
    )
    salida = []
    for a in asientos:
        lineas = (
            db.query(AsientoLinea, CuentaContable.codigo, CuentaContable.nombre)
            .join(CuentaContable, AsientoLinea.cuenta_id == CuentaContable.id)
            .filter(AsientoLinea.asiento_id == a.id)
            .order_by(CuentaContable.codigo)
            .all()
        )
        salida.append({
            "numero": a.numero, "fecha": a.fecha, "descripcion": a.descripcion, "origen": a.origen,
            "lineas": [{"codigo": cod, "nombre": nom, "debito": _d(l.debito), "credito": _d(l.credito)}
                       for l, cod, nom in lineas],
        })
    return salida


def libro_mayor(db: Session, empresa_id: str, cuenta_id: str, periodo: str) -> dict:
    ini, fin = _rango_periodo(periodo)
    cuenta = db.query(CuentaContable).filter(
        CuentaContable.id == cuenta_id, CuentaContable.empresa_id == empresa_id).first()
    if cuenta is None:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada.")
    movimientos = (
        db.query(AsientoLinea, AsientoContable.fecha, AsientoContable.numero, AsientoContable.descripcion)
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id, AsientoLinea.cuenta_id == cuenta_id,
                AsientoContable.fecha >= ini, AsientoContable.fecha <= fin)
        .order_by(AsientoContable.fecha, AsientoContable.numero)
        .all()
    )
    filas = []
    saldo = CERO
    for l, fecha, numero, desc in movimientos:
        saldo += _d(l.debito) - _d(l.credito)
        filas.append({"fecha": fecha, "numero": numero, "descripcion": desc,
                      "debito": _d(l.debito), "credito": _d(l.credito), "saldo": saldo.quantize(Q2)})
    return {"cuenta_codigo": cuenta.codigo, "cuenta_nombre": cuenta.nombre,
            "periodo": periodo, "movimientos": filas, "saldo_final": saldo.quantize(Q2)}
