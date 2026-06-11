from app.core.config_cloudinary import cloudinary_uploader
import cloudinary.uploader
import logging
import re

def subir_imagen_cloudinary(base64_data: str, folder: str, public_id: str, is_perfil: bool = False) -> str:
    """
    Sube una imagen optimizada a Cloudinary.
    """
    try:
        if not base64_data:
            raise Exception("No se recibió ninguna imagen para subir.")

        # Cloudinary requiere el prefijo data URI; añadirlo si viene como base64 puro
        if not base64_data.startswith("data:"):
            base64_data = f"data:image/jpeg;base64,{base64_data}"

        params = {
            "folder": folder,
            "public_id": public_id,
            "overwrite": True,
            "invalidate": True,
        }

        if is_perfil:
            params["transformation"] = [
                {"crop": "fill", "gravity": "face", "width": 400, "height": 400, "quality": "auto:good"}
            ]

        # IMPORTANTE: Asegúrate de usar el uploader que tiene la configuración
        upload_result = cloudinary.uploader.upload(
            base64_data,
            **params
        )

        return upload_result.get("secure_url")

    except Exception as e:
        logging.error(f"Error subiendo imagen a Cloudinary: {str(e)}")
        raise Exception(f"Fallo al procesar la imagen en la nube: {str(e)}")

# FUNCIÓN PARA ELIMINAR LA FOTO VIEJA
def eliminar_imagen_cloudinary(url: str):
    """
    Extrae el ID público de una URL de Cloudinary y elimina el archivo de la nube.
    """
    if not url or "res.cloudinary.com" not in url:
        return

    try:
        # Ejemplo URL: https://res.cloudinary.com/demo/image/upload/v1714000/e-zyro/perfiles/uuid_harold.webp
        partes = url.split("/upload/")
        if len(partes) > 1:
            ruta = partes[1] # "v1714000/e-zyro/perfiles/uuid_harold.webp"

            # 1. Quitamos la versión de la URL (el "v1714000/") si existe
            ruta_sin_version = re.sub(r'^v\d+/', '', ruta)

            # 2. Le quitamos la extensión (".webp", ".jpg") para obtener el public_id exacto
            public_id = ruta_sin_version.rsplit('.', 1)[0]

            # 3. ¡Destruimos la foto vieja en Cloudinary!
            cloudinary_uploader.destroy(public_id)
            logging.info(f"Foto antigua eliminada con éxito: {public_id}")

    except Exception as e:
        logging.error(f"Error al intentar eliminar foto antigua en Cloudinary: {str(e)}")


def subir_pdf_bytes_cloudinary(pdf_bytes: bytes, public_id: str) -> str:
    """
    Sube un PDF a Cloudinary como recurso raw y devuelve su secure_url.
    resource_type="raw" evita el procesamiento interno del SDK que referencia
    la variable full_public_id causando NameError en ciertas versiones.
    """
    try:
        import io
        # Asegurar que el public_id termine en .pdf para que la URL sea descargable
        pid = public_id.removesuffix(".pdf") + ".pdf"
        upload_result = cloudinary.uploader.upload(
            io.BytesIO(pdf_bytes),
            public_id=pid,
            resource_type="raw",
            overwrite=True,
            invalidate=True,
        )
        return upload_result["secure_url"]
    except Exception as e:
        logging.error(f"Error subiendo PDF (bytes) a Cloudinary: {str(e)}")
        raise Exception(f"Fallo al subir PDF a Cloudinary: {str(e)}")


_ALLOWED_EVIDENCE_TYPES = {
    "image/jpeg", "image/jpg", "image/png", "image/webp",
    "image/gif", "application/pdf",
}
_MAX_EVIDENCE_BYTES = 20 * 1024 * 1024  # 20 MB


async def subir_archivo_cloudinary(archivo, folder: str) -> str:
    """
    Sube un UploadFile de FastAPI a Cloudinary.
    Acepta imágenes y PDFs hasta 20 MB.
    """
    import io
    from fastapi import HTTPException

    content_type = (archivo.content_type or "").split(";")[0].strip().lower()
    if content_type not in _ALLOWED_EVIDENCE_TYPES:
        raise HTTPException(
            status_code=422,
            detail=f"Tipo de archivo no permitido: {content_type}. "
                   "Se aceptan imágenes (jpg, png, webp, gif) y PDF.",
        )

    try:
        contenido = await archivo.read()

        if len(contenido) > _MAX_EVIDENCE_BYTES:
            raise HTTPException(status_code=413, detail="El archivo supera el límite de 20 MB")

        upload_result = cloudinary.uploader.upload(
            io.BytesIO(contenido),
            folder=folder,
            resource_type="auto",
            overwrite=False,
        )
        return upload_result.get("secure_url", "")
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error subiendo archivo a Cloudinary: {str(e)}")
        raise Exception(f"Fallo al subir archivo a Cloudinary: {str(e)}")


# Formatos de imagen → resource_type 'image'; el resto (pdf, dwg, dxf, etc) → 'raw'
_IMAGEN_EXT = {"jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff"}


