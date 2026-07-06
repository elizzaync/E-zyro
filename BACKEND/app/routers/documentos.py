"""
Router: /documentos (Archivo centralizado · Gestión de TIC)

Listado del archivo centralizado de documentos generados (documento_archivo):
qué se generó, quién, cuándo, versión, hash y URL en Cloudinary.
Gate Soporte idéntico al de backups.py.
"""
from __future__ import annotations

import unicodedata

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.core.security import verificar_token
from app.db.database import get_db
from app.models.documento_archivo import DocumentoArchivo
from app.models.usuario import Usuario

router = APIRouter(prefix="/documentos", tags=["documentos"])


# ── Autorización: solo Soporte / TI / admin total (clon de backups.py) ────────

def _autorizar_soporte(payload: dict) -> None:
    if payload.get("admin_total"):
        return
    rol = (payload.get("rol") or "").strip().lower()
    rol = unicodedata.normalize("NFC", rol).replace("\xa0", " ")
    if rol in ("soporte", "ti", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Solo Soporte puede ver el archivo de documentos")


def _dto(db: Session, d: DocumentoArchivo) -> dict:
    nombre_gen = None
    if d.generado_por:
        u = db.query(Usuario.nombre, Usuario.apellido).filter(
            Usuario.id == d.generado_por).first()
        nombre_gen = f"{u.nombre} {u.apellido}".strip() if u else None
    return {
        "id": str(d.id),
        "nombre": d.nombre,
        "tipo": d.tipo,
        "moduloOrigen": d.modulo_origen,
        "entidadTipo": d.entidad_tipo,
        "generadoPorNombre": nombre_gen or ("Sistema" if not d.generado_por else None),
        "fechaCreacion": d.fecha_creacion.isoformat() if d.fecha_creacion else None,
        "fechaActualizacion": d.fecha_actualizacion.isoformat() if d.fecha_actualizacion else None,
        "tamanoBytes": d.tamano_bytes,
        "hashSha256": d.hash_sha256,
        "cloudinaryUrl": d.cloudinary_url,
        "version": d.version,
        "descargas": d.descargas,
    }


@router.get("")
def listar_documentos(
    tipo:      str = Query(""),
    modulo:    str = Query(""),
    q:         str = Query(""),
    page:      int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=200),
    payload:   dict = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _autorizar_soporte(payload)
    base = db.query(DocumentoArchivo)
    if tipo and tipo != "todos":
        base = base.filter(DocumentoArchivo.tipo == tipo)
    if modulo and modulo != "todos":
        base = base.filter(DocumentoArchivo.modulo_origen == modulo)
    if q:
        patron = f"%{q}%"
        base = base.filter(or_(DocumentoArchivo.nombre.ilike(patron),
                               DocumentoArchivo.identidad.ilike(patron)))
    total = base.with_entities(func.count(DocumentoArchivo.id)).scalar() or 0
    filas = (base.order_by(DocumentoArchivo.fecha_creacion.desc())
             .offset((page - 1) * page_size).limit(page_size).all())
    return {"items": [_dto(db, d) for d in filas], "total": total,
            "page": page, "pageSize": page_size}
