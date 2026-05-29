"""
Router: /servicios/{id}/(pre-informe|informe-final|informes) — refinamiento.
Compila procedimientos + evidencias de un servicio en un PDF (pre o final) y lo
sube/indexa. El informe final exige el servicio cerrado ('Completado').
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.informe_servicio import InformeServicio
from ..models.proyecto_servicio import ProyectoServicio
from ..models.procedimiento import Procedimiento
from ..models.evidencia_procedimiento import EvidenciaProcedimiento
from ..models.empresa import Empresa
from ..services.pdf_informe_servicio import generar_informe_servicio_pdf
from ..services.cloudinary_service import subir_pdf_bytes_cloudinary, registrar_recurso

router = APIRouter(prefix="/servicios", tags=["informes-servicio"])

_ESTADO_CERRADO = "Completado"


def _servicio_or_404(db: Session, empresa_id: str, servicio_id: str) -> ProyectoServicio:
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == servicio_id, ProyectoServicio.empresa_id == empresa_id
    ).first()
    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")
    return ps


def _armar_data(db: Session, empresa_id: str, ps: ProyectoServicio, tipo: str) -> dict:
    empresa = db.query(Empresa.razon_social).filter(Empresa.id == empresa_id).scalar() or ""
    procs = (
        db.query(Procedimiento)
        .filter(Procedimiento.proyecto_servicio_id == ps.id)
        .order_by(Procedimiento.orden).all()
    )
    proc_nombre = {str(p.id): p.nombre for p in procs}
    evs = (
        db.query(EvidenciaProcedimiento)
        .filter(EvidenciaProcedimiento.proyecto_servicio_id == ps.id)
        .order_by(EvidenciaProcedimiento.fecha_captura).all()
    )
    return {
        "tipo": tipo,
        "empresa": empresa,
        "servicio": {
            "nombre": ps.nombre, "estado": ps.estado, "alcance": ps.alcance,
            "zona": ps.zona_ejecucion, "responsable": "-",
            "fecha_inicio": ps.fecha_inicio, "fecha_fin": ps.fecha_fin,
            "nro_conformidad": ps.nro_conformidad,
        },
        "procedimientos": [{
            "orden": p.orden, "nombre": p.nombre, "estado": p.estado,
            "descripcion": p.descripcion, "fecha_inicio": p.fecha_inicio_tarea,
            "fecha_limite": p.fecha_limite,
        } for p in procs],
        "evidencias": [{
            "procedimiento": proc_nombre.get(str(e.procedimiento_id), ""),
            "etapa": e.etapa, "descripcion": e.descripcion,
            "fecha": e.fecha_captura, "url": e.url_cloudinary,
        } for e in evs],
    }


def _generar(db: Session, payload: dict, servicio_id: str, tipo: str) -> InformeServicio:
    empresa_id = payload["empresa_id"]
    ps = _servicio_or_404(db, empresa_id, servicio_id)
    if tipo == "final" and (ps.estado or "") != _ESTADO_CERRADO:
        raise HTTPException(status_code=409, detail=f"El informe final requiere el servicio '{_ESTADO_CERRADO}' (actual: {ps.estado})")

    data = _armar_data(db, empresa_id, ps, tipo)
    pdf_bytes = generar_informe_servicio_pdf(data)

    inf_id = str(_uuid.uuid4())
    pid = f"e-zyro/{empresa_id}/informes/{servicio_id}/{tipo}_{inf_id}"
    url = subir_pdf_bytes_cloudinary(pdf_bytes, pid)

    registrar_recurso(
        db, empresa_id=empresa_id, public_id=pid + ".pdf", secure_url=url,
        folder=f"e-zyro/{empresa_id}/informes/{servicio_id}", recurso_tipo="pdf",
        entidad_tipo="informe_servicio", entidad_id=servicio_id,
        descripcion=("Informe final" if tipo == "final" else "Pre-informe"),
        creado_por_id=payload.get("id"),
    )
    inf = InformeServicio(
        id=inf_id, empresa_id=empresa_id, servicio_id=servicio_id, tipo=tipo,
        titulo=("Informe final" if tipo == "final" else "Pre-informe") + f" — {ps.nombre}",
        url=url, public_id=pid + ".pdf", generado_por_id=payload.get("id"), fecha=date.today(),
    )
    db.add(inf)
    db.commit()
    return inf


def _out(i: InformeServicio) -> dict:
    return {
        "id": str(i.id), "servicio_id": str(i.servicio_id), "tipo": i.tipo,
        "titulo": i.titulo, "url": i.url, "fecha": str(i.fecha) if i.fecha else None,
    }


@router.post("/{servicio_id}/pre-informe")
def pre_informe(servicio_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "informe_servicio", "generar")
    return _out(_generar(db, payload, servicio_id, "pre"))


@router.post("/{servicio_id}/informe-final")
def informe_final(servicio_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "informe_servicio", "generar")
    return _out(_generar(db, payload, servicio_id, "final"))


@router.get("/{servicio_id}/informes", response_model=List[dict])
def listar_informes(servicio_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _servicio_or_404(db, payload["empresa_id"], servicio_id)
    rows = (
        db.query(InformeServicio)
        .filter(InformeServicio.empresa_id == payload["empresa_id"], InformeServicio.servicio_id == servicio_id)
        .order_by(InformeServicio.created_at.desc()).all()
    )
    return [_out(i) for i in rows]
