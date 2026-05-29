"""
Router: /correctivos — Garantías/Correctivos + Observaciones (descargos) por servicio (Fase 4).
NO altera proyecto_servicio; lo referencia. Valida pertenencia a la empresa del token.
"""
from __future__ import annotations

import re
import uuid as _uuid
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.correctivo import ServicioCorrectivo, ServicioObservacion
from ..models.proyecto_servicio import ProyectoServicio
from ..services.cloudinary_service import subir_e_indexar, eliminar_imagen_cloudinary
from ..services.cloudinary_paths import carpeta_correctivo
from ..schemas.correctivos import (
    CorrectivoIn, CorrectivoOut, TransicionIn, InformeIn,
    ObservacionIn, ObservacionOut, TRANSICIONES,
)

router = APIRouter(prefix="/correctivos", tags=["correctivos"])


def _servicio_or_400(db: Session, empresa_id: str, servicio_id: str) -> ProyectoServicio:
    ps = db.query(ProyectoServicio).filter(
        ProyectoServicio.id == servicio_id, ProyectoServicio.empresa_id == empresa_id
    ).first()
    if not ps:
        raise HTTPException(status_code=400, detail="Servicio inválido o de otra empresa")
    return ps


def _correctivo_or_404(db: Session, empresa_id: str, cid: str) -> ServicioCorrectivo:
    c = db.query(ServicioCorrectivo).filter(
        ServicioCorrectivo.id == cid, ServicioCorrectivo.empresa_id == empresa_id
    ).first()
    if not c:
        raise HTTPException(status_code=404, detail="Correctivo no encontrado")
    return c


def _siguiente_codigo(db: Session, empresa_id: str) -> str:
    rows = db.query(ServicioCorrectivo.codigo).filter(
        ServicioCorrectivo.empresa_id == empresa_id, ServicioCorrectivo.codigo.ilike("COR-%")
    ).all()
    mx = 0
    for (c,) in rows:
        m = re.match(r"^COR-(\d+)$", (c or "").strip(), re.IGNORECASE)
        if m:
            mx = max(mx, int(m.group(1)))
    return f"COR-{mx + 1:04d}"


def _out(c: ServicioCorrectivo) -> CorrectivoOut:
    return CorrectivoOut(
        id=str(c.id), servicio_id=str(c.servicio_id), codigo=c.codigo, alcance=c.alcance,
        fecha_inicio=(str(c.fecha_inicio) if c.fecha_inicio else None),
        fecha_fin=(str(c.fecha_fin) if c.fecha_fin else None),
        estado=c.estado, informe_url=c.informe_url,
    )


