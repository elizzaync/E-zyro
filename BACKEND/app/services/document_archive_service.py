"""
Archivo centralizado de documentos generados — con deduplicación (Fase 3).

`archivar(...)` es EL ÚNICO paso obligado: todo PDF/Excel/CSV generado pasa
(o irá pasando) por aquí antes de entregarse al usuario.

Identidad lógica = public_id determinístico en Cloudinary:
    "e-zyro/{empresa_id}/archivo/{modulo}/{slug}"
  - misma identidad + mismo hash SHA-256 → NO se re-sube: solo incrementa
    `descargas` (audit DOWNLOAD).
  - misma identidad + hash distinto     → se sobrescribe el MISMO public_id
    (overwrite=True, invalidate=True) y sube `version` (audit EXPORT).
  - identidad nueva                     → sube y crea la fila (audit EXPORT).

Best-effort en la nube: si Cloudinary falla, la fila se registra igual sin URL
y la descarga del usuario NUNCA se rompe.
"""
from __future__ import annotations

import hashlib
import logging
import re
import unicodedata
import uuid
from datetime import datetime

from sqlalchemy.orm import Session

from app.models.documento_archivo import DocumentoArchivo
from app.services.audit_service import registrar_evento

logger = logging.getLogger("documentos_archivo")

TIPOS = ("pdf", "excel", "csv", "export", "otro")


def slug_archivo(texto: str) -> str:
    """Slug seguro para public_id de Cloudinary (sin tildes/espacios/raros)."""
    t = unicodedata.normalize("NFKD", texto or "").encode("ascii", "ignore").decode()
    t = re.sub(r"[^A-Za-z0-9._-]+", "_", t).strip("_")
    return t[:150] or "documento"


def _subir(contenido: bytes, identidad: str, ext: str) -> tuple[str | None, str | None]:
    """Sube a Cloudinary con public_id = identidad (determinístico).
    Devuelve (url, public_id_final) o (None, None) si falló (best-effort)."""
    try:
        from app.services.cloudinary_service import subir_bytes_raw_cloudinary
        url = subir_bytes_raw_cloudinary(contenido, public_id=identidad, ext=ext)
        pid = identidad
        if ext:
            e = ext.lstrip(".").lower()
            if not pid.lower().endswith("." + e):
                pid = f"{pid}.{e}"
        return url, pid
    except Exception as e:  # noqa: BLE001 — la descarga del usuario no se rompe
        logger.warning("Cloudinary falló al archivar %s: %s", identidad, e)
        return None, None


def archivar(db: Session, *, contenido: bytes, nombre: str, tipo: str,
             modulo: str, identidad: str, entidad_tipo: str | None = None,
             entidad_id: str | None = None, usuario_id: str | None = None,
             empresa_id: str | None = None, ext: str = "") -> DocumentoArchivo:
    """Registra (con dedup) un documento generado. Ver docstring del módulo."""
    sha = hashlib.sha256(contenido).hexdigest()
    identidad = identidad[:300]
    fila = db.query(DocumentoArchivo).filter(
        DocumentoArchivo.identidad == identidad).first()

    # ── Mismo contenido: no re-subir, solo contar la descarga ────────────────
    if fila is not None and fila.hash_sha256 == sha:
        fila.descargas = (fila.descargas or 0) + 1
        db.commit()
        registrar_evento(
            accion="DOWNLOAD", usuario_id=usuario_id, empresa_id=empresa_id,
            entidad="documento_archivo", entidad_id=str(fila.id),
            detalle={"identidad": identidad, "nombre": fila.nombre,
                     "dedup": True, "descargas": fila.descargas},
        )
        return fila

    url, pid = _subir(contenido, identidad, ext)
    ahora = datetime.utcnow()

    if fila is not None:
        # ── Contenido nuevo bajo la misma identidad: versión++ ───────────────
        fila.nombre = (nombre or fila.nombre)[:200]
        fila.tipo = tipo if tipo in TIPOS else "otro"
        fila.hash_sha256 = sha
        fila.tamano_bytes = len(contenido)
        fila.fecha_actualizacion = ahora
        fila.version = (fila.version or 1) + 1
        fila.descargas = (fila.descargas or 0) + 1
        if url:
            fila.cloudinary_url = url
            fila.cloudinary_public_id = pid
    else:
        fila = DocumentoArchivo(
            id=str(uuid.uuid4()),
            nombre=(nombre or "documento")[:200],
            tipo=tipo if tipo in TIPOS else "otro",
            modulo_origen=(modulo or "")[:50] or None,
            entidad_tipo=(entidad_tipo or "")[:60] or None,
            entidad_id=(str(entidad_id) if entidad_id else None),
            identidad=identidad,
            generado_por=usuario_id,
            empresa_id=empresa_id,
            fecha_creacion=ahora,
            tamano_bytes=len(contenido),
            hash_sha256=sha,
            cloudinary_public_id=pid,
            cloudinary_url=url,
            version=1,
            descargas=1,
        )
        db.add(fila)
    db.commit()

    registrar_evento(
        accion="EXPORT", usuario_id=usuario_id, empresa_id=empresa_id,
        entidad="documento_archivo", entidad_id=str(fila.id),
        detalle={"identidad": identidad, "nombre": fila.nombre,
                 "version": fila.version, "tamanoBytes": fila.tamano_bytes,
                 "subidoACloudinary": bool(url)},
    )
    return fila


def registrar_documento_existente(db: Session, *, contenido: bytes, nombre: str,
                                  tipo: str, modulo: str, identidad: str,
                                  url: str | None, usuario_id: str | None = None,
                                  empresa_id: str | None = None,
                                  entidad_tipo: str | None = None,
                                  entidad_id: str | None = None) -> None:
    """Upsert de la fila documento_archivo para un asset YA subido a Cloudinary
    por otra vía (p. ej. subir_pdf_bytes_cloudinary). No re-sube nada.
    Best-effort: nunca lanza."""
    try:
        sha = hashlib.sha256(contenido).hexdigest()
        identidad = identidad[:300]
        ahora = datetime.utcnow()
        fila = db.query(DocumentoArchivo).filter(
            DocumentoArchivo.identidad == identidad).first()
        if fila is not None:
            if fila.hash_sha256 != sha:
                fila.version = (fila.version or 1) + 1
                fila.hash_sha256 = sha
                fila.tamano_bytes = len(contenido)
                fila.fecha_actualizacion = ahora
            fila.nombre = (nombre or fila.nombre)[:200]
            if url:
                fila.cloudinary_url = url
                fila.cloudinary_public_id = identidad
        else:
            db.add(DocumentoArchivo(
                id=str(uuid.uuid4()),
                nombre=(nombre or "documento")[:200],
                tipo=tipo if tipo in TIPOS else "otro",
                modulo_origen=(modulo or "")[:50] or None,
                entidad_tipo=(entidad_tipo or "")[:60] or None,
                entidad_id=(str(entidad_id) if entidad_id else None),
                identidad=identidad,
                generado_por=usuario_id,
                empresa_id=empresa_id,
                fecha_creacion=ahora,
                tamano_bytes=len(contenido),
                hash_sha256=sha,
                cloudinary_public_id=identidad,
                cloudinary_url=url,
                version=1,
                descargas=0,
            ))
        db.commit()
    except Exception as e:  # noqa: BLE001
        logger.warning("registrar_documento_existente(%s) falló: %s", identidad, e)
        try:
            db.rollback()
        except Exception:
            pass
