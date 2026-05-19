"""
Router: /requerimientos
Catálogo de materiales y gestión de solicitudes (HU-17).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db

from ..models.material import Material, Stock
from ..models.categoria_material import CategoriaMaterial
from ..models.requerimiento import Requerimiento, RequerimientoDetalle
from ..models.empleado import Empleado
from ..models.proyecto import Proyecto

from ..schemas.requerimientos import (
    CatalogoItemOut,
    SolicitudDetalleOut,
    MiSolicitudOut,
    CrearSolicitudBody,
)

router = APIRouter(prefix="/requerimientos", tags=["requerimientos"])


def _get_empleado_or_403(db: Session, usuario_id: str, empresa_id: str) -> Empleado:
    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    if not emp:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")
    return emp


# ── GET /requerimientos/catalogo ──────────────────────────────────────────────

@router.get("/catalogo", response_model=List[CatalogoItemOut])
def get_catalogo(
    q:         str = "",
    categoria: str = "",     # HU-15: filtro por categoría
    page:      int = 1,      # HU-15: página (base 1)
    page_size: int = 30,     # HU-15: items por página
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]

    page_size = min(max(page_size, 1), 100)
    page      = max(page, 1)
    offset    = (page - 1) * page_size

    stock_sq = (
        db.query(
            Stock.material_id,
            func.sum(Stock.cantidad).label("total"),
        )
        .filter(Stock.empresa_id == empresa_id)
        .group_by(Stock.material_id)
        .subquery()
    )

    query = (
        db.query(
            Material.id,
            Material.nombre,
            Material.codigo,
            Material.unidad,
            Material.descripcion,
            CategoriaMaterial.nombre.label("categoria"),
            func.coalesce(stock_sq.c.total, 0).label("stock"),
        )
        .outerjoin(stock_sq, stock_sq.c.material_id == Material.id)
        .outerjoin(CategoriaMaterial, CategoriaMaterial.id == Material.categoria_id)
        .filter(
            Material.empresa_id == empresa_id,
            Material.activo == True,
        )
    )

    if q:
        query = query.filter(
            (Material.nombre.ilike(f"%{q}%")) |
            (Material.codigo.ilike(f"%{q}%"))
        )

    if categoria:
        query = query.filter(CategoriaMaterial.nombre.ilike(f"%{categoria}%"))

    rows = (
        query
        .order_by(Material.nombre.asc())
        .offset(offset)
        .limit(page_size)
        .all()
    )

    return [
        CatalogoItemOut(
            id=r.id,
            nombre=r.nombre,
            codigo=r.codigo,
            unidad=r.unidad,
            stock=int(r.stock),
            categoria=r.categoria,
            descripcion=r.descripcion,
            imagen_url=None,
        )
        for r in rows
    ]


# ── GET /requerimientos/mis-solicitudes ───────────────────────────────────────

@router.get("/mis-solicitudes", response_model=List[MiSolicitudOut])
def get_mis_solicitudes(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    reqs = (
        db.query(Requerimiento)
        .filter(
            Requerimiento.empresa_id    == empresa_id,
            Requerimiento.solicitante_id == empleado.id,
            Requerimiento.tipo          == "material",
        )
        .order_by(Requerimiento.created_at.desc())
        .all()
    )

    if not reqs:
        return []

    req_ids     = [r.id for r in reqs]
    proyecto_ids = list({r.proyecto_id for r in reqs})

    proyectos_map = {
        p.id: p
        for p in db.query(Proyecto).filter(Proyecto.id.in_(proyecto_ids)).all()
    }

    detalles_rows = (
        db.query(
            RequerimientoDetalle,
            Material.nombre.label("mat_nombre"),
            Material.unidad.label("mat_unidad"),
        )
        .join(Material, Material.id == RequerimientoDetalle.material_id)
        .filter(RequerimientoDetalle.requerimiento_id.in_(req_ids))
        .all()
    )

    detalles_by_req: dict[str, list] = {}
    for row in detalles_rows:
        detalles_by_req.setdefault(row.RequerimientoDetalle.requerimiento_id, []).append(row)

    result = []
    for req in reqs:
        proyecto = proyectos_map.get(req.proyecto_id)
        proyecto_nombre = (
            proyecto.nombre_proyecto
            if proyecto and proyecto.nombre_proyecto
            else "Proyecto"
        )

        items = [
            SolicitudDetalleOut(
                id=str(d.RequerimientoDetalle.id),
                material_id=str(d.RequerimientoDetalle.material_id),
                nombre=d.mat_nombre or "",
                unidad=d.mat_unidad or "",
                cantidad=d.RequerimientoDetalle.cantidad or 0,
                cantidad_aprobada=d.RequerimientoDetalle.cantidad_aprobada,
            )
            for d in detalles_by_req.get(req.id, [])
        ]

        result.append(MiSolicitudOut(
            id=str(req.id),
            estado=req.estado or "pendiente",
            fecha=req.fecha.strftime("%d %b %Y") if req.fecha else "",
            observacion=req.observacion,
            observacion_logistico=req.observacion_logistico,  # HU-16
            proyecto_nombre=proyecto_nombre,
            items=items,
        ))

    return result


# ── POST /requerimientos/crear ────────────────────────────────────────────────

@router.post("/crear", status_code=status.HTTP_201_CREATED)
def crear_solicitud(
    body:    CrearSolicitudBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    if not body.items:
        raise HTTPException(status_code=422, detail="Debe incluir al menos un material")

    proyecto = db.query(Proyecto).filter(
        Proyecto.id         == body.proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    empleado = _get_empleado_or_403(db, usuario_id, empresa_id)

    for item in body.items:
        if item.cantidad < 1:
            raise HTTPException(status_code=422, detail="Cantidad debe ser mayor a 0")
        mat = db.query(Material).filter(
            Material.id         == item.material_id,
            Material.empresa_id == empresa_id,
            Material.activo     == True,
        ).first()
        if not mat:
            raise HTTPException(status_code=404, detail="Material no encontrado")

    req = Requerimiento(
        id             = str(_uuid.uuid4()),
        proyecto_id    = body.proyecto_id,
        empresa_id     = empresa_id,
        solicitante_id = empleado.id,
        tipo           = "material",
        estado         = "pendiente",
        observacion    = body.observacion,
        fecha          = date.today(),
    )
    db.add(req)
    db.flush()

    for item in body.items:
        db.add(RequerimientoDetalle(
            id               = str(_uuid.uuid4()),
            requerimiento_id = req.id,
            material_id      = item.material_id,
            cantidad         = item.cantidad,
        ))

    db.commit()
    return {"ok": True, "requerimiento_id": req.id}
