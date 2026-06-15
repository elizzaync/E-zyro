"""
Router: /documentos-sst — Repositorio de documentos de cumplimiento / SST.

Almacena y organiza homologaciones, ATS, PETAR (y otros) por (cliente, tipo),
con control de vencimiento. Lecturas para la empresa; crear/editar/eliminar
protegidos por RBAC (módulo 'documentos_sst').
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.documento_sst import DocumentoSst
from ..models.cliente import Cliente
from ..schemas.documento_sst import (
    DocumentoSstOut, DocumentoSstCrearIn, DocumentoSstEditarIn,
)
from ..services.cloudinary_service import (
    subir_archivo_base64, eliminar_recurso_por_public_id,
)

router = APIRouter(prefix="/documentos-sst", tags=["documentos_sst"])

_DIAS_AVISO = 30  # umbral "por vencer"


# ── Helpers ───────────────────────────────────────────────────────────────────
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


def _clientes_map(db: Session, empresa_id: str) -> dict[str, str]:
    rows = db.query(Cliente.id, Cliente.razon_social).filter(
        Cliente.empresa_id == empresa_id
    ).all()
    return {str(r.id): (r.razon_social or "") for r in rows}


def _out(d: DocumentoSst, clientes: dict[str, str]) -> DocumentoSstOut:
    estado, dias = _estado(d.fecha_vencimiento)
    return DocumentoSstOut(
        id=str(d.id),
        tipo=d.tipo,
        titulo=d.titulo,
        cliente_id=(str(d.cliente_id) if d.cliente_id else None),
        cliente_nombre=(clientes.get(str(d.cliente_id)) if d.cliente_id else None),
        entidad_emisora=d.entidad_emisora,
        codigo=d.codigo,
        fecha_emision=(d.fecha_emision.isoformat() if d.fecha_emision else None),
        fecha_vencimiento=(d.fecha_vencimiento.isoformat() if d.fecha_vencimiento else None),
        estado=estado,
        dias_para_vencer=dias,
        archivo_url=d.archivo_url,
        nombre_archivo=d.nombre_archivo,
        formato=d.formato,
        observaciones=d.observaciones,
        created_at=(d.created_at.isoformat() if d.created_at else None),
    )


def _subir_archivo(empresa_id: str, base64_data: str, nombre: Optional[str]) -> dict:
    ext = ""
    if nombre and "." in nombre:
        ext = nombre.rsplit(".", 1)[1]
    folder = f"e-zyro/documentos_sst/{empresa_id}"
    return subir_archivo_base64(base64_data, folder, str(_uuid.uuid4()), extension=ext)


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.get("", response_model=List[DocumentoSstOut])
def listar(
    cliente_id: Optional[str] = Query(None),
    tipo:       Optional[str] = Query(None),
    estado:     Optional[str] = Query(None, description="vigente|por_vencer|vencida|sin_fecha"),
    q:          Optional[str] = Query(None, description="busca en título/código/entidad"),
    limit:      int = Query(100, ge=1, le=300),
    offset:     int = Query(0, ge=0),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    qry = db.query(DocumentoSst).filter(DocumentoSst.empresa_id == empresa_id)
    if cliente_id:
        qry = qry.filter(DocumentoSst.cliente_id == cliente_id)
    if tipo:
        qry = qry.filter(DocumentoSst.tipo == tipo)
    if q:
        like = f"%{q.strip()}%"
        qry = qry.filter(or_(
            DocumentoSst.titulo.ilike(like),
            DocumentoSst.codigo.ilike(like),
            DocumentoSst.entidad_emisora.ilike(like),
        ))
    rows = qry.order_by(DocumentoSst.created_at.desc()).offset(offset).limit(limit).all()
    clientes = _clientes_map(db, empresa_id)
    out = [_out(d, clientes) for d in rows]
    if estado:
        out = [o for o in out if o.estado == estado]
    return out


@router.get("/{doc_id}", response_model=DocumentoSstOut)
def obtener(doc_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    d = db.query(DocumentoSst).filter(
        DocumentoSst.id == doc_id, DocumentoSst.empresa_id == empresa_id
    ).first()
    if not d:
        raise HTTPException(status_code=404, detail="Documento no encontrado")
    return _out(d, _clientes_map(db, empresa_id))


@router.post("", response_model=DocumentoSstOut, status_code=201)
def crear(body: DocumentoSstCrearIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "documentos_sst", "crear")
    empresa_id = payload["empresa_id"]
    if not body.titulo or not body.titulo.strip():
        raise HTTPException(status_code=400, detail="El título es obligatorio")

    archivo_url = archivo_public_id = formato = None
    if body.archivo_base64:
        res = _subir_archivo(empresa_id, body.archivo_base64, body.archivo_nombre)
        archivo_url       = res.get("secure_url")
        archivo_public_id = res.get("public_id")
        formato           = res.get("format")

    d = DocumentoSst(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        cliente_id=body.cliente_id,
        tipo=(body.tipo or "homologacion"),
        titulo=body.titulo.strip(),
        entidad_emisora=body.entidad_emisora,
        codigo=body.codigo,
        fecha_emision=_parse_fecha(body.fecha_emision),
        fecha_vencimiento=_parse_fecha(body.fecha_vencimiento),
        archivo_url=archivo_url,
        archivo_public_id=archivo_public_id,
        nombre_archivo=body.archivo_nombre,
        formato=formato,
        observaciones=body.observaciones,
        creado_por_id=payload.get("id"),
    )
    db.add(d)
    db.commit()
    db.refresh(d)
    return _out(d, _clientes_map(db, empresa_id))


@router.put("/{doc_id}", response_model=DocumentoSstOut)
def editar(doc_id: str, body: DocumentoSstEditarIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "documentos_sst", "editar")
    empresa_id = payload["empresa_id"]
    d = db.query(DocumentoSst).filter(
        DocumentoSst.id == doc_id, DocumentoSst.empresa_id == empresa_id
    ).first()
    if not d:
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    if body.titulo is not None:
        d.titulo = body.titulo.strip()
    if body.tipo is not None:
        d.tipo = body.tipo
    if body.cliente_id is not None:
        d.cliente_id = body.cliente_id or None
    if body.entidad_emisora is not None:
        d.entidad_emisora = body.entidad_emisora
    if body.codigo is not None:
        d.codigo = body.codigo
    if body.fecha_emision is not None:
        d.fecha_emision = _parse_fecha(body.fecha_emision)
    if body.fecha_vencimiento is not None:
        d.fecha_vencimiento = _parse_fecha(body.fecha_vencimiento)
    if body.observaciones is not None:
        d.observaciones = body.observaciones

    if body.archivo_base64:
        # Reemplaza el archivo: borra el anterior en la nube (best-effort).
        if d.archivo_public_id:
            rtype = "image" if (d.formato or "").lower() in (
                "jpg", "jpeg", "png", "webp", "gif", "bmp") else "raw"
            eliminar_recurso_por_public_id(d.archivo_public_id, resource_type=rtype)
        res = _subir_archivo(empresa_id, body.archivo_base64, body.archivo_nombre)
        d.archivo_url       = res.get("secure_url")
        d.archivo_public_id = res.get("public_id")
        d.formato           = res.get("format")
        if body.archivo_nombre is not None:
            d.nombre_archivo = body.archivo_nombre

    db.commit()
    db.refresh(d)
    return _out(d, _clientes_map(db, empresa_id))


@router.delete("/{doc_id}", status_code=204)
def eliminar(doc_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "documentos_sst", "eliminar")
    empresa_id = payload["empresa_id"]
    d = db.query(DocumentoSst).filter(
        DocumentoSst.id == doc_id, DocumentoSst.empresa_id == empresa_id
    ).first()
    if not d:
        raise HTTPException(status_code=404, detail="Documento no encontrado")
    if d.archivo_public_id:
        rtype = "image" if (d.formato or "").lower() in (
            "jpg", "jpeg", "png", "webp", "gif", "bmp") else "raw"
        eliminar_recurso_por_public_id(d.archivo_public_id, resource_type=rtype)
    db.delete(d)
    db.commit()
