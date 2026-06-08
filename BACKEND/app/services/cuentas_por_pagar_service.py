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
    """Total de la factura menos la suma de aplicaciones de pago. Una factura
    anulada no tiene saldo exigible."""
    if factura.estado == "anulada":
        return CERO
    aplicado = (
        db.query(func.coalesce(func.sum(AplicacionPagoProveedor.monto_aplicado), 0))
        .filter(AplicacionPagoProveedor.factura_id == factura.id)
        .scalar()
    ) or 0
    return _d(factura.total) - _d(aplicado)


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

    factura = FacturaProveedor(
        empresa_id=empresa_id,
        proveedor_id=datos.proveedor_id,
        orden_compra_id=datos.orden_compra_id,
        numero_documento=datos.numero_documento,
        tipo_documento=datos.tipo_documento,
        fecha_emision=datos.fecha_emision,
        fecha_vencimiento=datos.fecha_vencimiento,
        moneda=moneda,
        subtotal=subtotal,
        igv=igv,
        total=total,
        estado="pendiente",
    )
    db.add(factura)
    db.flush()  # obtiene factura.id sin confirmar

    # Asiento: Db Compras (+ IGV) / Cr Por pagar — sin commit (lo hace esta fn).
    # La cuenta de IGV crédito fiscal la resuelve el servicio tributario (Fase 6),
    # por configuración — no por código fijo.
    from app.services import tributario_service as tributario
    lineas = [LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_COMPRAS).id, debito=subtotal)]
    if igv > CERO:
        lineas.append(LineaAsiento(cuenta_id=tributario.cuenta_igv(db, empresa_id, "credito_fiscal").id, debito=igv))
    lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_POR_PAGAR).id, credito=total))

    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=datos.fecha_emision,
            descripcion=f"Factura {datos.tipo_documento} {datos.numero_documento}",
            origen="compras", lineas=lineas, referencia_id=factura.id,
            creado_por_id=creado_por_id, commit=False,
        )
        factura.asiento_id = asiento.id
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
        if f.proveedor_id != datos.proveedor_id:
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

    cuenta_origen = _cuenta(db, empresa_id, MEDIO_A_CUENTA[datos.medio_pago])

    pago = PagoProveedor(
        empresa_id=empresa_id, proveedor_id=datos.proveedor_id,
        fecha_pago=datos.fecha_pago, monto=monto_total,
        medio_pago=datos.medio_pago, referencia=datos.referencia,
    )
    db.add(pago)
    db.flush()

    for f, aplicado, _saldo_nuevo in facturas_estado:
        db.add(AplicacionPagoProveedor(pago_id=pago.id, factura_id=f.id, monto_aplicado=aplicado))

    lineas = [
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_POR_PAGAR).id, debito=monto_total),
        LineaAsiento(cuenta_id=cuenta_origen.id, credito=monto_total),
    ]
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