# ── Correctivos ──────────────────────────────────────────────────────────────
@router.get("", response_model=List[CorrectivoOut])
def listar(
    servicio_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(ServicioCorrectivo).filter(ServicioCorrectivo.empresa_id == payload["empresa_id"])
    if servicio_id:
        qry = qry.filter(ServicioCorrectivo.servicio_id == servicio_id)
    if estado:
        qry = qry.filter(ServicioCorrectivo.estado == estado)
    return [_out(c) for c in qry.order_by(ServicioCorrectivo.created_at.desc()).limit(300).all()]


@router.post("", response_model=CorrectivoOut, status_code=201)
def crear(body: CorrectivoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "crear")
    empresa_id = payload["empresa_id"]
    _servicio_or_400(db, empresa_id, body.servicio_id)
    c = ServicioCorrectivo(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, servicio_id=body.servicio_id,
        codigo=_siguiente_codigo(db, empresa_id), alcance=body.alcance,
        fecha_inicio=body.fecha_inicio or None, fecha_fin=body.fecha_fin or None,
        estado="registrado",
    )
    db.add(c)
    db.commit()
    return _out(c)


@router.put("/{cid}", response_model=CorrectivoOut)
def actualizar(cid: str, body: CorrectivoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "editar")
    c = _correctivo_or_404(db, payload["empresa_id"], cid)
    c.alcance = body.alcance
    c.fecha_inicio = body.fecha_inicio or None
    c.fecha_fin = body.fecha_fin or None
    db.commit()
    return _out(c)


@router.post("/{cid}/transicion", response_model=CorrectivoOut)
def transicionar(cid: str, body: TransicionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "aprobar")
    c = _correctivo_or_404(db, payload["empresa_id"], cid)
    permitidos = TRANSICIONES.get(c.estado, set())
    if body.nuevo_estado not in permitidos:
        raise HTTPException(status_code=409, detail=f"Transición inválida: {c.estado} → {body.nuevo_estado}. Permitidas: {sorted(permitidos)}")
    c.estado = body.nuevo_estado
    db.commit()
    return _out(c)


@router.post("/{cid}/finalizar", response_model=CorrectivoOut)
def finalizar(cid: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "finalizar")
    c = _correctivo_or_404(db, payload["empresa_id"], cid)
    if c.estado != "aprobado":
        raise HTTPException(status_code=409, detail="Solo se finaliza un correctivo 'aprobado'")
    c.estado = "finalizado"
    c.fecha_fin = c.fecha_fin or date.today()
    db.commit()
    return _out(c)


@router.post("/{cid}/informe", response_model=CorrectivoOut)
def subir_informe(cid: str, body: InformeIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "correctivo", "editar")
    empresa_id = payload["empresa_id"]
    c = _correctivo_or_404(db, empresa_id, cid)
    if c.informe_url:
        eliminar_imagen_cloudinary(c.informe_url)
    rec = subir_e_indexar(
        db, empresa_id=empresa_id, base64_data=body.archivo_base64,
        folder=carpeta_correctivo(empresa_id, cid), public_id=f"informe_{cid}",
        entidad_tipo="correctivo", entidad_id=cid, creado_por_id=payload.get("id"),
    )
    c.informe_url = rec.secure_url
    db.commit()
    return _out(c)


# ── Observaciones / descargos ────────────────────────────────────────────────
def _obs_out(o: ServicioObservacion) -> ObservacionOut:
    return ObservacionOut(
        id=str(o.id), servicio_id=str(o.servicio_id),
        correctivo_id=(str(o.correctivo_id) if o.correctivo_id else None),
        observaciones=o.observaciones, recomendaciones=o.recomendaciones,
        fecha_descargo=(str(o.fecha_descargo) if o.fecha_descargo else None),
    )


@router.get("/servicios/{servicio_id}/observaciones", response_model=List[ObservacionOut])
def listar_observaciones(servicio_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _servicio_or_400(db, payload["empresa_id"], servicio_id)
    rows = db.query(ServicioObservacion).filter(
        ServicioObservacion.empresa_id == payload["empresa_id"],
        ServicioObservacion.servicio_id == servicio_id,
    ).order_by(ServicioObservacion.created_at.desc()).all()
    return [_obs_out(o) for o in rows]


@router.post("/servicios/{servicio_id}/observaciones", response_model=ObservacionOut, status_code=201)
def crear_observacion(servicio_id: str, body: ObservacionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "observacion", "crear")
    empresa_id = payload["empresa_id"]
    _servicio_or_400(db, empresa_id, servicio_id)
    o = ServicioObservacion(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, servicio_id=servicio_id,
        correctivo_id=body.correctivo_id, observaciones=body.observaciones,
        recomendaciones=body.recomendaciones, fecha_descargo=date.today(),
        registrado_por_id=payload.get("id"),
    )
    db.add(o)
    db.commit()
    return _obs_out(o)


@router.delete("/observaciones/{obs_id}", status_code=204)
def eliminar_observacion(obs_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "observacion", "eliminar")
    o = db.query(ServicioObservacion).filter(
        ServicioObservacion.id == obs_id, ServicioObservacion.empresa_id == payload["empresa_id"]
    ).first()
    if not o:
        raise HTTPException(status_code=404, detail="Observación no encontrada")
    db.delete(o)
    db.commit()
