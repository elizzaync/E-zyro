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
                       desde: date | None = None,
                       excluir_origenes: tuple[str, ...] = ()) -> list[tuple]:
    """(codigo, nombre, tipo, naturaleza, total_debito, total_credito) por cuenta
    de detalle con movimiento en el rango.

    `excluir_origenes`: los reportes de RESULTADOS excluyen 'cierre_ejercicio'
    (el asiento de cierre salda 6x/7x; incluirlo dejaría el estado de resultados
    de un año cerrado en cero). Los reportes de BALANCE lo incluyen siempre: el
    59x actualizado y las 6x/7x saldadas son precisamente su efecto correcto."""
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
    if excluir_origenes:
        q = q.filter(~AsientoContable.origen.in_(excluir_origenes))
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
    filas = _saldos_por_cuenta(db, empresa_id, hasta=hasta, desde=desde,
                               excluir_origenes=("cierre_ejercicio",))
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


# ── 6) Resumen financiero (dashboard) ────────────────────────────────────────
def _documentos_abiertos(db: Session, empresa_id: str, lado: str) -> list[tuple[date, Decimal]]:
    """[(fecha_vencimiento, saldo_pendiente)] de facturas abiertas de CxP o CxC.

    El saldo se calcula en SQL (total − aplicaciones) para no iterar factura por
    factura en Python; imports perezosos para no acoplar módulos al importar."""
    if lado == "cxp":
        from app.models.cuentas_por_pagar import FacturaProveedor as Doc, AplicacionPagoProveedor as Apl
        col_factura = Apl.factura_id
        estados = ("pendiente", "pagada_parcial")
    else:
        from app.models.cuentas_por_cobrar import FacturaCliente as Doc, AplicacionCobroCliente as Apl
        col_factura = Apl.factura_id
        estados = ("pendiente", "cobrada_parcial")
    aplicado = (
        db.query(col_factura.label("fid"),
                 func.coalesce(func.sum(Apl.monto_aplicado), 0).label("apl"))
        .group_by(col_factura)
        .subquery()
    )
    filas = (
        db.query(Doc.fecha_vencimiento, Doc.moneda, Doc.tipo_cambio,
                 (Doc.total - func.coalesce(aplicado.c.apl, 0)).label("saldo"))
        .outerjoin(aplicado, aplicado.c.fid == Doc.id)
        .filter(Doc.empresa_id == empresa_id,
                Doc.estado.in_(estados))
        .all()
    )
    # Los documentos en moneda extranjera se agregan convertidos al TC de emisión
    # (el mismo de su asiento): el dashboard suma soles con soles.
    out = []
    for fv, moneda, tc, s in filas:
        saldo = _d(s)
        if saldo <= CERO:
            continue
        if (moneda or "PEN") != "PEN":
            saldo = (saldo * _d(tc or 1)).quantize(Q2)
        out.append((fv, saldo))
    return out


def _buckets_vencimiento(pares: list[tuple[date, Decimal]], hoy: date) -> dict:
    """Agrega documentos abiertos en: total, vencido (y cuántos), y exigible a
    30/60/90 días. Lo vencido cuenta dentro del bucket de 30 (es exigible YA):
    así la proyección de caja nunca esconde una deuda atrasada."""
    total = vencido = b30 = b60 = b90 = CERO
    n_vencidos = 0
    for fv, saldo in pares:
        # CxC al contado guarda vencimiento NULL: si sigue abierta, es exigible hoy.
        fv = fv or hoy
        total += saldo
        if fv < hoy:
            vencido += saldo
            n_vencidos += 1
        dias = (fv - hoy).days
        if dias <= 30:
            b30 += saldo
        elif dias <= 60:
            b60 += saldo
        elif dias <= 90:
            b90 += saldo
    return {"total": total.quantize(Q2), "vencido": vencido.quantize(Q2),
            "n_vencidos": n_vencidos, "hasta_30": b30.quantize(Q2),
            "hasta_60": b60.quantize(Q2), "hasta_90": b90.quantize(Q2)}


