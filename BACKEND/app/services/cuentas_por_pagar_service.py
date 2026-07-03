"""
Servicio de Cuentas por Pagar — AP (Fase 3).

Primer integrador real del módulo de finanzas: cada hecho operativo (registrar
una factura, pagarla, anularla) genera su asiento automático llamando a
`contabilizacion_service.registrar_asiento` con `commit=False`, de modo que el
documento (factura/pago) y su asiento se confirman en UNA sola transacción. Si
el asiento no cuadra o falla un constraint, nada se persiste.

Mapeo contable (Fase 0), usando cuentas de DETALLE del PCGE sembrado:
  Registrar factura : Db 601 Compras  (+ Db 40111 IGV crédito fiscal)
                      Cr 421 Facturas por pagar
  Registrar pago    : Db 421 Facturas por pagar
                      Cr 101 Caja / 104 Bancos  (según medio de pago)
  Anular factura    : asiento de REVERSIÓN del original (nunca se borra el
                      asiento — la trazabilidad es permanente).
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable, AsientoContable, AsientoLinea
from app.models.cuentas_por_pagar import (
    FacturaProveedor, PagoProveedor, AplicacionPagoProveedor,
)
from app.models.proveedor import Proveedor
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")

# Cuentas de detalle del PCGE usadas por el mapeo de Fase 0.
CTA_COMPRAS       = "601"    # 60 Compras / 601 Mercaderías
CTA_IGV_CREDITO   = "40111"  # IGV - cuenta propia (crédito fiscal en compras)
CTA_POR_PAGAR     = "421"    # Facturas, boletas y otros comprobantes por pagar
CTA_CAJA          = "101"    # Caja
CTA_BANCOS        = "104"    # Cuentas corrientes en instituciones financieras

MEDIO_A_CUENTA = {
    "efectivo": CTA_CAJA,
    "transferencia": CTA_BANCOS,
    "cheque": CTA_BANCOS,
}


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Decimal("0.01"))


def _tc_emision(db: Session, empresa_id: str, moneda: str, fecha) -> Decimal | None:
    """TC venta si la factura es en moneda extranjera (multimoneda activa)."""
    from app.services import tipo_cambio_service as tcs

    if moneda == "PEN":
        return None
    if not tcs.multimoneda_activa(db, empresa_id):
        raise HTTPException(
            status_code=422,
            detail="Multimoneda no habilitada: actívala en Finanzas → "
                   "Configuración contable para registrar en moneda extranjera.")
    return tcs.obtener_venta(db, fecha, moneda)


def _pen(monto: Decimal, tc: Decimal | None) -> Decimal:
    """Convierte a PEN para el asiento (los libros van en moneda funcional)."""
    return _d(monto if tc is None else monto * tc)


def _cuenta(db: Session, empresa_id: str, codigo: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == codigo)
        .first()
    )
    if c is None:
        raise HTTPException(
            status_code=422,
            detail=f"Falta la cuenta contable {codigo} en el plan de la empresa "
                   f"(¿se sembró el PCGE?).",
        )
    return c


def _cuenta_gasto(db: Session, empresa_id: str, cuenta_gasto_id: str | None) -> CuentaContable:
    """Resuelve la cuenta de gasto que debita la factura. Sin selección explícita
    cae a 601 Mercaderías (compatibilidad con el comportamiento previo). Si se
    elige una cuenta, debe ser de la empresa, de tipo 'gasto', de detalle y activa
    — así una factura de servicios se clasifica en 63/65 y no se fuerza a 601."""
    if not cuenta_gasto_id:
        return _cuenta(db, empresa_id, CTA_COMPRAS)
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.id == cuenta_gasto_id,
                CuentaContable.empresa_id == empresa_id)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422, detail="La cuenta de gasto no existe en la empresa.")
    if c.tipo != "gasto":
        raise HTTPException(status_code=422, detail=f"La cuenta {c.codigo} no es una cuenta de gasto.")
    if c.nivel != "detalle":
        raise HTTPException(status_code=422, detail=f"La cuenta {c.codigo} es de mayor; elige una de detalle.")
    if not c.activo:
        raise HTTPException(status_code=422, detail=f"La cuenta de gasto {c.codigo} está inactiva.")
    return c


def _proveedor(db: Session, empresa_id: str, proveedor_id: str) -> Proveedor:
    p = (
        db.query(Proveedor)
        .filter(Proveedor.id == proveedor_id, Proveedor.empresa_id == empresa_id)
        .first()
    )
    if p is None:
        raise HTTPException(status_code=422, detail="El proveedor no existe en la empresa.")
    return p


def get_factura(db: Session, empresa_id: str, factura_id: str) -> FacturaProveedor:
    f = (
        db.query(FacturaProveedor)
        .filter(FacturaProveedor.id == factura_id,
                FacturaProveedor.empresa_id == empresa_id)
        .first()
    )
    if f is None:
        raise HTTPException(status_code=404, detail="Factura no encontrada.")
    return f


def saldo_pendiente(db: Session, factura: FacturaProveedor) -> Decimal:
    """Total de la factura menos pagos aplicados y notas de crédito vigentes.
    Una factura anulada no tiene saldo; una nota de crédito tampoco (no es
    exigible: su efecto es rebajar el saldo del documento que afecta)."""
    if factura.estado == "anulada" or factura.tipo_documento == "nota_credito":
        return CERO
    aplicado = (
        db.query(func.coalesce(func.sum(AplicacionPagoProveedor.monto_aplicado), 0))
        .filter(AplicacionPagoProveedor.factura_id == factura.id)
        .scalar()
    ) or 0
    acreditado = (
        db.query(func.coalesce(func.sum(FacturaProveedor.total), 0))
        .filter(FacturaProveedor.documento_afectado_id == str(factura.id),
                FacturaProveedor.tipo_documento == "nota_credito",
                FacturaProveedor.estado != "anulada")
        .scalar()
    ) or 0
    return _d(factura.total) - _d(aplicado) - _d(acreditado)


def _estado_por_saldo(total: Decimal, saldo: Decimal) -> str:
    if saldo <= CERO:
        return "pagada"
    if saldo < total:
        return "pagada_parcial"
    return "pendiente"


# ── Registrar factura ────────────────────────────────────────────────────────
def registrar_factura(db: Session, empresa_id: str, datos, creado_por_id: str | None = None) -> FacturaProveedor:
    """Crea la factura y su asiento automático en una sola transacción atómica."""
    _proveedor(db, empresa_id, datos.proveedor_id)

    subtotal = _d(datos.subtotal)
    igv = _d(datos.igv)
    total = subtotal + igv

    # Duplicado por (empresa, proveedor, numero) — además del UNIQUE de BD, da
    # un 409 limpio en vez de un 500 por violación de constraint.
    dup = (
        db.query(FacturaProveedor)
        .filter(FacturaProveedor.empresa_id == empresa_id,
                FacturaProveedor.proveedor_id == datos.proveedor_id,
                FacturaProveedor.numero_documento == datos.numero_documento)
        .first()
    )
    if dup:
        raise HTTPException(status_code=409, detail="Ya existe una factura con ese número para el proveedor.")

    moneda = datos.moneda or _moneda_empresa(db, empresa_id)

    # Cuenta de gasto a debitar: la elegida (601 mercadería | 63/65 servicios…) o 601 por defecto.
    cuenta_gasto = _cuenta_gasto(db, empresa_id, getattr(datos, "cuenta_gasto_id", None))

    # Nota de crédito: REBAJA deuda y gasto (asiento inverso) aplicándose a una
    # factura del mismo proveedor. No es exigible por sí misma.
    es_nc = datos.tipo_documento == "nota_credito"
    doc_afectado = None
    if es_nc:
        afectado_id = getattr(datos, "documento_afectado_id", None)
        if not afectado_id:
            raise HTTPException(
                status_code=422,
                detail="Una nota de crédito debe indicar la factura que afecta.")
        doc_afectado = get_factura(db, empresa_id, afectado_id)
        if str(doc_afectado.proveedor_id) != str(datos.proveedor_id):
            raise HTTPException(status_code=422, detail="La factura afectada no es del proveedor indicado.")
        if doc_afectado.estado == "anulada":
            raise HTTPException(status_code=422, detail="La factura afectada está anulada.")
        if doc_afectado.tipo_documento == "nota_credito":
            raise HTTPException(status_code=422, detail="Una nota de crédito no puede afectar a otra nota de crédito.")
        saldo_afectado = saldo_pendiente(db, doc_afectado)
        if total > saldo_afectado:
            raise HTTPException(
                status_code=422,
                detail=f"La nota de crédito ({total}) excede el saldo pendiente "
                       f"({saldo_afectado}) de la factura {doc_afectado.numero_documento}.")

    tc = _tc_emision(db, empresa_id, moneda, datos.fecha_emision)

    factura = FacturaProveedor(
        empresa_id=empresa_id,
        proveedor_id=datos.proveedor_id,
        orden_compra_id=datos.orden_compra_id,
        numero_documento=datos.numero_documento,
        tipo_documento=datos.tipo_documento,
        fecha_emision=datos.fecha_emision,
        fecha_vencimiento=datos.fecha_vencimiento,
        moneda=moneda,
        tipo_cambio=tc,
        subtotal=subtotal,
        igv=igv,
        total=total,
        # La NC nace 'pagada' (= aplicada): así ningún reporte de saldos,
        # antigüedad ni alerta de vencimiento la trata como deuda exigible.
        estado=("pagada" if es_nc else "pendiente"),
        cuenta_gasto_id=str(cuenta_gasto.id),
        documento_afectado_id=(str(doc_afectado.id) if doc_afectado is not None else None),
    )
    db.add(factura)
    db.flush()  # obtiene factura.id sin confirmar

    # Asiento (sin commit; lo hace esta fn). Factura/boleta/ND: Db gasto (+IGV) /
    # Cr Por pagar. Nota de crédito: el espejo — Db Por pagar / Cr gasto (+IGV).
    # La cuenta de IGV la resuelve el servicio tributario (Fase 6) por configuración.
    # Asiento en PEN; la factura conserva su moneda origen y el TC usado.
    sub_pen = _pen(subtotal, tc)
    igv_pen = _pen(igv, tc)
    total_pen = sub_pen + igv_pen

    from app.services import tributario_service as tributario
    if es_nc:
        lineas = [LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_POR_PAGAR).id, debito=total_pen),
                  LineaAsiento(cuenta_id=cuenta_gasto.id, credito=sub_pen)]
        if igv > CERO:
            lineas.append(LineaAsiento(cuenta_id=tributario.cuenta_igv(db, empresa_id, "credito_fiscal").id, credito=igv_pen))
        descripcion = (f"Nota de crédito {datos.numero_documento} sobre "
                       f"factura {doc_afectado.numero_documento}")
    else:
        lineas = [LineaAsiento(cuenta_id=cuenta_gasto.id, debito=sub_pen)]
        if igv > CERO:
            lineas.append(LineaAsiento(cuenta_id=tributario.cuenta_igv(db, empresa_id, "credito_fiscal").id, debito=igv_pen))
        lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_POR_PAGAR).id, credito=total_pen))
        descripcion = f"Factura {datos.tipo_documento} {datos.numero_documento}"

    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=datos.fecha_emision,
            descripcion=descripcion,
            origen="compras", lineas=lineas, referencia_id=factura.id,
            creado_por_id=creado_por_id, commit=False,
        )
        factura.asiento_id = asiento.id
        if es_nc and doc_afectado is not None:
            # El saldo de la factura afectada baja: refleja su nuevo estado.
            doc_afectado.estado = _estado_por_saldo(
                _d(doc_afectado.total), saldo_afectado - total)
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo registrar la factura: {exc}") from exc

    db.refresh(factura)
    return factura


# ── Registrar pago ───────────────────────────────────────────────────────────
def registrar_pago(db: Session, empresa_id: str, datos, creado_por_id: str | None = None) -> PagoProveedor:
    """Registra un pago, lo aplica a facturas y genera su asiento, todo atómico.

    Valida (antes de tocar la BD) que cada aplicación no exceda el saldo
    pendiente de su factura y que las facturas existan, sean del proveedor y no
    estén anuladas."""
    _proveedor(db, empresa_id, datos.proveedor_id)

    if not datos.aplicaciones:
        raise HTTPException(status_code=422, detail="El pago debe aplicarse al menos a una factura.")

    monto_total = CERO
    facturas_estado: list[tuple[FacturaProveedor, Decimal, Decimal]] = []  # (factura, aplicado, saldo_nuevo)
    for ap in datos.aplicaciones:
        f = get_factura(db, empresa_id, ap.factura_id)
        # f.proveedor_id es uuid.UUID (columna UUID nativa) y datos.proveedor_id
        # es str: comparar sin normalizar da SIEMPRE True y rechaza todo pago.
        if str(f.proveedor_id) != str(datos.proveedor_id):
            raise HTTPException(status_code=422, detail=f"La factura {f.numero_documento} no es del proveedor indicado.")
        if f.estado == "anulada":
            raise HTTPException(status_code=422, detail=f"La factura {f.numero_documento} está anulada.")
        aplicado = _d(ap.monto_aplicado)
        saldo = saldo_pendiente(db, f)
        if aplicado > saldo:
            raise HTTPException(
                status_code=422,
                detail=f"El monto aplicado ({aplicado}) excede el saldo pendiente "
                       f"({saldo}) de la factura {f.numero_documento}.",
            )
        facturas_estado.append((f, aplicado, saldo - aplicado))
        monto_total += aplicado

    if monto_total <= CERO:
        raise HTTPException(status_code=422, detail="El monto del pago debe ser mayor que 0.")

    # Multimoneda: un pago aplica a facturas de UNA sola moneda.
    monedas = {f.moneda for f, _a, _s in facturas_estado}
    if len(monedas) > 1:
        raise HTTPException(status_code=422,
                            detail="Un pago no puede mezclar facturas de distintas monedas.")
    moneda_pago = monedas.pop()
    tc_pago = None
    if moneda_pago != "PEN":
        from app.services import tipo_cambio_service as tcs
        tc_pago = tcs.obtener_venta(db, datos.fecha_pago, moneda_pago)

    cuenta_origen = _cuenta(db, empresa_id, MEDIO_A_CUENTA[datos.medio_pago])

    pago = PagoProveedor(
        empresa_id=empresa_id, proveedor_id=datos.proveedor_id,
        fecha_pago=datos.fecha_pago, monto=monto_total,
        moneda=moneda_pago, tipo_cambio=tc_pago,
        medio_pago=datos.medio_pago, referencia=datos.referencia,
    )
    db.add(pago)
    db.flush()

    for f, aplicado, _saldo_nuevo in facturas_estado:
        db.add(AplicacionPagoProveedor(pago_id=pago.id, factura_id=f.id, monto_aplicado=aplicado))

    # Asiento en PEN: la 421 se rebaja al TC HISTÓRICO de cada factura; la caja
    # sale al TC de HOY. Pagar más caro que lo provisionado es pérdida (Db 676);
    # más barato, ganancia (Cr 776).
    caja_pen = _pen(monto_total, tc_pago)
    hist_pen = sum((_pen(aplicado, Decimal(str(f.tipo_cambio)) if f.tipo_cambio else None)
                    for f, aplicado, _s in facturas_estado), CERO)
    lineas = [
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_POR_PAGAR).id, debito=hist_pen),
        LineaAsiento(cuenta_id=cuenta_origen.id, credito=caja_pen),
    ]
    dif = caja_pen - hist_pen
    if dif != CERO:
        from app.services import tipo_cambio_service as tcs
        cta_gan, cta_per = tcs.cuentas_diferencia_cambio(db, empresa_id)
        if dif > CERO:
            lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, cta_per).id,
                                       debito=dif, glosa="Pérdida por diferencia de cambio"))
        else:
            lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, cta_gan).id,
                                       credito=-dif, glosa="Ganancia por diferencia de cambio"))
    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=datos.fecha_pago,
            descripcion=f"Pago a proveedor ({datos.medio_pago})",
            origen="compras", lineas=lineas, referencia_id=pago.id,
            creado_por_id=creado_por_id, commit=False,
        )
        pago.asiento_id = asiento.id
        # Actualiza el estado de cada factura según su saldo restante.
        for f, _aplicado, saldo_nuevo in facturas_estado:
            f.estado = _estado_por_saldo(_d(f.total), saldo_nuevo)
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo registrar el pago: {exc}") from exc

    db.refresh(pago)
    return pago


# ── Anular factura ───────────────────────────────────────────────────────────
def anular_factura(db: Session, empresa_id: str, factura_id: str, creado_por_id: str | None = None) -> FacturaProveedor:
    """Anula una factura mediante un asiento de REVERSIÓN (no borra el original).

    Solo es posible si la factura no tiene pagos aplicados: revertir contable y
    operativamente una factura ya pagada exigiría además revertir los pagos, lo
    que se maneja anulando primero los pagos (fuera del alcance de esta fase)."""
    factura = get_factura(db, empresa_id, factura_id)
    if factura.estado == "anulada":
        raise HTTPException(status_code=409, detail="La factura ya está anulada.")

    aplicado = (
        db.query(func.coalesce(func.sum(AplicacionPagoProveedor.monto_aplicado), 0))
        .filter(AplicacionPagoProveedor.factura_id == factura.id)
        .scalar()
    ) or 0
    if _d(aplicado) > CERO:
        raise HTTPException(
            status_code=409,
            detail="No se puede anular una factura con pagos aplicados; anule primero los pagos.",
        )
    # Una factura con notas de crédito vigentes tampoco se anula directamente:
    # quedarían NC "colgadas" rebajando un documento inexistente.
    nc_vigente = (
        db.query(FacturaProveedor)
        .filter(FacturaProveedor.documento_afectado_id == str(factura.id),
                FacturaProveedor.tipo_documento == "nota_credito",
                FacturaProveedor.estado != "anulada")
        .first()
    )
    if nc_vigente is not None:
        raise HTTPException(
            status_code=409,
            detail=f"La factura tiene la nota de crédito {nc_vigente.numero_documento} "
                   "vigente; anúlela primero.",
        )

    # Reversión: por cada línea del asiento original, una línea espejo (débito y
    # crédito intercambiados). Garantiza que el neto contable vuelve a cero.
    lineas_orig = (
        db.query(AsientoLinea)
        .filter(AsientoLinea.asiento_id == factura.asiento_id)
        .all()
    ) if factura.asiento_id else []
    if not lineas_orig:
        # Sin asiento que revertir (caso defensivo): solo marca el estado.
        factura.estado = "anulada"
        db.commit()
        db.refresh(factura)
        return factura

    lineas_rev = [
        LineaAsiento(
            cuenta_id=str(l.cuenta_id),
            debito=_d(l.credito), credito=_d(l.debito),
            centro_costo_id=(str(l.centro_costo_id) if l.centro_costo_id else None),
            glosa="Reversión por anulación de factura",
        )
        for l in lineas_orig
    ]
    try:
        contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=factura.fecha_emision,
            descripcion=f"Anulación factura {factura.numero_documento}",
            origen="compras", lineas=lineas_rev, referencia_id=factura.id,
            creado_por_id=creado_por_id, commit=False,
        )
        factura.estado = "anulada"
        # Anular una NC devuelve el saldo a la factura que afectaba.
        if factura.tipo_documento == "nota_credito" and factura.documento_afectado_id:
            db.flush()  # la NC anulada ya no cuenta en saldo_pendiente
            afectada = (
                db.query(FacturaProveedor)
                .filter(FacturaProveedor.id == str(factura.documento_afectado_id),
                        FacturaProveedor.empresa_id == empresa_id)
                .first()
            )
            if afectada is not None and afectada.estado != "anulada":
                afectada.estado = _estado_por_saldo(
                    _d(afectada.total), saldo_pendiente(db, afectada))
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo anular la factura: {exc}") from exc

    db.refresh(factura)
    return factura


# ── Reportes ─────────────────────────────────────────────────────────────────
def reporte_saldos(db: Session, empresa_id: str) -> list[dict]:
    """Saldos abiertos por proveedor (facturas pendiente/pagada_parcial)."""
    facturas = (
        db.query(FacturaProveedor)
        .filter(FacturaProveedor.empresa_id == empresa_id,
                FacturaProveedor.estado.in_(("pendiente", "pagada_parcial")))
        .all()
    )
    acc: dict[str, dict] = {}
    for f in facturas:
        saldo = saldo_pendiente(db, f)
        if saldo <= CERO:
            continue
        # proveedor_id puede venir como uuid.UUID (columna UUID nativa); normalizar
        # a str para que coincida con _nombres_proveedor y con el schema de salida.
        pid = str(f.proveedor_id)
        row = acc.setdefault(pid, {"facturas_abiertas": 0, "saldo_total": CERO})
        row["facturas_abiertas"] += 1
        row["saldo_total"] += saldo
    nombres = _nombres_proveedor(db, empresa_id, list(acc.keys()))
    return [
        {
            "proveedor_id": pid,
            "proveedor": nombres.get(pid, "—"),
            "facturas_abiertas": data["facturas_abiertas"],
            "saldo_total": data["saldo_total"],
        }
        for pid, data in acc.items()
    ]


def reporte_antiguedad(db: Session, empresa_id: str, corte: date | None = None) -> list[dict]:
    """Antigüedad de saldos por proveedor con una única fecha de corte para
    todos los cálculos (evita inconsistencias). Buckets sobre días vencidos:
    por_vencer (vence después del corte), 0-30, 31-60, 61-90, +90."""
    corte = corte or date.today()
    facturas = (
        db.query(FacturaProveedor)
        .filter(FacturaProveedor.empresa_id == empresa_id,
                FacturaProveedor.estado.in_(("pendiente", "pagada_parcial")))
        .all()
    )
    acc: dict[str, dict] = {}
    for f in facturas:
        saldo = saldo_pendiente(db, f)
        if saldo <= CERO:
            continue
        pid = str(f.proveedor_id)
        row = acc.setdefault(pid, {
            "por_vencer": CERO, "d_0_30": CERO, "d_31_60": CERO,
            "d_61_90": CERO, "d_mas_90": CERO, "total": CERO,
        })
        dias = (corte - f.fecha_vencimiento).days
        if dias < 0:
            row["por_vencer"] += saldo
        elif dias <= 30:
            row["d_0_30"] += saldo
        elif dias <= 60:
            row["d_31_60"] += saldo
        elif dias <= 90:
            row["d_61_90"] += saldo
        else:
            row["d_mas_90"] += saldo
        row["total"] += saldo
    nombres = _nombres_proveedor(db, empresa_id, list(acc.keys()))
    return [{"proveedor_id": pid, "proveedor": nombres.get(pid, "—"), **data}
            for pid, data in acc.items()]


# ── Helpers internos ─────────────────────────────────────────────────────────
def _moneda_empresa(db: Session, empresa_id: str) -> str:
    from app.models.empresa import Empresa
    emp = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    return getattr(emp, "moneda_funcional", None) or "PEN"


def _nombres_proveedor(db: Session, empresa_id: str, ids: list[str]) -> dict[str, str]:
    if not ids:
        return {}
    filas = (
        db.query(Proveedor.id, Proveedor.razon_social)
        .filter(Proveedor.empresa_id == empresa_id, Proveedor.id.in_(ids))
        .all()
    )
    return {str(i): n for i, n in filas}
