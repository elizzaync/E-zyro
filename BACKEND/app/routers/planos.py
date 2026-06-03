"""
Router: /planos — Gestión documental de planos tipo Drive (híbrido).
Carpetas recursivas (carpeta_documental) + planos (plano) + versiones
(version_plano). Almacenamiento en Cloudinary carpeta 'planos'.
Lectura: cualquier usuario de la empresa. Escritura: roles de gestión.
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..models.plano import Plano, VersionPlano
from ..models.carpeta_documental import CarpetaDocumental
from ..services.cloudinary_service import (
    subir_archivo_base64,
    eliminar_recurso_por_public_id,
)
from ..services.cloudinary_paths import carpeta_planos
from ..schemas.planos import (
    CarpetaIn, CarpetaRename, CarpetaOut,
    PlanoIn, PlanoOut, PlanoDetalleOut, VersionIn, VersionOut,
)

router = APIRouter(prefix="/planos", tags=["planos"])

_ROLES_GESTION = {
    "superadmin", "admin", "administrador",
    "jefe de operaciones", "jefe_operaciones",
    "supervisor de campo", "supervisor",
    "logística", "logistica", "logístico", "logistico",
}
_MAX_BYTES = 30 * 1024 * 1024  # 30 MB por archivo
_IMG_EXT = {"jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff"}


def _exigir_gestion(payload: dict) -> None:
    if (payload.get("rol") or "").lower().strip() not in _ROLES_GESTION:
        raise HTTPException(status_code=403, detail="Sin permiso para gestionar planos")


def _subido_por(payload: dict) -> Optional[str]:
    """version_plano.subido_por referencia usuario.id → guardamos el usuario logueado."""
    return payload.get("id")


def _ext(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


def _check_size(b64: str) -> None:
    # tamaño aproximado decodificado = len(base64) * 3/4
    payload = b64.split(",", 1)[1] if b64.startswith("data:") and "," in b64 else b64
    aprox = (len(payload) * 3) // 4
    if aprox > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="El archivo supera el límite de 30 MB")


# ════════════════════════════════════════════════════════════════════════════
# CARPETAS
# ════════════════════════════════════════════════════════════════════════════
def _carpeta_out(db: Session, c: CarpetaDocumental) -> CarpetaOut:
    subc = db.query(func.count(CarpetaDocumental.id)).filter(CarpetaDocumental.padre_id == c.id).scalar() or 0
    nplan = db.query(func.count(Plano.id)).filter(Plano.carpeta_id == c.id).scalar() or 0
    return CarpetaOut(
        id=str(c.id), nombre=c.nombre,
        padre_id=str(c.padre_id) if c.padre_id else None,
        proyecto_id=str(c.proyecto_id) if c.proyecto_id else None,
        sub_carpetas=int(subc), planos=int(nplan),
        created_at=c.created_at.isoformat() if c.created_at else None,
    )


@router.get("/carpetas", response_model=List[CarpetaOut])
def listar_carpetas(
    padre_id: str = Query("", description="vacío = raíz"),
    proyecto_id: str = Query(""),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    e = payload["empresa_id"]
    q = db.query(CarpetaDocumental).filter(CarpetaDocumental.empresa_id == e)
    if padre_id:
        q = q.filter(CarpetaDocumental.padre_id == padre_id)
    else:
        q = q.filter(CarpetaDocumental.padre_id.is_(None))
    if proyecto_id:
        q = q.filter(CarpetaDocumental.proyecto_id == proyecto_id)
    rows = q.order_by(CarpetaDocumental.nombre.asc()).all()
    return [_carpeta_out(db, c) for c in rows]


@router.post("/carpetas", response_model=CarpetaOut, status_code=201)
def crear_carpeta(body: CarpetaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _exigir_gestion(payload)
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")
    c = CarpetaDocumental(
        id=str(_uuid.uuid4()), empresa_id=payload["empresa_id"],
        nombre=nombre,
        padre_id=body.padre_id or None,
        proyecto_id=body.proyecto_id or None,
        created_at=datetime.utcnow(),
    )
    db.add(c)
    db.commit()
    return _carpeta_out(db, c)


@router.patch("/carpetas/{carpeta_id}", response_model=CarpetaOut)
def renombrar_carpeta(carpeta_id: str, body: CarpetaRename,
                      payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _exigir_gestion(payload)
    c = db.query(CarpetaDocumental).filter(
        CarpetaDocumental.id == carpeta_id, CarpetaDocumental.empresa_id == payload["empresa_id"]).first()
    if not c:
        raise HTTPException(status_code=404, detail="Carpeta no encontrada")
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")
    c.nombre = nombre
    db.commit()
    return _carpeta_out(db, c)


@router.delete("/carpetas/{carpeta_id}", status_code=204)
def eliminar_carpeta(carpeta_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _exigir_gestion(payload)
    e = payload["empresa_id"]
    c = db.query(CarpetaDocumental).filter(
        CarpetaDocumental.id == carpeta_id, CarpetaDocumental.empresa_id == e).first()
    if not c:
        raise HTTPException(status_code=404, detail="Carpeta no encontrada")
    subc = db.query(func.count(CarpetaDocumental.id)).filter(CarpetaDocumental.padre_id == carpeta_id).scalar() or 0
    nplan = db.query(func.count(Plano.id)).filter(Plano.carpeta_id == carpeta_id).scalar() or 0
    if subc or nplan:
        raise HTTPException(status_code=409, detail="La carpeta no está vacía. Elimina su contenido primero.")
    db.delete(c)
    db.commit()


# ════════════════════════════════════════════════════════════════════════════
# PLANOS
# ════════════════════════════════════════════════════════════════════════════
def _version_activa(db: Session, plano_id: str) -> Optional[VersionPlano]:
    return db.query(VersionPlano).filter(
        VersionPlano.plano_id == plano_id, VersionPlano.es_version_activa == True
    ).first()


def _plano_out(db: Session, pl: Plano) -> PlanoOut:
    va = _version_activa(db, pl.id)
    nver = db.query(func.count(VersionPlano.id)).filter(VersionPlano.plano_id == pl.id).scalar() or 0
    return PlanoOut(
        id=str(pl.id), nombre=pl.nombre, disciplina=pl.disciplina, descripcion=pl.descripcion,
        carpeta_id=str(pl.carpeta_id) if pl.carpeta_id else None,
        proyecto_id=str(pl.proyecto_id) if pl.proyecto_id else None,
        url=va.url_cloudinary if va else None,
        formato=va.formato if va else None,
        bytes=int(va.bytes) if va and va.bytes is not None else None,
        version_activa=va.version if va else None,
        num_versiones=int(nver),
        created_at=pl.created_at.isoformat() if pl.created_at else None,
    )


@router.get("", response_model=List[PlanoOut])
def listar_planos(
    carpeta_id: str = Query("", description="vacío = raíz (sin carpeta)"),
    proyecto_id: str = Query(""),
    q: str = Query(""),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    e = payload["empresa_id"]
    qry = db.query(Plano).filter(Plano.empresa_id == e)
    if carpeta_id:
        qry = qry.filter(Plano.carpeta_id == carpeta_id)
    else:
        qry = qry.filter(Plano.carpeta_id.is_(None))
    if proyecto_id:
        qry = qry.filter(Plano.proyecto_id == proyecto_id)
    if q:
        like = f"%{q.strip()}%"
        qry = qry.filter((Plano.nombre.ilike(like)) | (Plano.disciplina.ilike(like)))
    rows = qry.order_by(Plano.nombre.asc()).all()
    return [_plano_out(db, p) for p in rows]


def _crear_version(db: Session, empresa_id: str, plano_id: str, archivo_base64: str,
                   filename: str, subido_por: Optional[str], version_label: str) -> VersionPlano:
    _check_size(archivo_base64)
    ext = _ext(filename)
    vid = str(_uuid.uuid4())
    res = subir_archivo_base64(
        archivo_base64, folder=carpeta_planos(empresa_id),
        public_id=f"{plano_id}-{vid}", extension=ext)
    # Desactivar versiones previas
    db.query(VersionPlano).filter(
        VersionPlano.plano_id == plano_id, VersionPlano.es_version_activa == True
    ).update({VersionPlano.es_version_activa: False}, synchronize_session=False)
    v = VersionPlano(
        id=vid, plano_id=plano_id, empresa_id=empresa_id, version=version_label,
        url_cloudinary=res["secure_url"], public_id_cloudinary=res["public_id"],
        subido_por=subido_por, fecha=date.today(), es_version_activa=True,
        formato=res.get("format"), bytes=res.get("bytes"),
    )
    db.add(v)
    return v


@router.post("", response_model=PlanoDetalleOut, status_code=201)
def crear_plano(body: PlanoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _exigir_gestion(payload)
    e = payload["empresa_id"]
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")
    if not body.archivo_base64:
        raise HTTPException(status_code=422, detail="Archivo requerido")

    pl = Plano(
        id=str(_uuid.uuid4()), empresa_id=e, nombre=nombre,
        disciplina=(body.disciplina or None), descripcion=(body.descripcion or None),
        carpeta_id=body.carpeta_id or None, proyecto_id=body.proyecto_id or None,
        created_at=datetime.utcnow(),
    )
    db.add(pl)
    db.flush()  # obtener pl.id antes de la versión

    _crear_version(db, e, pl.id, body.archivo_base64, body.filename,
                   _subido_por(payload), "v1")
    db.commit()
    return _plano_detalle(db, pl)


@router.post("/{plano_id}/versiones", response_model=PlanoDetalleOut, status_code=201)
def subir_version(plano_id: str, body: VersionIn,
                  payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _exigir_gestion(payload)
    e = payload["empresa_id"]
    pl = db.query(Plano).filter(Plano.id == plano_id, Plano.empresa_id == e).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Plano no encontrado")
    if not body.archivo_base64:
        raise HTTPException(status_code=422, detail="Archivo requerido")
    nver = db.query(func.count(VersionPlano.id)).filter(VersionPlano.plano_id == plano_id).scalar() or 0
    label = (body.version or "").strip() or f"v{nver + 1}"
    _crear_version(db, e, plano_id, body.archivo_base64, body.filename, _subido_por(payload), label)
    db.commit()
    return _plano_detalle(db, pl)


def _plano_detalle(db: Session, pl: Plano) -> PlanoDetalleOut:
    base = _plano_out(db, pl)
    vers = db.query(VersionPlano).filter(VersionPlano.plano_id == pl.id).order_by(
        VersionPlano.created_at.desc()).all()
    versiones = [
        VersionOut(
            id=str(v.id), version=v.version, url=v.url_cloudinary,
            formato=v.formato, bytes=int(v.bytes) if v.bytes is not None else None,
            fecha=v.fecha.isoformat() if v.fecha else None,
            es_activa=bool(v.es_version_activa),
            subido_por=str(v.subido_por) if v.subido_por else None,
        ) for v in vers
    ]
    return PlanoDetalleOut(**base.model_dump(), versiones=versiones)


@router.get("/{plano_id}", response_model=PlanoDetalleOut)
def detalle_plano(plano_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    pl = db.query(Plano).filter(Plano.id == plano_id, Plano.empresa_id == payload["empresa_id"]).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Plano no encontrado")
    return _plano_detalle(db, pl)


@router.delete("/{plano_id}", status_code=204)
def eliminar_plano(plano_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _exigir_gestion(payload)
    e = payload["empresa_id"]
    pl = db.query(Plano).filter(Plano.id == plano_id, Plano.empresa_id == e).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Plano no encontrado")
    vers = db.query(VersionPlano).filter(VersionPlano.plano_id == plano_id).all()
    for v in vers:
        rtype = "image" if (v.formato or "").lower() in _IMG_EXT else "raw"
        eliminar_recurso_por_public_id(v.public_id_cloudinary, resource_type=rtype)
    # Borrar primero las versiones (FK), luego el plano
    db.query(VersionPlano).filter(VersionPlano.plano_id == plano_id).delete(synchronize_session=False)
    db.flush()
    db.delete(pl)
    db.commit()
