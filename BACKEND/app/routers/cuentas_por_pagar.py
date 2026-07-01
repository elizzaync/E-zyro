"""
Router: /cuentas-por-pagar — AP (Fase 3 del módulo de finanzas).

Toda escritura contable pasa por cuentas_por_pagar_service → registrar_asiento
(no hay escritura directa de líneas). RBAC por (modulo='cxp', accion) y filtro
por la empresa del token en cada consulta.
"""
from __future__ import annotations

from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.cuentas_por_pagar import (
    FacturaProveedor, PagoProveedor, AplicacionPagoProveedor,
)
from ..models.contabilidad import CuentaContable
from ..schemas.cuentas_por_pagar import (
    FacturaCreate, FacturaOut, PagoCreate, PagoOut, AplicacionOut,
    SaldoProveedorOut, AntiguedadBucketOut,
)
from ..services import cuentas_por_pagar_service as cxp

router = APIRouter(prefix="/cuentas-por-pagar", tags=["cuentas-por-pagar"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


def _factura_out(db: Session, f: FacturaProveedor) -> FacturaOut:
    cuenta_gasto_id = str(f.cuenta_gasto_id) if f.cuenta_gasto_id else None
    cuenta_gasto_codigo = None
    if cuenta_gasto_id:
        c = db.query(CuentaContable.codigo).filter(CuentaContable.id == cuenta_gasto_id).first()
        cuenta_gasto_codigo = c[0] if c else None
    return FacturaOut(
        id=str(f.id), proveedor_id=str(f.proveedor_id),
        orden_compra_id=(str(f.orden_compra_id) if f.orden_compra_id else None),
        numero_documento=f.numero_documento, tipo_documento=f.tipo_documento,
        fecha_emision=f.fecha_emision, fecha_vencimiento=f.fecha_vencimiento,
        moneda=f.moneda, subtotal=f.subtotal, igv=f.igv, total=f.total,
        estado=f.estado, saldo_pendiente=cxp.saldo_pendiente(db, f),
        asiento_id=(str(f.asiento_id) if f.asiento_id else None),
        cuenta_gasto_id=cuenta_gasto_id, cuenta_gasto_codigo=cuenta_gasto_codigo,
        documento_afectado_id=(str(f.documento_afectado_id)
                               if f.documento_afectado_id else None),
    )


def _pago_out(db: Session, p: PagoProveedor) -> PagoOut:
    aplicaciones = (
        db.query(AplicacionPagoProveedor)
        .filter(AplicacionPagoProveedor.pago_id == p.id)
        .all()
    )
    return PagoOut(
        id=str(p.id), proveedor_id=str(p.proveedor_id), fecha_pago=p.fecha_pago,
        monto=p.monto, medio_pago=p.medio_pago, referencia=p.referencia,
        asiento_id=(str(p.asiento_id) if p.asiento_id else None),
        aplicaciones=[AplicacionOut(factura_id=str(a.factura_id), monto_aplicado=a.monto_aplicado)
                      for a in aplicaciones],
    )


# ── Facturas ─────────────────────────────────────────────────────────────────
@router.get("/facturas", response_model=List[FacturaOut])
def listar_facturas(
    proveedor_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    vence_hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "ver")
    q = db.query(FacturaProveedor).filter(FacturaProveedor.empresa_id == payload["empresa_id"])
    if proveedor_id:
        q = q.filter(FacturaProveedor.proveedor_id == proveedor_id)
    if estado:
        q = q.filter(FacturaProveedor.estado == estado)
    if vence_hasta:
        q = q.filter(FacturaProveedor.fecha_vencimiento <= vence_hasta)
    return [_factura_out(db, f) for f in q.order_by(FacturaProveedor.fecha_vencimiento).all()]


@router.post("/facturas", response_model=FacturaOut, status_code=201)
def registrar_factura(
    body: FacturaCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "registrar_factura")
    f = cxp.registrar_factura(db, payload["empresa_id"], body, _empleado_id(db, payload))
    return _factura_out(db, f)


@router.get("/facturas/{factura_id}", response_model=FacturaOut)
def obtener_factura(
    factura_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "ver")
    f = cxp.get_factura(db, payload["empresa_id"], factura_id)
    return _factura_out(db, f)


@router.post("/facturas/{factura_id}/anular", response_model=FacturaOut)
def anular_factura(
    factura_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "anular_factura")
    f = cxp.anular_factura(db, payload["empresa_id"], factura_id, _empleado_id(db, payload))
    return _factura_out(db, f)


# ── Pagos ────────────────────────────────────────────────────────────────────
@router.post("/pagos", response_model=PagoOut, status_code=201)
def registrar_pago(
    body: PagoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "registrar_pago")
    p = cxp.registrar_pago(db, payload["empresa_id"], body, _empleado_id(db, payload))
    return _pago_out(db, p)


@router.get("/pagos", response_model=List[PagoOut])
def listar_pagos(
    proveedor_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "ver")
    q = db.query(PagoProveedor).filter(PagoProveedor.empresa_id == payload["empresa_id"])
    if proveedor_id:
        q = q.filter(PagoProveedor.proveedor_id == proveedor_id)
    return [_pago_out(db, p) for p in q.order_by(PagoProveedor.fecha_pago.desc()).all()]


@router.get("/pagos/{pago_id}", response_model=PagoOut)
def obtener_pago(
    pago_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "ver")
    from fastapi import HTTPException
    p = (
        db.query(PagoProveedor)
        .filter(PagoProveedor.id == pago_id, PagoProveedor.empresa_id == payload["empresa_id"])
        .first()
    )
    if not p:
        raise HTTPException(status_code=404, detail="Pago no encontrado.")
    return _pago_out(db, p)


# ── Reportes ─────────────────────────────────────────────────────────────────
@router.get("/reporte-saldos", response_model=List[SaldoProveedorOut])
def reporte_saldos(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "ver")
    return [SaldoProveedorOut(**r) for r in cxp.reporte_saldos(db, payload["empresa_id"])]


@router.get("/reporte-antiguedad", response_model=List[AntiguedadBucketOut])
def reporte_antiguedad(
    corte: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxp", "ver")
    return [AntiguedadBucketOut(**r) for r in cxp.reporte_antiguedad(db, payload["empresa_id"], corte)]
