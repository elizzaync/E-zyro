"""
Router: /compras
Gestión de proveedores, órdenes de compra y recepción de mercadería (Logística Fase 5).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime, date as _date
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token, es_superadmin
from ..db.database import get_db

from ..models.proveedor import Proveedor
from ..models.orden_compra import OrdenCompra, DetalleCompra
from ..models.recepcion_compra import RecepcionCompra, RecepcionDetalle
from ..models.material import Material, Stock
from ..models.almacen import Almacen
from ..models.empleado import Empleado
from ..models.movimiento_inventario import MovimientoInventario

from ..schemas.compras import (
    ProveedorOut,
    ProveedorBody,
    CrearOrdenCompraBody,
    OrdenCompraOut,
    DetalleCompraOut,
    CambiarEstadoOrdenBody,
    RecibirOrdenBody,
)

router = APIRouter(prefix="/compras", tags=["compras"])


def _puede_gestionar(payload: dict) -> bool:
    if es_superadmin(payload):
        return True
    return "logist" in (payload.get("rol") or "").lower()


def _guard(payload: dict):
    if not _puede_gestionar(payload):
        raise HTTPException(status_code=403, detail="No tienes acceso a la gestión de logística")


def _parse_date(s: str | None):
    if not s:
        return None
    try:
        return _date.fromisoformat(s)
    except Exception:
        return None


# ══════════════════════════════════════════════════════════════════
# Proveedores
# ══════════════════════════════════════════════════════════════════

@router.get("/proveedores", response_model=List[ProveedorOut])
def listar_proveedores(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)
    rows = (
        db.query(Proveedor)
        .filter(Proveedor.empresa_id == empresa_id, Proveedor.activo == True)
        .order_by(Proveedor.razon_social.asc())
        .all()
    )
    return [
        ProveedorOut(
            id=str(p.id),
            razon_social=p.razon_social,
            ruc=p.ruc,
            contacto=p.contacto,
            email=p.email,
            telefono=p.telefono,
            direccion=p.direccion,
        )
        for p in rows
    ]


@router.post("/proveedores", status_code=status.HTTP_201_CREATED)
def crear_proveedor(
    body:    ProveedorBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)
    if not body.razon_social.strip():
        raise HTTPException(status_code=422, detail="La razón social es obligatoria")

    p = Proveedor(
        id           = str(_uuid.uuid4()),
        empresa_id   = empresa_id,
        razon_social = body.razon_social.strip(),
        ruc          = body.ruc,
        contacto     = body.contacto,
        email        = body.email,
        telefono     = body.telefono,
        direccion    = body.direccion,
        activo       = True,
    )
    db.add(p)
    db.commit()
    return {"ok": True, "proveedor_id": p.id}


@router.patch("/proveedores/{proveedor_id}")
def editar_proveedor(
    proveedor_id: str,
    body:         ProveedorBody,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)
    p = db.query(Proveedor).filter(
        Proveedor.id == proveedor_id, Proveedor.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")

    if body.razon_social.strip():
        p.razon_social = body.razon_social.strip()
    p.ruc = body.ruc
    p.contacto = body.contacto
    p.email = body.email
    p.telefono = body.telefono
    p.direccion = body.direccion
    db.commit()
    return {"ok": True}


@router.delete("/proveedores/{proveedor_id}")
def eliminar_proveedor(
    proveedor_id: str,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)
    p = db.query(Proveedor).filter(
        Proveedor.id == proveedor_id, Proveedor.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    p.activo = False
    db.commit()
    return {"ok": True}


# ══════════════════════════════════════════════════════════════════
# Órdenes de compra
# ══════════════════════════════════════════════════════════════════

def _orden_to_out(db: Session, orden: OrdenCompra, proveedor_nombre: str,
                  con_items: bool = False) -> OrdenCompraOut:
    items: list[DetalleCompraOut] = []
    total_items = 0
    if con_items:
        rows = (
            db.query(
                DetalleCompra,
                Material.nombre.label("mat_nombre"),
                Material.unidad.label("mat_unidad"),
            )
            .join(Material, Material.id == DetalleCompra.material_id)
            .filter(DetalleCompra.orden_id == orden.id)
            .all()
        )
        total_items = len(rows)
        for r in rows:
            d = r.DetalleCompra
            items.append(DetalleCompraOut(
                id=str(d.id),
                material_id=str(d.material_id),
                material_nombre=r.mat_nombre or "",
                unidad=r.mat_unidad or "und",
                cantidad=d.cantidad or 0,
                precio_unitario=float(d.precio_unitario or 0),
            ))
    else:
        total_items = (
            db.query(func.count(DetalleCompra.id))
            .filter(DetalleCompra.orden_id == orden.id)
            .scalar()
        ) or 0

    return OrdenCompraOut(
        id=str(orden.id),
        proveedor_id=str(orden.proveedor_id),
        proveedor_nombre=proveedor_nombre,
        estado=orden.estado or "borrador",
        fecha_emision=orden.fecha_emision.isoformat() if orden.fecha_emision else "",
        fecha_entrega_estimada=orden.fecha_entrega_estimada.isoformat() if orden.fecha_entrega_estimada else None,
        total_referencial=float(orden.total_referencial or 0),
        total_items=total_items,
        items=items,
    )


@router.get("/ordenes", response_model=List[OrdenCompraOut])
def listar_ordenes(
    estado:  str = "",
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)

    q = (
        db.query(OrdenCompra, Proveedor.razon_social.label("prov"))
        .outerjoin(Proveedor, Proveedor.id == OrdenCompra.proveedor_id)
        .filter(OrdenCompra.empresa_id == empresa_id)
    )
    if estado:
        q = q.filter(OrdenCompra.estado == estado)
    rows = q.order_by(OrdenCompra.created_at.desc()).all()

    return [
        _orden_to_out(db, r.OrdenCompra, r.prov or "Proveedor", con_items=False)
        for r in rows
    ]


@router.get("/ordenes/{orden_id}", response_model=OrdenCompraOut)
def detalle_orden(
    orden_id: str,
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)
    orden = db.query(OrdenCompra).filter(
        OrdenCompra.id == orden_id, OrdenCompra.empresa_id == empresa_id
    ).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden no encontrada")
    prov = db.query(Proveedor).filter(Proveedor.id == orden.proveedor_id).first()
    return _orden_to_out(db, orden, prov.razon_social if prov else "Proveedor", con_items=True)


@router.post("/ordenes", status_code=status.HTTP_201_CREATED)
def crear_orden(
    body:    CrearOrdenCompraBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)

    if not body.items:
        raise HTTPException(status_code=422, detail="Debe incluir al menos un material")

    prov = db.query(Proveedor).filter(
        Proveedor.id == body.proveedor_id, Proveedor.empresa_id == empresa_id
    ).first()
    if not prov:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")

    total = 0.0
    for it in body.items:
        if it.cantidad < 1:
            raise HTTPException(status_code=422, detail="Cantidad inválida")
        mat = db.query(Material).filter(
            Material.id == it.material_id, Material.empresa_id == empresa_id
        ).first()
        if not mat:
            raise HTTPException(status_code=404, detail="Material no encontrado")
        total += (it.precio_unitario or 0) * it.cantidad

    orden = OrdenCompra(
        id                     = str(_uuid.uuid4()),
        empresa_id             = empresa_id,
        proveedor_id           = body.proveedor_id,
        estado                 = "enviada",
        fecha_emision          = date.today(),
        fecha_entrega_estimada = _parse_date(body.fecha_entrega_estimada),
        total_referencial      = total,
    )
    db.add(orden)
    db.flush()

    for it in body.items:
        db.add(DetalleCompra(
            id              = str(_uuid.uuid4()),
            orden_id        = orden.id,
            material_id     = it.material_id,
            cantidad        = it.cantidad,
            precio_unitario = it.precio_unitario or 0,
        ))

    db.commit()
    return {"ok": True, "orden_id": orden.id}


@router.patch("/ordenes/{orden_id}/estado")
def cambiar_estado_orden(
    orden_id: str,
    body:     CambiarEstadoOrdenBody,
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    _guard(payload)
    estado = (body.estado or "").lower().strip()
    if estado not in ("enviada", "confirmada", "en_transito", "cancelada"):
        raise HTTPException(status_code=422, detail="Estado inválido")

    orden = db.query(OrdenCompra).filter(
        OrdenCompra.id == orden_id, OrdenCompra.empresa_id == empresa_id
    ).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden no encontrada")
    if orden.estado == "recibida":
        raise HTTPException(status_code=409, detail="La orden ya fue recibida")

    orden.estado = estado
    orden.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "estado": estado}


# ══════════════════════════════════════════════════════════════════
# Recepción de mercadería
# ══════════════════════════════════════════════════════════════════

@router.post("/ordenes/{orden_id}/recibir")
def recibir_orden(
    orden_id: str,
    body:     RecibirOrdenBody,
    payload:  dict    = Depends(verificar_token),
    db:       Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    _guard(payload)

    orden = db.query(OrdenCompra).filter(
        OrdenCompra.id == orden_id, OrdenCompra.empresa_id == empresa_id
    ).first()
    if not orden:
        raise HTTPException(status_code=404, detail="Orden no encontrada")
    if orden.estado == "recibida":
        raise HTTPException(status_code=409, detail="La orden ya fue recibida")
    if orden.estado == "cancelada":
        raise HTTPException(status_code=409, detail="La orden está cancelada")

    detalles = db.query(DetalleCompra).filter(
        DetalleCompra.orden_id == orden.id
    ).all()
    if not detalles:
        raise HTTPException(status_code=400, detail="La orden no tiene items")

    # Almacén destino: el indicado o el principal
    almacen_id = body.almacen_id
    if not almacen_id:
        alm = db.query(Almacen).filter(Almacen.empresa_id == empresa_id).first()
        if not alm:
            raise HTTPException(status_code=400, detail="No hay almacenes registrados")
        almacen_id = str(alm.id)

    # Mapa de cantidades recibidas (si no se especifica, recibir lo esperado)
    recibidas: dict[str, int] = {}
    if body.items:
        for it in body.items:
            recibidas[it.material_id] = it.cantidad_recibida

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()

    recepcion = RecepcionCompra(
        id          = str(_uuid.uuid4()),
        orden_id    = orden.id,
        empresa_id  = empresa_id,
        receptor_id = empleado.id if empleado else None,
        almacen_id  = almacen_id,
        estado      = "completa",
        fecha       = datetime.utcnow(),
        notas       = body.notas,
    )
    db.add(recepcion)
    db.flush()

    hubo_diferencias = False
    for d in detalles:
        esperada = d.cantidad or 0
        recibida = recibidas.get(str(d.material_id), esperada)
        if recibida < 0:
            recibida = 0
        if recibida != esperada:
            hubo_diferencias = True

        estado_item = (
            "completo" if recibida == esperada
            else "parcial" if 0 < recibida < esperada
            else "faltante" if recibida == 0
            else "completo"
        )

        db.add(RecepcionDetalle(
            id                = str(_uuid.uuid4()),
            recepcion_id      = recepcion.id,
            material_id       = d.material_id,
            cantidad_esperada = esperada,
            cantidad_recibida = recibida,
            estado_item       = estado_item,
        ))

        if recibida > 0:
            # Sumar al stock
            stock = db.query(Stock).filter(
                Stock.material_id == d.material_id,
                Stock.empresa_id  == empresa_id,
                Stock.almacen_id  == almacen_id,
            ).first()
            if stock:
                stock.cantidad = (stock.cantidad or 0) + recibida
                stock.updated_at = datetime.utcnow()
            else:
                db.add(Stock(
                    material_id    = d.material_id,
                    empresa_id     = empresa_id,
                    almacen_id     = almacen_id,
                    cantidad       = recibida,
                    cantidad_minima= 0,
                ))

            # Registrar movimiento tipo=compra
            db.add(MovimientoInventario(
                id              = str(_uuid.uuid4()),
                empresa_id      = empresa_id,
                material_id     = d.material_id,
                almacen_id      = almacen_id,
                tipo            = "compra",
                cantidad        = recibida,
                motivo          = f"Recepción OC {orden.id[:8]}",
                referencia_id   = orden.id,
                referencia_tipo = "orden_compra",
                responsable_id  = empleado.id if empleado else None,
                fecha           = datetime.utcnow(),
            ))

    if hubo_diferencias:
        recepcion.estado = "con_diferencias"

    orden.estado = "recibida"
    orden.fecha_entrega_real = date.today()
    orden.updated_at = datetime.utcnow()
    db.commit()
    return {"ok": True, "recepcion_id": recepcion.id, "estado": recepcion.estado}
