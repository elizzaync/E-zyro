"""
Router: /cotizaciones — ciclo comercial (pre-venta).

borrador → enviada → aceptada|rechazada|vencida → convertida (proyecto).
RBAC: (cotizaciones, ver|gestionar). La conversión crea ContratoComercial +
Proyecto reutilizando el correlativo de orden de trabajo de operaciones.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.cliente import Cliente
from ..models.contrato_comercial import ContratoComercial
from ..models.cotizacion import Cotizacion, CotizacionItem
from ..models.proyecto import Proyecto
from ..schemas.cotizacion import (
    ConvertirIn, CotizacionCreate, CotizacionOut, CotizacionUpdate,
    ItemOut, ResolverIn,
)
from ..services import tributario_service
from ..services.pdf_docs import generar_cotizacion_pdf

router = APIRouter(prefix="/cotizaciones", tags=["cotizaciones"])

_D2 = Decimal("0.01")


def _get(db: Session, empresa_id: str, cot_id: str) -> Cotizacion:
    c = db.query(Cotizacion).filter(
        Cotizacion.id == cot_id, Cotizacion.empresa_id == empresa_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Cotización no encontrada")
    return c


def _marcar_vencida(db: Session, c: Cotizacion) -> None:
    """Vence en lectura: enviada + fecha pasada → vencida (sin job aparte)."""
    if c.estado == "enviada" and \
            c.fecha_emision + timedelta(days=c.validez_dias) < date.today():
        c.estado = "vencida"
        db.commit()


def _out(db: Session, c: Cotizacion) -> CotizacionOut:
    cli = db.query(Cliente).filter(Cliente.id == c.cliente_id).first()
    items = (
        db.query(CotizacionItem)
        .filter(CotizacionItem.cotizacion_id == c.id)
        .order_by(CotizacionItem.orden).all()
    )
    return CotizacionOut(
        id=str(c.id), numero=c.numero, cliente_id=str(c.cliente_id),
        cliente=(cli.razon_social if cli else "—"),
        ruc=(cli.ruc if cli else None),
        fecha_emision=c.fecha_emision, validez_dias=c.validez_dias,
        vence=c.fecha_emision + timedelta(days=c.validez_dias),
        estado=c.estado, moneda=c.moneda,
        subtotal=c.subtotal, igv=c.igv, total=c.total,
        condiciones_pago=c.condiciones_pago, notas=c.notas,
        proyecto_id=(str(c.proyecto_id) if c.proyecto_id else None),
        contrato_comercial_id=(str(c.contrato_comercial_id)
                               if c.contrato_comercial_id else None),
        resuelto_via=c.resuelto_via, fecha_resolucion=c.fecha_resolucion,
        items=[ItemOut(id=str(i.id), descripcion=i.descripcion, unidad=i.unidad,
                       cantidad=i.cantidad, precio_unitario=i.precio_unitario,
                       total=i.total) for i in items],
    )


def _siguiente_numero(db: Session, empresa_id: str) -> str:
    anio = date.today().year
    prefijo = f"COT-{anio}-"
    usados = {
        n for (n,) in db.query(Cotizacion.numero).filter(
            Cotizacion.empresa_id == empresa_id,
            Cotizacion.numero.like(f"{prefijo}%"))
    }
    i = 1
    while f"{prefijo}{i:04d}" in usados:
        i += 1
    return f"{prefijo}{i:04d}"


def _aplicar_items(db: Session, c: Cotizacion, items, empresa_id: str) -> None:
    """Reemplaza los items y recalcula subtotal/igv/total (IGV de tributario)."""
    db.query(CotizacionItem).filter(CotizacionItem.cotizacion_id == c.id).delete()
    subtotal = Decimal("0")
    for orden, it in enumerate(items, start=1):
        total_item = (it.cantidad * it.precio_unitario).quantize(_D2)
        subtotal += total_item
        db.add(CotizacionItem(
            cotizacion_id=c.id, descripcion=it.descripcion, unidad=it.unidad,
            cantidad=it.cantidad, precio_unitario=it.precio_unitario,
            total=total_item, orden=orden,
        ))
    tasa = tributario_service.tasa_igv(db, empresa_id) / Decimal("100")
    c.subtotal = subtotal.quantize(_D2)
    c.igv = (subtotal * tasa).quantize(_D2)
    c.total = (c.subtotal + c.igv).quantize(_D2)


@router.get("", response_model=List[CotizacionOut])
def listar(
    estado: Optional[str] = Query(None),
    cliente_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cotizaciones", "ver")
    q = db.query(Cotizacion).filter(Cotizacion.empresa_id == payload["empresa_id"])
    if cliente_id:
        q = q.filter(Cotizacion.cliente_id == cliente_id)
    cots = q.order_by(Cotizacion.created_at.desc()).all()
    for c in cots:
        _marcar_vencida(db, c)
    if estado:
        cots = [c for c in cots if c.estado == estado]
    return [_out(db, c) for c in cots]


@router.post("", response_model=CotizacionOut, status_code=201)
def crear(
    body: CotizacionCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cotizaciones", "gestionar")
    empresa_id = payload["empresa_id"]

    cliente_id = body.cliente_id
    if not cliente_id:
        if not body.cliente_nuevo:
            raise HTTPException(status_code=422,
                                detail="Indica cliente_id o cliente_nuevo.")
        cli = Cliente(empresa_id=empresa_id,
                      razon_social=body.cliente_nuevo.razon_social.strip(),
                      ruc=(body.cliente_nuevo.ruc or None), activo=True)
        db.add(cli)
        db.flush()
        cliente_id = str(cli.id)
    else:
        existe = db.query(Cliente).filter(
            Cliente.id == cliente_id, Cliente.empresa_id == empresa_id).first()
        if not existe:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")

    c = Cotizacion(
        empresa_id=empresa_id, cliente_id=cliente_id,
        numero=_siguiente_numero(db, empresa_id),
        fecha_emision=body.fecha_emision or date.today(),
        validez_dias=body.validez_dias, moneda=body.moneda,
        condiciones_pago=body.condiciones_pago, notas=body.notas,
        estado="borrador", creado_por_id=payload.get("id"),
    )
    db.add(c)
    db.flush()
    _aplicar_items(db, c, body.items, empresa_id)
    db.commit()
    db.refresh(c)
    return _out(db, c)


@router.get("/{cot_id}", response_model=CotizacionOut)
def obtener(
    cot_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cotizaciones", "ver")
    c = _get(db, payload["empresa_id"], cot_id)
    _marcar_vencida(db, c)
    return _out(db, c)


@router.put("/{cot_id}", response_model=CotizacionOut)
def editar(
    cot_id: str, body: CotizacionUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cotizaciones", "gestionar")
    c = _get(db, payload["empresa_id"], cot_id)
    if c.estado != "borrador":
        raise HTTPException(status_code=409, detail="Solo se edita un borrador.")
    if body.validez_dias is not None:
        c.validez_dias = body.validez_dias
    if body.condiciones_pago is not None:
        c.condiciones_pago = body.condiciones_pago
    if body.notas is not None:
        c.notas = body.notas
    if body.items is not None:
        if not body.items:
            raise HTTPException(status_code=422, detail="La cotización necesita ítems.")
        _aplicar_items(db, c, body.items, payload["empresa_id"])
    db.commit()
    db.refresh(c)
    return _out(db, c)


@router.delete("/{cot_id}", status_code=204)
def eliminar_borrador(
    cot_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cotizaciones", "gestionar")
    c = _get(db, payload["empresa_id"], cot_id)
    if c.estado != "borrador":
        raise HTTPException(status_code=409, detail="Solo se elimina un borrador.")
    db.query(CotizacionItem).filter(CotizacionItem.cotizacion_id == c.id).delete()
    db.delete(c)
    db.commit()


@router.post("/{cot_id}/enviar", response_model=CotizacionOut)
def enviar(
    cot_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """borrador → enviada. El PDF se descarga con GET /{id}/pdf."""
    exigir_permiso(db, payload, "cotizaciones", "gestionar")
    c = _get(db, payload["empresa_id"], cot_id)
    if c.estado != "borrador":
        raise HTTPException(status_code=409, detail="Solo se envía un borrador.")
    c.estado = "enviada"
    db.commit()
    db.refresh(c)
    return _out(db, c)


@router.post("/{cot_id}/resolver", response_model=CotizacionOut)
def resolver(
    cot_id: str, body: ResolverIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """enviada → aceptada | rechazada (registro interno de la respuesta)."""
    exigir_permiso(db, payload, "cotizaciones", "gestionar")
    c = _get(db, payload["empresa_id"], cot_id)
    _marcar_vencida(db, c)
    if c.estado != "enviada":
        raise HTTPException(status_code=409,
                            detail=f"Solo se resuelve una enviada (actual: {c.estado}).")
    c.estado = body.estado
    c.resuelto_via = "interno"
    c.fecha_resolucion = datetime.utcnow()
    db.commit()
    db.refresh(c)
    return _out(db, c)


@router.post("/{cot_id}/convertir", response_model=CotizacionOut)
def convertir(
    cot_id: str, body: ConvertirIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """aceptada → convertida: crea ContratoComercial + Proyecto enlazados."""
    from .operaciones import _siguiente_orden_trabajo

    exigir_permiso(db, payload, "cotizaciones", "gestionar")
    empresa_id = payload["empresa_id"]
    c = _get(db, empresa_id, cot_id)
    if c.estado != "aceptada":
        raise HTTPException(status_code=409,
                            detail="Solo se convierte una cotización aceptada.")

    contrato = ContratoComercial(
        cliente_id=str(c.cliente_id), empresa_id=empresa_id,
        numero_contrato=c.numero.replace("COT-", "CTR-"),
        fecha_inicio=date.today(), monto_total=c.total,
        estado="vigente",
        descripcion=f"Generado desde la cotización {c.numero}",
        creado_por=payload["id"],
    )
    db.add(contrato)
    db.flush()

    cli = db.query(Cliente).filter(Cliente.id == c.cliente_id).first()
    nombre = body.nombre_proyecto or \
        f"Proyecto {c.numero} — {cli.razon_social if cli else ''}".strip(" —")
    proyecto = Proyecto(
        empresa_id=empresa_id, cliente_id=str(c.cliente_id),
        contrato_comercial_id=str(contrato.id),
        orden_trabajo=_siguiente_orden_trabajo(db, empresa_id),
        jefe_operaciones_id=body.jefe_operaciones_id,
        nombre_proyecto=nombre, estado="Pendiente",
        fecha_inicio=date.today(),
    )
    db.add(proyecto)
    db.flush()

    c.estado = "convertida"
    c.proyecto_id = str(proyecto.id)
    c.contrato_comercial_id = str(contrato.id)
    db.commit()
    db.refresh(c)
    return _out(db, c)


@router.get("/{cot_id}/pdf")
def pdf(
    cot_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cotizaciones", "ver")
    c = _get(db, payload["empresa_id"], cot_id)
    data = armar_data_pdf(db, c)
    return Response(
        content=generar_cotizacion_pdf(data),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{c.numero}.pdf"'},
    )


def armar_data_pdf(db: Session, c: Cotizacion) -> dict:
    """Data del PDF; compartida con el portal del cliente."""
    from ..models.empresa import Empresa

    emp = db.query(Empresa).filter(Empresa.id == c.empresa_id).first()
    cli = db.query(Cliente).filter(Cliente.id == c.cliente_id).first()
    items = (
        db.query(CotizacionItem)
        .filter(CotizacionItem.cotizacion_id == c.id)
        .order_by(CotizacionItem.orden).all()
    )
    return {
        "empresa": emp.razon_social if emp else "",
        "empresa_ruc": emp.ruc if emp else "",
        "empresa_direccion": (emp.direccion or "") if emp else "",
        "numero": c.numero,
        "fecha": c.fecha_emision.isoformat(),
        "vence": (c.fecha_emision + timedelta(days=c.validez_dias)).isoformat(),
        "cliente": cli.razon_social if cli else "",
        "cliente_ruc": (cli.ruc or "") if cli else "",
        "moneda": c.moneda,
        "items": [{
            "descripcion": i.descripcion, "unidad": i.unidad,
            "cantidad": i.cantidad, "precio_unitario": i.precio_unitario,
            "total": i.total,
        } for i in items],
        "subtotal": c.subtotal, "igv": c.igv, "total": c.total,
        "condiciones_pago": c.condiciones_pago or "",
        "notas": c.notas or "",
    }
