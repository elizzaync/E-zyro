"""
Servicio de Cuentas por Cobrar — AR (Fase 4). Espejo simétrico de AP.

Mapeo contable (Fase 0), cuentas de DETALLE del PCGE:
  Emitir comprobante (crédito): Db 121 Por cobrar
                                 Cr 7011 Ventas (+ Cr 40111 IGV débito fiscal)
  Emitir comprobante (contado): Db 101/104 Caja/Bancos  (resto igual)
  Registrar cobro             : Db 101/104 Caja/Bancos
                                 Cr 121 Por cobrar
  Anular comprobante          : asiento de REVERSIÓN del original.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable, AsientoContable, AsientoLinea
from app.models.cuentas_por_cobrar import (
    FacturaCliente, CobroCliente, AplicacionCobroCliente,
)
from app.models.cliente import Cliente
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")

CTA_POR_COBRAR  = "121"    # Facturas, boletas y otros comprobantes por cobrar
CTA_VENTAS      = "7011"   # Ventas - mercaderías terceros (detalle)
CTA_IGV_DEBITO  = "40111"  # IGV - cuenta propia (débito fiscal en ventas)
CTA_CAJA        = "101"
CTA_BANCOS      = "104"

MEDIO_A_CUENTA = {"efectivo": CTA_CAJA, "transferencia": CTA_BANCOS, "cheque": CTA_BANCOS}


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Decimal("0.01"))


def _cuenta(db: Session, empresa_id: str, codigo: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == codigo)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422,
                            detail=f"Falta la cuenta contable {codigo} en el plan de la empresa.")
    return c


def _cliente(db: Session, empresa_id: str, cliente_id: str) -> Cliente:
    c = db.query(Cliente).filter(Cliente.id == cliente_id, Cliente.empresa_id == empresa_id).first()
    if c is None:
        raise HTTPException(status_code=422, detail="El cliente no existe en la empresa.")
    return c


def get_factura(db: Session, empresa_id: str, factura_id: str) -> FacturaCliente:
    f = (
        db.query(FacturaCliente)
        .filter(FacturaCliente.id == factura_id, FacturaCliente.empresa_id == empresa_id)
        .first()
    )
    if f is None:
        raise HTTPException(status_code=404, detail="Comprobante no encontrado.")
    return f


def saldo_pendiente(db: Session, factura: FacturaCliente) -> Decimal:
    """Saldo por cobrar = total − cobros aplicados. Una factura anulada o una
    venta al contado (cobrada en la propia emisión, sin aplicaciones) no tienen
    saldo exigible."""
    if factura.estado in ("anulada", "cobrada"):
        return CERO
    aplicado = (
        db.query(func.coalesce(func.sum(AplicacionCobroCliente.monto_aplicado), 0))
        .filter(AplicacionCobroCliente.factura_id == factura.id)
        .scalar()
    ) or 0
    return _d(factura.total) - _d(aplicado)


def _estado_por_saldo(total: Decimal, saldo: Decimal) -> str:
    if saldo <= CERO:
        return "cobrada"
    if saldo < total:
        return "cobrada_parcial"
    return "pendiente"


# ── Emitir comprobante ───────────────────────────────────────────────────────
def emitir_comprobante(db: Session, empresa_id: str, datos, creado_por_id: str | None = None) -> FacturaCliente:
    _cliente(db, empresa_id, datos.cliente_id)

    subtotal = _d(datos.subtotal)
    igv = _d(datos.igv)
    total = subtotal + igv

    dup = (
        db.query(FacturaCliente)
        .filter(FacturaCliente.empresa_id == empresa_id,
                FacturaCliente.tipo_documento == datos.tipo_documento,
                FacturaCliente.numero_documento == datos.numero_documento)
        .first()
    )
    if dup:
        raise HTTPException(status_code=409, detail="Ya existe un comprobante con ese tipo y número.")

    moneda = datos.moneda or _moneda_empresa(db, empresa_id)
    al_contado = bool(getattr(datos, "al_contado", False))

    factura = FacturaCliente(
        empresa_id=empresa_id, cliente_id=datos.cliente_id, proyecto_id=datos.proyecto_id,
        proyecto_servicio_id=getattr(datos, "proyecto_servicio_id", None),
        numero_documento=datos.numero_documento, tipo_documento=datos.tipo_documento,
        fecha_emision=datos.fecha_emision, fecha_vencimiento=datos.fecha_vencimiento,
        moneda=moneda, subtotal=subtotal, igv=igv, total=total,
        estado=("cobrada" if al_contado else "pendiente"),
    )
    db.add(factura)
    db.flush()

    # Db cargo (121 a crédito, o caja al contado) / Cr ventas (+IGV)
    if al_contado:
        cuenta_cargo = _cuenta(db, empresa_id, CTA_CAJA)
    else:
        cuenta_cargo = _cuenta(db, empresa_id, CTA_POR_COBRAR)
    from app.services import tributario_service as tributario
    lineas = [LineaAsiento(cuenta_id=cuenta_cargo.id, debito=total)]
    lineas.append(LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_VENTAS).id, credito=subtotal))
    if igv > CERO:
        # Cuenta de IGV débito fiscal resuelta por configuración (Fase 6).
        lineas.append(LineaAsiento(cuenta_id=tributario.cuenta_igv(db, empresa_id, "debito_fiscal").id, credito=igv))

    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=datos.fecha_emision,
            descripcion=f"Comprobante {datos.tipo_documento} {datos.numero_documento}",
            origen="ventas", lineas=lineas, referencia_id=factura.id,
            creado_por_id=creado_por_id, commit=False,
        )
        factura.asiento_id = asiento.id
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo emitir el comprobante: {exc}") from exc

    db.refresh(factura)
    return factura


# ── Registrar cobro ──────────────────────────────────────────────────────────
def registrar_cobro(db: Session, empresa_id: str, datos, creado_por_id: str | None = None) -> CobroCliente:
    _cliente(db, empresa_id, datos.cliente_id)
    if not datos.aplicaciones:
        raise HTTPException(status_code=422, detail="El cobro debe aplicarse al menos a una factura.")

    monto_total = CERO
    facturas_estado: list[tuple[FacturaCliente, Decimal, Decimal]] = []
    for ap in datos.aplicaciones:
        f = get_factura(db, empresa_id, ap.factura_id)
        # f.cliente_id es uuid.UUID (columna UUID nativa) y datos.cliente_id es
        # str: comparar sin normalizar da SIEMPRE True y rechaza todo cobro.
        if str(f.cliente_id) != str(datos.cliente_id):
            raise HTTPException(status_code=422, detail=f"El comprobante {f.numero_documento} no es del cliente indicado.")
        if f.estado == "anulada":
            raise HTTPException(status_code=422, detail=f"El comprobante {f.numero_documento} está anulado.")
        aplicado = _d(ap.monto_aplicado)
        saldo = saldo_pendiente(db, f)
        if aplicado > saldo:
            raise HTTPException(
                status_code=422,
                detail=f"El monto aplicado ({aplicado}) excede el saldo pendiente ({saldo}) "
                       f"del comprobante {f.numero_documento}.",
            )
        facturas_estado.append((f, aplicado, saldo - aplicado))
        monto_total += aplicado

    if monto_total <= CERO:
        raise HTTPException(status_code=422, detail="El monto del cobro debe ser mayor que 0.")

    cuenta_destino = _cuenta(db, empresa_id, MEDIO_A_CUENTA[datos.medio_pago])

    cobro = CobroCliente(
        empresa_id=empresa_id, cliente_id=datos.cliente_id, fecha_cobro=datos.fecha_cobro,
        monto=monto_total, medio_pago=datos.medio_pago, referencia=datos.referencia,
    )
    db.add(cobro)
    db.flush()

    for f, aplicado, _saldo_nuevo in facturas_estado:
        db.add(AplicacionCobroCliente(cobro_id=cobro.id, factura_id=f.id, monto_aplicado=aplicado))

    lineas = [
        LineaAsiento(cuenta_id=cuenta_destino.id, debito=monto_total),
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_POR_COBRAR).id, credito=monto_total),
    ]
    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=datos.fecha_cobro,
            descripcion=f"Cobro de cliente ({datos.medio_pago})",
            origen="ventas", lineas=lineas, referencia_id=cobro.id,
            creado_por_id=creado_por_id, commit=False,
        )
        cobro.asiento_id = asiento.id
        for f, _aplicado, saldo_nuevo in facturas_estado:
            f.estado = _estado_por_saldo(_d(f.total), saldo_nuevo)
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo registrar el cobro: {exc}") from exc

    db.refresh(cobro)
    return cobro


# ── Anular comprobante ───────────────────────────────────────────────────────
def anular_comprobante(db: Session, empresa_id: str, factura_id: str, creado_por_id: str | None = None) -> FacturaCliente:
    factura = get_factura(db, empresa_id, factura_id)
    if factura.estado == "anulada":
        raise HTTPException(status_code=409, detail="El comprobante ya está anulado.")

    aplicado = (
        db.query(func.coalesce(func.sum(AplicacionCobroCliente.monto_aplicado), 0))
        .filter(AplicacionCobroCliente.factura_id == factura.id)
        .scalar()
    ) or 0
    if _d(aplicado) > CERO:
        raise HTTPException(status_code=409,
                            detail="No se puede anular un comprobante con cobros aplicados; anule primero los cobros.")

    lineas_orig = (
        db.query(AsientoLinea).filter(AsientoLinea.asiento_id == factura.asiento_id).all()
    ) if factura.asiento_id else []
    if not lineas_orig:
        factura.estado = "anulada"
        db.commit()
        db.refresh(factura)
        return factura

    lineas_rev = [
        LineaAsiento(
            cuenta_id=str(l.cuenta_id), debito=_d(l.credito), credito=_d(l.debito),
            centro_costo_id=(str(l.centro_costo_id) if l.centro_costo_id else None),
            glosa="Reversión por anulación de comprobante",
        )
        for l in lineas_orig
    ]
    try:
        contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=factura.fecha_emision,
            descripcion=f"Anulación comprobante {factura.numero_documento}",
            origen="ventas", lineas=lineas_rev, referencia_id=factura.id,
            creado_por_id=creado_por_id, commit=False,
        )
        factura.estado = "anulada"
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo anular el comprobante: {exc}") from exc

    db.refresh(factura)
    return factura


# ── Reportes ─────────────────────────────────────────────────────────────────
def reporte_saldos(db: Session, empresa_id: str) -> list[dict]:
    facturas = (
        db.query(FacturaCliente)
        .filter(FacturaCliente.empresa_id == empresa_id,
                FacturaCliente.estado.in_(("pendiente", "cobrada_parcial")))
        .all()
    )
    acc: dict[str, dict] = {}
    for f in facturas:
        saldo = saldo_pendiente(db, f)
        if saldo <= CERO:
            continue
        # cliente_id puede venir como uuid.UUID (columna UUID nativa); normalizar
        # a str para que coincida con las claves de _nombres_cliente y con el schema.
        cid = str(f.cliente_id)
        row = acc.setdefault(cid, {"facturas_abiertas": 0, "saldo_total": CERO})
        row["facturas_abiertas"] += 1
        row["saldo_total"] += saldo
    nombres = _nombres_cliente(db, empresa_id, list(acc.keys()))
    return [{"cliente_id": cid, "cliente": nombres.get(cid, "—"),
             "facturas_abiertas": d["facturas_abiertas"], "saldo_total": d["saldo_total"]}
            for cid, d in acc.items()]


def reporte_antiguedad(db: Session, empresa_id: str, corte: date | None = None) -> list[dict]:
    corte = corte or date.today()
    facturas = (
        db.query(FacturaCliente)
        .filter(FacturaCliente.empresa_id == empresa_id,
                FacturaCliente.estado.in_(("pendiente", "cobrada_parcial")))
        .all()
    )
    acc: dict[str, dict] = {}
    for f in facturas:
        saldo = saldo_pendiente(db, f)
        if saldo <= CERO or f.fecha_vencimiento is None:
            continue
        cid = str(f.cliente_id)
        row = acc.setdefault(cid, {
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
    nombres = _nombres_cliente(db, empresa_id, list(acc.keys()))
    return [{"cliente_id": cid, "cliente": nombres.get(cid, "—"), **d} for cid, d in acc.items()]


def _moneda_empresa(db: Session, empresa_id: str) -> str:
    from app.models.empresa import Empresa
    emp = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    return getattr(emp, "moneda_funcional", None) or "PEN"


def _nombres_cliente(db: Session, empresa_id: str, ids: list[str]) -> dict[str, str]:
    if not ids:
        return {}
    filas = (
        db.query(Cliente.id, Cliente.razon_social)
        .filter(Cliente.empresa_id == empresa_id, Cliente.id.in_(ids))
        .all()
    )
    return {str(i): n for i, n in filas}
