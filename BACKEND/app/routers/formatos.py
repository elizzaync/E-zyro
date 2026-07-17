"""
Router: /formatos — Biblioteca de Formatos (documentos PDF normados).

Reglas del módulo:
  - Ver/descargar: cualquier usuario interno autenticado (los técnicos usan
    ATS/PETAR en campo). ClienteExterno queda fuera por el candado global.
  - Crear/actualizar: RBAC 'formatos:gestionar' (admins por bypass).
  - SIN DELETE: un formato nunca se elimina; cada cambio de archivo crea una
    nueva fila en formato_documento_version y avanza version_actual. Las
    versiones anteriores se conservan (archivo incluido) para trazabilidad.
  - Auditoría: alta, nueva versión y descarga registran evento en audit_log.
"""
from __future__ import annotations

import base64 as _b64
import uuid as _uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.formato_documento import FormatoDocumento, FormatoDocumentoVersion
from ..schemas.formato_documento import (
    FormatoOut, FormatoVersionOut, FormatoCrearIn, FormatoActualizarIn,
)
from ..services.audit_service import registrar_evento
from ..services.cloudinary_service import subir_archivo_base64

router = APIRouter(prefix="/formatos", tags=["formatos"])

_MAX_PDF_BYTES = 20 * 1024 * 1024  # 20 MB, mismo tope que legajo/evidencias


# ── Helpers ───────────────────────────────────────────────────────────────────
def _decodificar_pdf(archivo_base64: str) -> bytes:
    """Decodifica y valida que el contenido sea un PDF real (magic bytes)."""
    payload = archivo_base64.split(",", 1)[1] if archivo_base64.startswith("data:") else archivo_base64
    try:
        raw = _b64.b64decode(payload)
    except Exception:
        raise HTTPException(status_code=422, detail="Archivo base64 inválido")
    if len(raw) > _MAX_PDF_BYTES:
        raise HTTPException(status_code=413, detail="El archivo supera los 20 MB")
    if not raw.startswith(b"%PDF"):
        raise HTTPException(status_code=422, detail="Solo se permiten archivos PDF")
    return raw


def _subir_pdf(empresa_id: str, archivo_base64: str) -> dict:
    folder = f"e-zyro/formatos/{empresa_id}"
    return subir_archivo_base64(archivo_base64, folder, str(_uuid.uuid4()), extension="pdf")


def _version_vigente(db: Session, f: FormatoDocumento) -> Optional[FormatoDocumentoVersion]:
    return (db.query(FormatoDocumentoVersion)
              .filter(FormatoDocumentoVersion.formato_id == f.id,
                      FormatoDocumentoVersion.numero_version == f.version_actual)
              .first())


def _out(db: Session, f: FormatoDocumento) -> FormatoOut:
    v = _version_vigente(db, f)
    total = (db.query(FormatoDocumentoVersion)
               .filter(FormatoDocumentoVersion.formato_id == f.id).count())
    return FormatoOut(
        id=str(f.id),
        nombre=f.nombre,
        tipo_formato=f.tipo_formato,
        version_actual=f.version_actual,
        archivo_url=(v.archivo_url if v else None),
        nombre_archivo=(v.nombre_archivo if v else None),
        actualizado_por_nombre=(v.subido_por_nombre if v else None),
        created_at=(f.created_at.isoformat() if f.created_at else None),
        updated_at=(f.updated_at.isoformat() if f.updated_at else
                    (f.created_at.isoformat() if f.created_at else None)),
        total_versiones=total,
    )


def _auditar(db: Session, request: Request, payload: dict, *, accion: str,
             formato: FormatoDocumento, detalle: dict | None = None) -> None:
    registrar_evento(
        accion=accion,
        usuario_id=payload.get("id"),
        usuario_nombre=payload.get("nombre") or payload.get("nombre_completo"),
        rol=payload.get("rol"),
        empresa_id=payload.get("empresa_id"),
        entidad="formato_documento",
        entidad_id=str(formato.id),
        metodo_http=request.method,
        ruta=str(request.url.path),
        detalle={"nombre": formato.nombre, "version": formato.version_actual,
                 **(detalle or {})},
        db=db,
    )