def resumen_financiero(db: Session, empresa_id: str, hoy: date | None = None) -> dict:
    """KPIs del dashboard de Finanzas — todo derivado en vivo del libro mayor y
    de los documentos abiertos de CxP/CxC. Nada se persiste ni se digita.

    Pensado para un usuario NO contable: disponible hoy, cuánto me deben /
    cuánto debo (y qué está vencido), cómo me fue en el mes, en qué gasto más,
    el flujo de los últimos 6 meses y la caja proyectada a 30/60/90 días."""
    hoy = hoy or date.today()

    # 1) Disponible hoy: saldo acumulado de cuentas de efectivo (elemento 10)
    filas_10 = (
        db.query(CuentaContable.codigo,
                 func.coalesce(func.sum(AsientoLinea.debito), 0),
                 func.coalesce(func.sum(AsientoLinea.credito), 0))
        .join(AsientoLinea, AsientoLinea.cuenta_id == CuentaContable.id)
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.fecha <= hoy,
                CuentaContable.codigo.like("10%"))
        .group_by(CuentaContable.codigo)
        .all()
    )
    caja = bancos = otros = CERO
    for codigo, td, tc in filas_10:
        saldo = _d(td) - _d(tc)
        if codigo.startswith("101"):
            caja += saldo
        elif codigo.startswith("104"):
            bancos += saldo
        else:
            otros += saldo
    disponible = (caja + bancos + otros).quantize(Q2)

    # 2) Por cobrar / por pagar con semáforo de vencimiento
    cxc = _buckets_vencimiento(_documentos_abiertos(db, empresa_id, "cxc"), hoy)
    cxp = _buckets_vencimiento(_documentos_abiertos(db, empresa_id, "cxp"), hoy)

    # 3) Resultado del mes en curso (excluye asientos de cierre)
    inicio_mes = hoy.replace(day=1)
    er = estado_resultados(db, empresa_id, inicio_mes, hoy)
    resultado_mes = {"ingresos": er["total_ingresos"], "gastos": er["total_gastos"],
                     "resultado": er["resultado"]}

    # 4) Top 5 gastos del mes por cuenta de detalle
    top_gastos = sorted(er["gastos"], key=lambda g: g["monto"], reverse=True)[:5]

    # 5) Serie de flujo de efectivo de los últimos 6 meses (incluye el actual)
    anio_ini = hoy.year if hoy.month > 5 else hoy.year - 1
    mes_ini = hoy.month - 5 if hoy.month > 5 else hoy.month + 7
    ini_serie = date(anio_ini, mes_ini, 1)
    filas_serie = (
        db.query(func.extract("year", AsientoContable.fecha).label("a"),
                 func.extract("month", AsientoContable.fecha).label("m"),
                 func.coalesce(func.sum(AsientoLinea.debito), 0),
                 func.coalesce(func.sum(AsientoLinea.credito), 0))
        .join(AsientoLinea, AsientoLinea.asiento_id == AsientoContable.id)
        .join(CuentaContable, AsientoLinea.cuenta_id == CuentaContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.fecha >= ini_serie, AsientoContable.fecha <= hoy,
                CuentaContable.codigo.like("10%"))
        .group_by("a", "m")
        .all()
    )
    por_mes = {(int(a), int(m)): (_d(td), _d(tc)) for a, m, td, tc in filas_serie}
    flujo_mensual = []
    anio, mes = ini_serie.year, ini_serie.month
    for _ in range(6):
        td, tc = por_mes.get((anio, mes), (CERO, CERO))
        flujo_mensual.append({"periodo": f"{anio}-{mes:02d}", "entradas": td,
                              "salidas": tc, "neto": (td - tc).quantize(Q2)})
        anio, mes = (anio + 1, 1) if mes == 12 else (anio, mes + 1)

    # 6) Caja proyectada: disponible + lo que entra − lo que sale, por horizonte
    proyeccion = []
    entra = sale = CERO
    for dias, ke, ks in ((30, "hasta_30", "hasta_30"), (60, "hasta_60", "hasta_60"),
                         (90, "hasta_90", "hasta_90")):
        entra += cxc[ke]
        sale += cxp[ks]
        proyeccion.append({"dias": dias,
                           "cobros_esperados": entra.quantize(Q2),
                           "pagos_comprometidos": sale.quantize(Q2),
                           "saldo_proyectado": (disponible + entra - sale).quantize(Q2)})

    # 7) Salud contable: ¿el mes en curso está abierto para registrar?
    periodo_actual = (
        db.query(PeriodoContable)
        .filter(PeriodoContable.empresa_id == empresa_id,
                PeriodoContable.anio == hoy.year, PeriodoContable.mes == hoy.month)
        .first()
    )

    return {
        "fecha": hoy,
        "disponible": {"total": disponible, "caja": caja.quantize(Q2),
                       "bancos": bancos.quantize(Q2), "otros": otros.quantize(Q2)},
        "cxc": cxc,
        "cxp": cxp,
        "resultado_mes": resultado_mes,
        "top_gastos_mes": top_gastos,
        "flujo_mensual": flujo_mensual,
        "proyeccion": proyeccion,
        "periodo_actual_abierto": bool(periodo_actual and periodo_actual.estado == "abierto"),
    }