def subir_archivo_base64(base64_data: str, folder: str, public_id: str,
                         extension: str = "") -> dict:
    """Sube un archivo (base64) a Cloudinary eligiendo resource_type por extensión.
    Imágenes → 'image'; PDF/DWG/DXF/otros → 'raw' (con la extensión en el
    public_id para que la URL sea descargable/abrible).
    Devuelve dict {secure_url, public_id, bytes, format, resource_type}."""
    import io, base64 as _b64

    ext = (extension or "").lower().lstrip(".")
    es_imagen = ext in _IMAGEN_EXT
    resource_type = "image" if es_imagen else "raw"

    # Quitar prefijo data URI si viene
    payload = base64_data.split(",", 1)[1] if base64_data.startswith("data:") and "," in base64_data else base64_data
    try:
        raw = _b64.b64decode(payload)
    except Exception as e:
        raise Exception(f"base64 inválido: {e}")

    pid = public_id
    if resource_type == "raw" and ext and not pid.lower().endswith("." + ext):
        pid = f"{pid}.{ext}"

    try:
        res = cloudinary.uploader.upload(
            io.BytesIO(raw),
            folder=folder,
            public_id=pid,
            resource_type=resource_type,
            overwrite=True,
            invalidate=True,
        )
        return {
            "secure_url": res.get("secure_url", ""),
            "public_id": res.get("public_id", ""),
            "bytes": res.get("bytes"),
            "format": res.get("format") or ext,
            "resource_type": res.get("resource_type", resource_type),
        }
    except Exception as e:
        logging.error(f"Error subiendo archivo base64 a Cloudinary: {str(e)}")
        raise Exception(f"Fallo al subir archivo a Cloudinary: {str(e)}")


def subir_pdf_cloudinary(base64_data: str, public_id: str) -> str:
    """
    Sube un PDF en base64 a Cloudinary como recurso raw.
    Acepta data URI completo (data:application/pdf;base64,...) o solo la parte base64.
    """
    try:
        if ',' in base64_data:
            base64_data = base64_data.split(',')[1]

        upload_result = cloudinary.uploader.upload(
            f"data:application/pdf;base64,{base64_data}",
            public_id=public_id,
            resource_type="raw",
            overwrite=True,
            invalidate=True,
        )
        return upload_result.get("secure_url", "")
    except Exception as e:
        logging.error(f"Error subiendo PDF a Cloudinary: {str(e)}")
        raise Exception(f"Fallo al subir PDF a Cloudinary: {str(e)}")


# ──────────────────────────────────────────────────────────────────────────
# Subida + indexado en recurso_cloudinary (Fase 1 — Galería Global)
# ──────────────────────────────────────────────────────────────────────────
def registrar_recurso(db, *, empresa_id, public_id, secure_url, folder,
                      entidad_tipo, entidad_id=None, recurso_tipo="imagen",
                      descripcion=None, bytes=None, formato=None, creado_por_id=None):
    """Inserta (sin subir) una fila de índice. Útil para backfill o cuando el
    asset ya fue subido por otra vía."""
    import uuid as _uuid
    from app.models.recurso_cloudinary import RecursoCloudinary
    rec = RecursoCloudinary(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, public_id=public_id,
        secure_url=secure_url, folder=folder, recurso_tipo=recurso_tipo,
        entidad_tipo=entidad_tipo, entidad_id=entidad_id, descripcion=descripcion,
        bytes=bytes, formato=formato, creado_por_id=creado_por_id,
    )
    db.add(rec)
    db.commit()
    return rec


def subir_e_indexar(db, *, empresa_id, base64_data, folder, public_id,
                    entidad_tipo, entidad_id=None, descripcion=None,
                    creado_por_id=None, is_perfil=False):
    """Sube una imagen a `folder` e indexa el recurso. Devuelve la fila RecursoCloudinary."""
    if not base64_data.startswith("data:"):
        base64_data = f"data:image/jpeg;base64,{base64_data}"
    params = {"folder": folder, "public_id": public_id, "overwrite": True, "invalidate": True}
    if is_perfil:
        params["transformation"] = [
            {"crop": "fill", "gravity": "face", "width": 400, "height": 400, "quality": "auto:good"}
        ]
    res = cloudinary.uploader.upload(base64_data, **params)
    return registrar_recurso(
        db, empresa_id=empresa_id, public_id=res.get("public_id"),
        secure_url=res.get("secure_url"), folder=folder, entidad_tipo=entidad_tipo,
        entidad_id=entidad_id, recurso_tipo="imagen", descripcion=descripcion,
        bytes=res.get("bytes"), formato=res.get("format"), creado_por_id=creado_por_id,
    )


def eliminar_recurso_por_public_id(public_id: str, resource_type: str = "image"):
    """Destruye un asset por su public_id. Resiliente: no lanza si Cloudinary falla."""
    if not public_id:
        return
    try:
        cloudinary_uploader.destroy(public_id, resource_type=resource_type, invalidate=True)
        logging.info(f"Recurso Cloudinary eliminado: {public_id}")
    except Exception as e:
        logging.error(f"No se pudo eliminar recurso Cloudinary {public_id}: {e}")