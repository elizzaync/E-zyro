"""
Router: /galeria  — Galería Global (índice recurso_cloudinary).
Lista/filtra/sube/borra recursos de la nube por empresa. Lecturas abiertas a la
empresa; subir/borrar protegidos por RBAC (módulo 'galeria').
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.recurso_cloudinary import RecursoCloudinary
from ..schemas.galeria import RecursoOut, RecursoSubirIn
from ..services.cloudinary_service import subir_e_indexar, eliminar_recurso_por_public_id
from ..services.cloudinary_paths import carpeta_galeria

router = APIRouter(prefix="/galeria", tags=["galeria"])


def _out(r: RecursoCloudinary) -> RecursoOut:
    return RecursoOut(
        id=str(r.id), secure_url=r.secure_url, public_id=r.public_id,
        recurso_tipo=r.recurso_tipo, entidad_tipo=r.entidad_tipo,
        entidad_id=(str(r.entidad_id) if r.entidad_id else None),
        descripcion=r.descripcion, formato=r.formato, bytes=r.bytes,
        created_at=(r.created_at.isoformat() if r.created_at else None),
    )


@router.get("", response_model=List[RecursoOut])
def listar(
    entidad_tipo: Optional[str] = Query(None),
    entidad_id:   Optional[str] = Query(None),
    recurso_tipo: Optional[str] = Query(None),
    fecha_desde:  Optional[str] = Query(None, description="ISO yyyy-mm-dd"),
    fecha_hasta:  Optional[str] = Query(None, description="ISO yyyy-mm-dd"),
    q:            Optional[str] = Query(None, description="busca en descripción/carpeta"),
    limit:        int = Query(60, ge=1, le=200),
    offset:       int = Query(0, ge=0),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    qry = db.query(RecursoCloudinary).filter(RecursoCloudinary.empresa_id == payload["empresa_id"])
    if entidad_tipo:
        qry = qry.filter(RecursoCloudinary.entidad_tipo == entidad_tipo)
    if entidad_id:
        qry = qry.filter(RecursoCloudinary.entidad_id == entidad_id)
    if recurso_tipo:
        qry = qry.filter(RecursoCloudinary.recurso_tipo == recurso_tipo)
    if fecha_desde:
        qry = qry.filter(RecursoCloudinary.created_at >= fecha_desde)
    if fecha_hasta:
        qry = qry.filter(RecursoCloudinary.created_at <= f"{fecha_hasta} 23:59:59")
    if q:
        like = f"%{q.strip()}%"
        from sqlalchemy import or_
        qry = qry.filter(or_(RecursoCloudinary.descripcion.ilike(like),
                             RecursoCloudinary.folder.ilike(like)))
    rows = qry.order_by(RecursoCloudinary.created_at.desc()).offset(offset).limit(limit).all()
    return [_out(r) for r in rows]


@router.get("/entidad/{tipo}/{ent_id}", response_model=List[RecursoOut])
def listar_por_entidad(tipo: str, ent_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    rows = (
        db.query(RecursoCloudinary)
        .filter(RecursoCloudinary.empresa_id == payload["empresa_id"],
                RecursoCloudinary.entidad_tipo == tipo,
                RecursoCloudinary.entidad_id == ent_id)
        .order_by(RecursoCloudinary.created_at.desc())
        .all()
    )
    return [_out(r) for r in rows]


@router.post("", response_model=RecursoOut, status_code=201)
def subir(body: RecursoSubirIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "galeria", "subir")
    if not body.imagen_base64:
        raise HTTPException(status_code=400, detail="imagen_base64 requerida")
    empresa_id = payload["empresa_id"]
    ahora = datetime.utcnow()
    folder = carpeta_galeria(empresa_id, ahora.year, ahora.month)
    import uuid as _uuid
    rec = subir_e_indexar(
        db, empresa_id=empresa_id, base64_data=body.imagen_base64, folder=folder,
        public_id=str(_uuid.uuid4()), entidad_tipo=(body.entidad_tipo or "galeria"),
        entidad_id=body.entidad_id, descripcion=body.descripcion, creado_por_id=payload.get("id"),
    )
    return _out(rec)


@router.delete("/{recurso_id}", status_code=204)
def eliminar(recurso_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "galeria", "eliminar")
    r = db.query(RecursoCloudinary).filter(
        RecursoCloudinary.id == recurso_id,
        RecursoCloudinary.empresa_id == payload["empresa_id"],
    ).first()
    if not r:
        raise HTTPException(status_code=404, detail="Recurso no encontrado")
    rtype = "raw" if r.recurso_tipo in ("pdf", "raw") else "image"
    eliminar_recurso_por_public_id(r.public_id, resource_type=rtype)
    db.delete(r)
    db.commit()