def _buscar_formato(db: Session, empresa_id: str, formato_id: str) -> FormatoDocumento:
    f = (db.query(FormatoDocumento)
           .filter(FormatoDocumento.id == formato_id,
                   FormatoDocumento.empresa_id == empresa_id,
                   FormatoDocumento.activo.is_(True))
           .first())
    if not f:
        raise HTTPException(status_code=404, detail="Formato no encontrado")
    return f


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.get("", response_model=List[FormatoOut])
def listar(
    q: Optional[str] = Query(None, description="busca en nombre/tipo"),
    tipo: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    qry = db.query(FormatoDocumento).filter(
        FormatoDocumento.empresa_id == empresa_id,
        FormatoDocumento.activo.is_(True),
    )
    if tipo:
        qry = qry.filter(FormatoDocumento.tipo_formato == tipo)
    if q:
        like = f"%{q.strip()}%"
        qry = qry.filter(or_(FormatoDocumento.nombre.ilike(like),
                             FormatoDocumento.tipo_formato.ilike(like)))
    rows = qry.order_by(FormatoDocumento.nombre.asc()).all()
    return [_out(db, f) for f in rows]


@router.get("/{formato_id}/versiones", response_model=List[FormatoVersionOut])
def historial(formato_id: str, payload: dict = Depends(verificar_token),
              db: Session = Depends(get_db)):
    f = _buscar_formato(db, payload["empresa_id"], formato_id)
    versiones = (db.query(FormatoDocumentoVersion)
                   .filter(FormatoDocumentoVersion.formato_id == f.id)
                   .order_by(FormatoDocumentoVersion.numero_version.desc())
                   .all())
    return [FormatoVersionOut(
        id=str(v.id),
        numero_version=v.numero_version,
        archivo_url=v.archivo_url,
        nombre_archivo=v.nombre_archivo,
        tamano_bytes=v.tamano_bytes,
        nota=v.nota,
        origen=v.origen,
        subido_por_nombre=v.subido_por_nombre,
        created_at=(v.created_at.isoformat() if v.created_at else None),
        es_vigente=(v.numero_version == f.version_actual),
    ) for v in versiones]


@router.get("/{formato_id}/enlace")
def enlace_descarga(formato_id: str, request: Request,
                    version: Optional[int] = Query(None, description="versión puntual; por defecto la vigente"),
                    payload: dict = Depends(verificar_token),
                    db: Session = Depends(get_db)):
    """Devuelve la URL del PDF y registra la descarga en audit_log.
    La ruta NO termina en /descargar a propósito: el evento se registra aquí
    con metadatos ricos y el middleware de auditoría no lo duplica."""
    f = _buscar_formato(db, payload["empresa_id"], formato_id)
    num = version or f.version_actual
    v = (db.query(FormatoDocumentoVersion)
           .filter(FormatoDocumentoVersion.formato_id == f.id,
                   FormatoDocumentoVersion.numero_version == num)
           .first())
    if not v:
        raise HTTPException(status_code=404, detail="Versión no encontrada")
    _auditar(db, request, payload, accion="DOWNLOAD", formato=f,
             detalle={"version_descargada": num,
                      "nombre_archivo": v.nombre_archivo})
    return {"url": v.archivo_url, "version": num, "nombre_archivo": v.nombre_archivo}


@router.post("", response_model=FormatoOut, status_code=201)
def crear(body: FormatoCrearIn, request: Request,
          payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "formatos", "gestionar")
    empresa_id = payload["empresa_id"]

    nombre = (body.nombre or "").strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="El nombre es obligatorio")
    raw = _decodificar_pdf(body.archivo_base64)

    duplicado = db.query(FormatoDocumento).filter(
        FormatoDocumento.empresa_id == empresa_id,
        FormatoDocumento.activo.is_(True),
        FormatoDocumento.nombre.ilike(nombre),
    ).first()
    if duplicado:
        raise HTTPException(status_code=409,
                            detail="Ya existe un formato con ese nombre; actualízalo con una nueva versión")

    res = _subir_pdf(empresa_id, body.archivo_base64)

    f = FormatoDocumento(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        nombre=nombre,
        tipo_formato=(body.tipo_formato or "").strip() or None,
        version_actual=1,
        creado_por_id=payload.get("id"),
        created_at=datetime.utcnow(),
    )
    v = FormatoDocumentoVersion(
        id=str(_uuid.uuid4()),
        formato_id=f.id,
        numero_version=1,
        archivo_url=res.get("secure_url", ""),
        archivo_public_id=res.get("public_id"),
        nombre_archivo=body.archivo_nombre,
        tamano_bytes=len(raw),
        nota=(body.nota or "").strip() or None,
        origen="sistema",
        subido_por_id=payload.get("id"),
        subido_por_nombre=payload.get("nombre") or payload.get("nombre_completo"),
        created_at=datetime.utcnow(),
    )
    db.add(f)
    db.add(v)
    db.flush()
    _auditar(db, request, payload, accion="FORMATO_CREAR",
             formato=f, detalle={"nombre_archivo": body.archivo_nombre})
    return _out(db, f)


@router.put("/{formato_id}", response_model=FormatoOut)
def actualizar(formato_id: str, body: FormatoActualizarIn, request: Request,
               payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """Actualiza metadatos y/o publica una NUEVA versión del PDF.
    Nunca borra el archivo anterior: el historial completo se conserva."""
    exigir_permiso(db, payload, "formatos", "gestionar")
    empresa_id = payload["empresa_id"]
    f = _buscar_formato(db, empresa_id, formato_id)

    cambios: dict = {}
    if body.nombre is not None and body.nombre.strip() and body.nombre.strip() != f.nombre:
        cambios["nombre_anterior"] = f.nombre
        f.nombre = body.nombre.strip()
    if body.tipo_formato is not None:
        f.tipo_formato = body.tipo_formato.strip() or None

    if body.archivo_base64:
        raw = _decodificar_pdf(body.archivo_base64)
        res = _subir_pdf(empresa_id, body.archivo_base64)
        nueva = f.version_actual + 1
        v = FormatoDocumentoVersion(
            id=str(_uuid.uuid4()),
            formato_id=f.id,
            numero_version=nueva,
            archivo_url=res.get("secure_url", ""),
            archivo_public_id=res.get("public_id"),
            nombre_archivo=body.archivo_nombre,
            tamano_bytes=len(raw),
            nota=(body.nota or "").strip() or None,
            origen="sistema",
            subido_por_id=payload.get("id"),
            subido_por_nombre=payload.get("nombre") or payload.get("nombre_completo"),
            created_at=datetime.utcnow(),
        )
        db.add(v)
        cambios["de_version"] = f.version_actual
        cambios["a_version"] = nueva
        f.version_actual = nueva

    if not cambios and body.archivo_base64 is None and body.nota is None:
        raise HTTPException(status_code=400, detail="Nada que actualizar")

    f.actualizado_por_id = payload.get("id")
    f.updated_at = datetime.utcnow()
    db.flush()
    _auditar(db, request, payload, accion="FORMATO_ACTUALIZAR",
             formato=f, detalle=cambios)
    return _out(db, f)
