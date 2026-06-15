"""
Router: /epp — Equipos de Protección Personal.
Catálogo (stock), entregas con firma + constancia, ingresos de stock.
Lecturas: empresa del token. Escrituras: RBAC módulo 'epp'.
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.epp import Epp, EppEntrega, EppEntregaDetalle, EppIngreso, EppIngresoDetalle
from ..models.empleado import Empleado
from ..models.contabilidad import CuentaContable
from ..services import contabilizacion_service as contab
from ..services.contabilizacion_service import LineaAsiento
from ..services import costeo_inventario_service as costeo
from ..services.cloudinary_service import (
    subir_e_indexar, eliminar_imagen_cloudinary, subir_pdf_bytes_cloudinary, registrar_recurso,
)
from ..services.cloudinary_paths import carpeta_epp, carpeta_epp_entrega
from ..services.pdf_docs import generar_constancia_epp, generar_reporte_epp_empleado
from ..models.usuario import Usuario
from ..models.empresa import Empresa
from ..schemas.epp import (
    EppIn, EppOut, EppImagenIn,
    EntregaIn, EntregaOut, EntregaItemOut,
    IngresoIn, IngresoOut,
)

router = APIRouter(prefix="/epp", tags=["epp"])

CTA_MERCADERIAS  = "201"   # Mercaderías
CTA_VARIACION    = "611"   # Variación de existencias
CTA_COSTO_VENTAS = "691"   # Costo de ventas
Q2 = Decimal("0.01")


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


def _contabilizar_epp(db: Session, empresa_id: str, deb_cod: str, cre_cod: str,
                      valor: Decimal, descripcion: str, ref_id: str | None,
                      creado_por_id: str | None = None) -> None:
    """Asiento de inventario para EPP, best-effort: si no hay periodo abierto o
    falta una cuenta, NO contabiliza y NO rompe la operación de EPP."""
    valor = _d(valor)
    if valor <= 0:
        return
    fecha = datetime.utcnow()
    if not costeo._puede_contabilizar(db, empresa_id, fecha, (deb_cod, cre_cod)):
        return
    def _cid(cod: str):
        c = db.query(CuentaContable).filter(
            CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == cod).first()
        return c.id if c else None
    contab.registrar_asiento(
        db, empresa_id=empresa_id, fecha=fecha.date(), descripcion=descripcion,
        origen="inventario", lineas=[
            LineaAsiento(cuenta_id=_cid(deb_cod), debito=valor),
            LineaAsiento(cuenta_id=_cid(cre_cod), credito=valor),
        ],
        referencia_id=ref_id, creado_por_id=creado_por_id, commit=False,
    )


def _epp_out(e: Epp) -> EppOut:
    return EppOut(
        id=str(e.id), nombre=e.nombre, descripcion=e.descripcion,
        marca_id=(str(e.marca_id) if e.marca_id else None),
        unidad_id=(str(e.unidad_id) if e.unidad_id else None),
        zona_id=(str(e.zona_id) if e.zona_id else None),
        stock_actual=int(e.stock_actual or 0), stock_min=int(e.stock_min or 0),
        precio=(float(e.precio) if e.precio is not None else None),
        imagen_url=e.imagen_url, activo=bool(e.activo),
    )


def _epp_or_404(db: Session, empresa_id: str, epp_id: str) -> Epp:
    e = db.query(Epp).filter(Epp.id == epp_id, Epp.empresa_id == empresa_id).first()
    if not e:
        raise HTTPException(status_code=404, detail="EPP no encontrado")
    return e


# ── Catálogo ─────────────────────────────────────────────────────────────────
@router.get("", response_model=List[EppOut])
def listar(
    q: Optional[str] = Query(None),
    zona_id: Optional[str] = Query(None),
    stock_bajo: bool = Query(False),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(Epp).filter(Epp.empresa_id == payload["empresa_id"], Epp.activo.is_(True))
    if q:
        qry = qry.filter(func.lower(Epp.nombre).like(f"%{q.strip().lower()}%"))
    if zona_id:
        qry = qry.filter(Epp.zona_id == zona_id)
    if stock_bajo:
        qry = qry.filter(Epp.stock_actual <= Epp.stock_min)
    return [_epp_out(e) for e in qry.order_by(Epp.nombre).all()]


@router.post("", response_model=EppOut, status_code=201)
def crear(body: EppIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "crear")
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre requerido")
    e = Epp(
        id=str(_uuid.uuid4()), empresa_id=payload["empresa_id"], nombre=nombre,
        descripcion=body.descripcion, marca_id=body.marca_id, unidad_id=body.unidad_id,
        zona_id=body.zona_id, stock_min=body.stock_min or 0, precio=body.precio,
    )
    db.add(e)
    db.commit()
    return _epp_out(e)


@router.put("/{epp_id}", response_model=EppOut)
def actualizar(epp_id: str, body: EppIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "editar")
    e = _epp_or_404(db, payload["empresa_id"], epp_id)
    e.nombre = body.nombre.strip() or e.nombre
    e.descripcion = body.descripcion
    e.marca_id = body.marca_id
    e.unidad_id = body.unidad_id
    e.zona_id = body.zona_id
    e.stock_min = body.stock_min or 0
    e.precio = body.precio
    db.commit()
    return _epp_out(e)


@router.delete("/{epp_id}", status_code=204)
def eliminar(epp_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "eliminar")
    e = _epp_or_404(db, payload["empresa_id"], epp_id)
    e.activo = False  # baja lógica (preserva historial de entregas)
    db.commit()


@router.post("/{epp_id}/imagen", response_model=EppOut)
def subir_imagen(epp_id: str, body: EppImagenIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "editar")
    empresa_id = payload["empresa_id"]
    e = _epp_or_404(db, empresa_id, epp_id)
    if e.imagen_url:
        eliminar_imagen_cloudinary(e.imagen_url)
    rec = subir_e_indexar(
        db, empresa_id=empresa_id, base64_data=body.imagen_base64,
        folder=carpeta_epp(empresa_id, epp_id), public_id=f"epp_{epp_id}",
        entidad_tipo="epp", entidad_id=epp_id, creado_por_id=payload.get("id"),
    )
    e.imagen_url = rec.secure_url
    db.commit()
    return _epp_out(e)


# ── Entregas ─────────────────────────────────────────────────────────────────
def _items_out(db: Session, detalles) -> List[EntregaItemOut]:
    out = []
    for d in detalles:
        nombre = db.query(Epp.nombre).filter(Epp.id == d.epp_id).scalar() or ""
        out.append(EntregaItemOut(epp_id=str(d.epp_id), nombre=nombre, cantidad=int(d.cantidad)))
    return out


@router.post("/entregas", response_model=EntregaOut, status_code=201)
def crear_entrega(body: EntregaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "entregar")
    empresa_id = payload["empresa_id"]
    if not body.items:
        raise HTTPException(status_code=400, detail="La entrega no tiene ítems")
    emp = db.query(Empleado).filter(Empleado.id == body.empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=400, detail="Empleado receptor inválido")

    # Validar stock y bloquear filas EPP
    epps: dict[str, Epp] = {}
    for it in body.items:
        e = _epp_or_404(db, empresa_id, it.epp_id)
        if int(e.stock_actual or 0) < it.cantidad:
            raise HTTPException(status_code=409, detail=f"Stock insuficiente de '{e.nombre}' (hay {e.stock_actual}, piden {it.cantidad})")
        epps[it.epp_id] = e

    entrega = EppEntrega(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, empleado_id=body.empleado_id,
        fecha=date.today(), registrado_por_id=payload.get("id"), observacion=body.observacion,
        estado="registrada",
    )
    db.add(entrega)
    total_costo = Decimal("0")
    for it in body.items:
        db.add(EppEntregaDetalle(id=str(_uuid.uuid4()), entrega_id=entrega.id, epp_id=it.epp_id, cantidad=it.cantidad))
        e = epps[it.epp_id]
        total_costo += _d(e.precio) * Decimal(int(it.cantidad))
        e.stock_actual = int(e.stock_actual or 0) - it.cantidad
    # Asiento de salida al costo promedio (Db 691 / Cr 201) por el total entregado.
    _contabilizar_epp(db, empresa_id, CTA_COSTO_VENTAS, CTA_MERCADERIAS, total_costo,
                      f"Entrega de EPP (costo) {_d(total_costo)}", str(entrega.id))
    db.commit()

    # Firma (opcional) → Cloudinary + índice
    if body.firma_base64:
        rec = subir_e_indexar(
            db, empresa_id=empresa_id, base64_data=body.firma_base64,
            folder=carpeta_epp_entrega(empresa_id, entrega.id), public_id=f"firma_{entrega.id}",
            entidad_tipo="epp_entrega", entidad_id=entrega.id, creado_por_id=payload.get("id"),
        )
        entrega.firma_url = rec.secure_url
        db.commit()
    # NOTA: la constancia PDF (pdf_url) se generará en una iteración posterior (pdf_service).

    detalles = db.query(EppEntregaDetalle).filter(EppEntregaDetalle.entrega_id == entrega.id).all()
    return EntregaOut(
        id=str(entrega.id), empleado_id=str(entrega.empleado_id),
        empleado_nombre=None, fecha=str(entrega.fecha), estado=entrega.estado,
        firma_url=entrega.firma_url, pdf_url=entrega.pdf_url, observacion=entrega.observacion,
        items=_items_out(db, detalles),
    )


@router.get("/entregas", response_model=List[EntregaOut])
def listar_entregas(
    empleado_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(EppEntrega).filter(EppEntrega.empresa_id == payload["empresa_id"])
    if empleado_id:
        qry = qry.filter(EppEntrega.empleado_id == empleado_id)
    out = []
    for en in qry.order_by(EppEntrega.created_at.desc()).limit(200).all():
        detalles = db.query(EppEntregaDetalle).filter(EppEntregaDetalle.entrega_id == en.id).all()
        out.append(EntregaOut(
            id=str(en.id), empleado_id=str(en.empleado_id), fecha=str(en.fecha),
            estado=en.estado, firma_url=en.firma_url, pdf_url=en.pdf_url,
            observacion=en.observacion, items=_items_out(db, detalles),
        ))
    return out


@router.post("/entregas/{entrega_id}/anular", response_model=EntregaOut)
def anular_entrega(entrega_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "entregar")
    empresa_id = payload["empresa_id"]
    en = db.query(EppEntrega).filter(EppEntrega.id == entrega_id, EppEntrega.empresa_id == empresa_id).first()
    if not en:
        raise HTTPException(status_code=404, detail="Entrega no encontrada")
    if en.estado == "anulada":
        raise HTTPException(status_code=409, detail="La entrega ya está anulada")
    detalles = db.query(EppEntregaDetalle).filter(EppEntregaDetalle.entrega_id == en.id).all()
    total_costo = Decimal("0")
    for d in detalles:  # devolver stock
        e = db.query(Epp).filter(Epp.id == d.epp_id).first()
        if e:
            e.stock_actual = int(e.stock_actual or 0) + int(d.cantidad)
            total_costo += _d(e.precio) * Decimal(int(d.cantidad))
    # Revierte el asiento de salida (Db 201 / Cr 691) al costo promedio vigente.
    _contabilizar_epp(db, empresa_id, CTA_MERCADERIAS, CTA_COSTO_VENTAS, total_costo,
                      f"Anulación entrega EPP {_d(total_costo)}", str(en.id))
    en.estado = "anulada"
    db.commit()
    return EntregaOut(
        id=str(en.id), empleado_id=str(en.empleado_id), fecha=str(en.fecha),
        estado=en.estado, firma_url=en.firma_url, pdf_url=en.pdf_url,
        observacion=en.observacion, items=_items_out(db, detalles),
    )


@router.post("/entregas/{entrega_id}/constancia", response_model=EntregaOut)
def generar_constancia(entrega_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "ver")
    empresa_id = payload["empresa_id"]
    en = db.query(EppEntrega).filter(EppEntrega.id == entrega_id, EppEntrega.empresa_id == empresa_id).first()
    if not en:
        raise HTTPException(status_code=404, detail="Entrega no encontrada")
    detalles = db.query(EppEntregaDetalle).filter(EppEntregaDetalle.entrega_id == en.id).all()
    items = _items_out(db, detalles)
    fila = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == en.empleado_id).first()
    )
    receptor = f"{fila[0]} {fila[1] or ''}".strip() if fila else str(en.empleado_id)
    empresa = db.query(Empresa.razon_social).filter(Empresa.id == empresa_id).scalar() or ""
    data = {
        "empresa": empresa, "receptor": receptor, "fecha": str(en.fecha),
        "observacion": en.observacion, "firma_url": en.firma_url,
        "items": [{"nombre": it.nombre, "cantidad": it.cantidad} for it in items],
    }
    pdf = generar_constancia_epp(data)
    pid = f"e-zyro/{empresa_id}/epp-entregas/{entrega_id}/constancia_{entrega_id}"
    url = subir_pdf_bytes_cloudinary(pdf, pid)
    registrar_recurso(
        db, empresa_id=empresa_id, public_id=pid + ".pdf", secure_url=url,
        folder=carpeta_epp_entrega(empresa_id, entrega_id), recurso_tipo="pdf",
        entidad_tipo="epp_entrega", entidad_id=entrega_id, descripcion="Constancia de entrega EPP",
        creado_por_id=payload.get("id"),
    )
    en.pdf_url = url
    db.commit()
    return EntregaOut(
        id=str(en.id), empleado_id=str(en.empleado_id), empleado_nombre=receptor,
        fecha=str(en.fecha), estado=en.estado, firma_url=en.firma_url, pdf_url=en.pdf_url,
        observacion=en.observacion, items=items,
    )


# ── Reporte consolidado por técnico ──────────────────────────────────────────

@router.get("/empleado/{empleado_id}/reporte")
def reporte_empleado(empleado_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """Genera un PDF con TODO el EPP entregado a un técnico (consolidado +
    detalle por entrega), lo sube a Cloudinary y devuelve la URL."""
    exigir_permiso(db, payload, "epp", "ver")
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Técnico no encontrado")

    fila = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == empleado_id).first()
    )
    tecnico = f"{fila[0]} {fila[1] or ''}".strip() if fila else str(empleado_id)
    empresa = db.query(Empresa.razon_social).filter(Empresa.id == empresa_id).scalar() or ""

    entregas = (
        db.query(EppEntrega)
        .filter(
            EppEntrega.empleado_id == empleado_id,
            EppEntrega.empresa_id == empresa_id,
            EppEntrega.estado != "anulada",
        )
        .order_by(EppEntrega.fecha.desc())
        .all()
    )

    entregas_data: list = []
    totales: dict = {}  # nombre -> cantidad
    for en in entregas:
        detalles = db.query(EppEntregaDetalle).filter(
            EppEntregaDetalle.entrega_id == en.id
        ).all()
        items = _items_out(db, detalles)
        entregas_data.append({
            "fecha": str(en.fecha),
            "estado": en.estado,
            "items": [{"nombre": it.nombre, "cantidad": it.cantidad} for it in items],
        })
        for it in items:
            totales[it.nombre] = totales.get(it.nombre, 0) + (it.cantidad or 0)

    data = {
        "empresa": empresa,
        "tecnico": tecnico,
        "cargo": emp.cargo or "",
        "generado": str(date.today()),
        "totales": [{"nombre": k, "cantidad": v} for k, v in sorted(totales.items())],
        "entregas": entregas_data,
    }
    pdf = generar_reporte_epp_empleado(data)
    pid = f"e-zyro/{empresa_id}/epp-reportes/{empleado_id}/reporte_{empleado_id}"
    url = subir_pdf_bytes_cloudinary(pdf, pid)
    registrar_recurso(
        db, empresa_id=empresa_id, public_id=pid + ".pdf", secure_url=url,
        folder=f"e-zyro/{empresa_id}/epp-reportes/{empleado_id}", recurso_tipo="pdf",
        entidad_tipo="empleado", entidad_id=empleado_id,
        descripcion=f"Reporte EPP de {tecnico}", creado_por_id=payload.get("id"),
    )
    return {"pdf_url": url, "tecnico": tecnico, "total_entregas": len(entregas)}


# ── Ingresos ─────────────────────────────────────────────────────────────────
@router.post("/ingresos", response_model=IngresoOut, status_code=201)
def crear_ingreso(body: IngresoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "epp", "ingresar")
    empresa_id = payload["empresa_id"]
    if not body.items:
        raise HTTPException(status_code=400, detail="El ingreso no tiene ítems")
    for it in body.items:
        _epp_or_404(db, empresa_id, it.epp_id)

    ing = EppIngreso(
        id=str(_uuid.uuid4()), empresa_id=empresa_id,
        personal_compro_id=body.personal_compro_id, proveedor_id=body.proveedor_id,
        fecha_compra=date.today(), registrado_por_id=payload.get("id"),
    )
    db.add(ing)
    total_valor = Decimal("0")
    for it in body.items:
        db.add(EppIngresoDetalle(id=str(_uuid.uuid4()), ingreso_id=ing.id, epp_id=it.epp_id,
                                 cantidad=it.cantidad, precio_unitario=it.precio_unitario))
        e = db.query(Epp).filter(Epp.id == it.epp_id).first()
        prev = int(e.stock_actual or 0)
        precio = _d(it.precio_unitario)
        if precio > 0:
            # epp.precio se usa como COSTO PROMEDIO móvil del EPP.
            avg_prev = _d(e.precio)
            nueva = prev + int(it.cantidad)
            e.precio = (((Decimal(prev) * avg_prev + Decimal(int(it.cantidad)) * precio)
                         / Decimal(nueva)).quantize(Q2) if nueva > 0 else precio)
            total_valor += precio * Decimal(int(it.cantidad))
        e.stock_actual = prev + it.cantidad
    # Asiento de entrada valorizada (Db 201 / Cr 611) por el total del ingreso.
    _contabilizar_epp(db, empresa_id, CTA_MERCADERIAS, CTA_VARIACION, total_valor,
                      f"Ingreso de EPP (valorizado) {_d(total_valor)}", str(ing.id))
    db.commit()
    detalles = db.query(EppIngresoDetalle).filter(EppIngresoDetalle.ingreso_id == ing.id).all()
    return IngresoOut(
        id=str(ing.id), fecha_compra=str(ing.fecha_compra), proveedor_id=ing.proveedor_id,
        items=_items_out(db, detalles),
    )


@router.get("/ingresos", response_model=List[IngresoOut])
def listar_ingresos(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    out = []
    rows = db.query(EppIngreso).filter(EppIngreso.empresa_id == payload["empresa_id"]).order_by(EppIngreso.created_at.desc()).limit(200).all()
    for ing in rows:
        detalles = db.query(EppIngresoDetalle).filter(EppIngresoDetalle.ingreso_id == ing.id).all()
        out.append(IngresoOut(id=str(ing.id), fecha_compra=str(ing.fecha_compra),
                              proveedor_id=ing.proveedor_id, items=_items_out(db, detalles)))
    return out
