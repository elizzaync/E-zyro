"""
Router: /garantias — Repositorio central de cartas de garantía.

Lista TODAS las garantías de la empresa (generadas post-servicio + manuales),
con filtros por cliente/proyecto/servicio/estado, enlazadas a su servicio →
proyecto → cliente. Punto final de la documentación de garantías del servicio.

La generación normal sigue en /operaciones/servicio/{id}/carta-garantia/generar;
aquí solo se consulta, se sube manualmente y se elimina. Reusa permisos del
módulo 'correctivo' (mismo apartado Garantías/Correctivos).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.carta_garantia import CartaGarantia
from ..models.proyecto_servicio import ProyectoServicio
from ..models.proyecto import Proyecto
from ..models.cliente import Cliente
from ..schemas.garantia import GarantiaOut, GarantiaManualIn
from ..services.cloudinary_service import subir_archivo_base64

router = APIRouter(prefix="/garantias", tags=["garantias"])

_DIAS_AVISO = 30


def _parse_fecha(s: Optional[str]) -> Optional[date]:
    if not s:
        return None
    try:
        return date.fromisoformat(s[:10])
    except Exception:
        return None


def _estado(fv: Optional[date]) -> tuple[str, Optional[int]]:
    if not fv:
        return ("sin_fecha", None)
    dias = (fv - date.today()).days
    if dias < 0:
        return ("vencida", dias)
    if dias <= _DIAS_AVISO:
        return ("por_vencer", dias)
    return ("vigente", dias)


def _construir(db: Session, garantias: list[CartaGarantia]) -> list[GarantiaOut]:
    """Enriquemos con servicio→proyecto→cliente vía mapas en Python (las PK son
    uuid nativo vs varchar → un JOIN directo en SQL fallaría)."""
    sids = {str(g.servicio_id) for g in garantias if g.servicio_id}
    serv_map: dict[str, ProyectoServicio] = {}
    if sids:
        for s in db.query(ProyectoServicio).filter(ProyectoServicio.id.in_(sids)).all():
            serv_map[str(s.id)] = s
    pids = {str(s.proyecto_id) for s in serv_map.values() if s.proyecto_id}
    proy_map: dict[str, Proyecto] = {}
    if pids:
        for p in db.query(Proyecto).filter(Proyecto.id.in_(pids)).all():
            proy_map[str(p.id)] = p
    cids = {str(p.cliente_id) for p in proy_map.values() if p.cliente_id}
    cli_map: dict[str, str] = {}
    if cids:
        for c in db.query(Cliente).filter(Cliente.id.in_(cids)).all():
            cli_map[str(c.id)] = c.razon_social or ""

    out: list[GarantiaOut] = []
    for g in garantias:
        s = serv_map.get(str(g.servicio_id)) if g.servicio_id else None
        p = proy_map.get(str(s.proyecto_id)) if (s and s.proyecto_id) else None
        cid = (str(p.cliente_id) if (p and p.cliente_id) else None)
        estado, dias = _estado(g.vigencia_garantia)
        out.append(GarantiaOut(
            id=str(g.id),
            servicio_id=(str(g.servicio_id) if g.servicio_id else None),
            servicio_nombre=(s.nombre if s else None),
            proyecto_id=(str(s.proyecto_id) if (s and s.proyecto_id) else None),
            proyecto_nombre=(p.nombre_proyecto if p else None),
            cliente_id=cid,
            cliente_nombre=(cli_map.get(cid) if cid else None),
            razon_social=g.razon_social,
            lugar=g.lugar,
            fecha_operatividad=(g.fecha_operatividad.isoformat() if g.fecha_operatividad else None),
            vigencia_garantia=(g.vigencia_garantia.isoformat() if g.vigencia_garantia else None),
            estado=estado,
            dias_para_vencer=dias,
            documento_pdf_url=g.documento_pdf_url,
            created_at=(g.created_at.isoformat() if g.created_at else None),
        ))
    return out


@router.get("", response_model=List[GarantiaOut])
def listar(
    cliente_id:  Optional[str] = Query(None),
    proyecto_id: Optional[str] = Query(None),
    servicio_id: Optional[str] = Query(None),
    estado:      Optional[str] = Query(None, description="vigente|por_vencer|vencida|sin_fecha"),
    q:           Optional[str] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "correctivo", "ver")
    empresa_id = payload["empresa_id"]
    garantias = (
        db.query(CartaGarantia)
        .filter(CartaGarantia.empresa_id == empresa_id)
        .order_by(CartaGarantia.created_at.desc())
        .all()
    )
    items = _construir(db, garantias)
    if cliente_id:
        items = [o for o in items if o.cliente_id == cliente_id]
    if proyecto_id:
        items = [o for o in items if o.proyecto_id == proyecto_id]
    if servicio_id:
        items = [o for o in items if o.servicio_id == servicio_id]
    if estado:
        items = [o for o in items if o.estado == estado]
    if q:
        ql = q.strip().lower()
        items = [o for o in items if ql in (
            f"{o.razon_social or ''} {o.cliente_nombre or ''} "
            f"{o.servicio_nombre or ''} {o.proyecto_nombre or ''}").lower()]
    return items


@router.post("/manual", response_model=GarantiaOut, status_code=201)
def crear_manual(body: GarantiaManualIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "crear")
    empresa_id = payload["empresa_id"]
    if not body.archivo_base64:
        raise HTTPException(status_code=400, detail="archivo_base64 requerido")

    razon = body.razon_social
    if not razon and body.cliente_id:
        c = db.query(Cliente).filter(Cliente.id == body.cliente_id).first()
        razon = c.razon_social if c else None

    ext = ""
    if body.archivo_nombre and "." in body.archivo_nombre:
        ext = body.archivo_nombre.rsplit(".", 1)[1]
    res = subir_archivo_base64(
        body.archivo_base64, f"e-zyro/garantias/{empresa_id}",
        str(_uuid.uuid4()), extension=ext,
    )

    g = CartaGarantia(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        servicio_id=(body.servicio_id or None),
        equipo_ids=[],
        razon_social=razon,
        lugar=body.lugar,
        direccion=body.direccion,
        fecha_operatividad=_parse_fecha(body.fecha_operatividad),
        vigencia_garantia=_parse_fecha(body.vigencia_garantia),
        documento_pdf_url=res.get("secure_url"),
    )
    db.add(g)
    db.commit()
    db.refresh(g)
    return _construir(db, [g])[0]


@router.delete("/{garantia_id}", status_code=204)
def eliminar(garantia_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "editar")
    g = db.query(CartaGarantia).filter(
        CartaGarantia.id == garantia_id,
        CartaGarantia.empresa_id == payload["empresa_id"],
    ).first()
    if not g:
        raise HTTPException(status_code=404, detail="Garantía no encontrada")
    db.delete(g)
    db.commit()
