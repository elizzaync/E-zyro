"""
Router: /cuentas-por-cobrar — AR (Fase 4). Simétrico a /cuentas-por-pagar.

Toda escritura contable pasa por cuentas_por_cobrar_service → registrar_asiento.
RBAC por (modulo='cxc', accion) y filtro por la empresa del token.
"""
from __future__ import annotations

from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.cuentas_por_cobrar import (
    FacturaCliente, CobroCliente, AplicacionCobroCliente,
)
from ..models.proyecto_servicio import ProyectoServicio
from ..models.proyecto import Proyecto
from ..models.cliente import Cliente
from ..schemas.cuentas_por_cobrar import (
    ComprobanteCreate, ComprobanteOut, CobroCreate, CobroOut, AplicacionCobroOut,
    SaldoClienteOut, AntiguedadClienteOut,
    FacturarServicioIn, ServicioFacturableOut,
)
from ..services import cuentas_por_cobrar_service as cxc

router = APIRouter(prefix="/cuentas-por-cobrar", tags=["cuentas-por-cobrar"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


def _factura_out(db: Session, f: FacturaCliente) -> ComprobanteOut:
    return ComprobanteOut(
        id=str(f.id), cliente_id=str(f.cliente_id),
        proyecto_id=(str(f.proyecto_id) if f.proyecto_id else None),
        numero_documento=f.numero_documento, tipo_documento=f.tipo_documento,
        fecha_emision=f.fecha_emision, fecha_vencimiento=f.fecha_vencimiento,
        moneda=f.moneda, subtotal=f.subtotal, igv=f.igv, total=f.total,
        estado=f.estado, saldo_pendiente=cxc.saldo_pendiente(db, f),
        asiento_id=(str(f.asiento_id) if f.asiento_id else None),
        documento_afectado_id=(str(f.documento_afectado_id)
                               if f.documento_afectado_id else None),
    )


def _cobro_out(db: Session, c: CobroCliente) -> CobroOut:
    aplicaciones = (
        db.query(AplicacionCobroCliente)
        .filter(AplicacionCobroCliente.cobro_id == c.id).all()
    )
    return CobroOut(
        id=str(c.id), cliente_id=str(c.cliente_id), fecha_cobro=c.fecha_cobro,
        monto=c.monto, medio_pago=c.medio_pago, referencia=c.referencia,
        asiento_id=(str(c.asiento_id) if c.asiento_id else None),
        aplicaciones=[AplicacionCobroOut(factura_id=str(a.factura_id), monto_aplicado=a.monto_aplicado)
                      for a in aplicaciones],
    )


# ── Comprobantes ─────────────────────────────────────────────────────────────
@router.get("/facturas", response_model=List[ComprobanteOut])
def listar_facturas(
    cliente_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    vence_hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    q = db.query(FacturaCliente).filter(FacturaCliente.empresa_id == payload["empresa_id"])
    if cliente_id:
        q = q.filter(FacturaCliente.cliente_id == cliente_id)
    if estado:
        q = q.filter(FacturaCliente.estado == estado)
    if vence_hasta:
        q = q.filter(FacturaCliente.fecha_vencimiento <= vence_hasta)
    return [_factura_out(db, f) for f in q.order_by(FacturaCliente.fecha_emision).all()]


@router.post("/facturas", response_model=ComprobanteOut, status_code=201)
def emitir_comprobante(
    body: ComprobanteCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "emitir_comprobante")
    f = cxc.emitir_comprobante(db, payload["empresa_id"], body, _empleado_id(db, payload))
    return _factura_out(db, f)


@router.get("/facturas/{factura_id}", response_model=ComprobanteOut)
def obtener_factura(
    factura_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    return _factura_out(db, cxc.get_factura(db, payload["empresa_id"], factura_id))


@router.post("/facturas/{factura_id}/anular", response_model=ComprobanteOut)
def anular_comprobante(
    factura_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "anular_comprobante")
    f = cxc.anular_comprobante(db, payload["empresa_id"], factura_id, _empleado_id(db, payload))
    return _factura_out(db, f)


# ── Facturación de servicios (Servicios → CxC) ───────────────────────────────
@router.get("/servicios-facturables", response_model=List[ServicioFacturableOut])
def servicios_facturables(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Servicios COMPLETADOS que aún no tienen una factura vigente (no anulada).
    Insumo de la acción 'Facturar servicio'."""
    exigir_permiso(db, payload, "cxc", "ver")
    empresa_id = payload["empresa_id"]

    # IDs de servicios ya facturados con comprobante vigente (no anulado).
    facturados = {
        str(sid) for (sid,) in db.query(FacturaCliente.proyecto_servicio_id).filter(
            FacturaCliente.empresa_id == empresa_id,
            FacturaCliente.proyecto_servicio_id.isnot(None),
            FacturaCliente.estado != "anulada",
        ).all()
    }

    filas = (
        db.query(ProyectoServicio, Proyecto, Cliente)
        .join(Proyecto, Proyecto.id == ProyectoServicio.proyecto_id)
        .outerjoin(Cliente, Cliente.id == Proyecto.cliente_id)
        .filter(ProyectoServicio.empresa_id == empresa_id,
                ProyectoServicio.estado == "Completado")
        .order_by(ProyectoServicio.updated_at.desc())
        .all()
    )
    out = []
    for ps, proy, cli in filas:
        if str(ps.id) in facturados:
            continue
        out.append(ServicioFacturableOut(
            servicio_id=str(ps.id), servicio_nombre=ps.nombre or "Servicio",
            proyecto_id=str(proy.id) if proy else None,
            proyecto_nombre=(proy.nombre_proyecto if proy else None),
            cliente_id=str(cli.id) if cli else None,
            cliente_nombre=(cli.razon_social if cli else None),
            nro_documento_cliente=ps.nro_documento,
        ))
    return out


@router.post("/facturar-servicio", response_model=ComprobanteOut, status_code=201)
def facturar_servicio(
    body: FacturarServicioIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Emite la factura de venta de un servicio completado. Deriva el cliente del
    proyecto, valida que el servicio esté Completado y sin factura vigente, y
    genera la CxC + asiento (Db 121/Cr 7011+40111) vía emitir_comprobante."""
    exigir_permiso(db, payload, "cxc", "emitir_comprobante")
    empresa_id = payload["empresa_id"]

    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == body.servicio_id,
        ProyectoServicio.empresa_id == empresa_id).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")
    if ps.estado != "Completado":
        raise HTTPException(status_code=409, detail="Solo se factura un servicio Completado.")

    ya = db.query(FacturaCliente).filter(
        FacturaCliente.empresa_id == empresa_id,
        FacturaCliente.proyecto_servicio_id == ps.id,
        FacturaCliente.estado != "anulada").first()
    if ya:
        raise HTTPException(status_code=409, detail="El servicio ya tiene una factura vigente.")

    proy = db.query(Proyecto).filter(Proyecto.id == ps.proyecto_id).first()
    if not proy or not proy.cliente_id:
        raise HTTPException(status_code=422,
                            detail="El proyecto del servicio no tiene cliente asignado.")

    datos = ComprobanteCreate(
        cliente_id=str(proy.cliente_id),
        numero_documento=body.numero_documento,
        tipo_documento=body.tipo_documento,
        fecha_emision=body.fecha_emision,
        fecha_vencimiento=body.fecha_vencimiento,
        subtotal=body.subtotal,
        igv=body.igv,
        moneda=body.moneda,
        proyecto_id=str(ps.proyecto_id),
        proyecto_servicio_id=str(ps.id),
        al_contado=body.al_contado,
    )
    f = cxc.emitir_comprobante(db, empresa_id, datos, _empleado_id(db, payload))
    return _factura_out(db, f)


# ── Cobros ───────────────────────────────────────────────────────────────────
@router.post("/cobros", response_model=CobroOut, status_code=201)
def registrar_cobro(
    body: CobroCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "registrar_cobro")
    c = cxc.registrar_cobro(db, payload["empresa_id"], body, _empleado_id(db, payload))
    return _cobro_out(db, c)


@router.get("/cobros", response_model=List[CobroOut])
def listar_cobros(
    cliente_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    q = db.query(CobroCliente).filter(CobroCliente.empresa_id == payload["empresa_id"])
    if cliente_id:
        q = q.filter(CobroCliente.cliente_id == cliente_id)
    return [_cobro_out(db, c) for c in q.order_by(CobroCliente.fecha_cobro.desc()).all()]


@router.get("/cobros/{cobro_id}", response_model=CobroOut)
def obtener_cobro(
    cobro_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    c = (
        db.query(CobroCliente)
        .filter(CobroCliente.id == cobro_id, CobroCliente.empresa_id == payload["empresa_id"])
        .first()
    )
    if not c:
        raise HTTPException(status_code=404, detail="Cobro no encontrado.")
    return _cobro_out(db, c)


# ── Reportes ─────────────────────────────────────────────────────────────────
@router.get("/reporte-saldos", response_model=List[SaldoClienteOut])
def reporte_saldos(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    return [SaldoClienteOut(**r) for r in cxc.reporte_saldos(db, payload["empresa_id"])]


@router.get("/reporte-antiguedad", response_model=List[AntiguedadClienteOut])
def reporte_antiguedad(
    corte: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    return [AntiguedadClienteOut(**r) for r in cxc.reporte_antiguedad(db, payload["empresa_id"], corte)]
