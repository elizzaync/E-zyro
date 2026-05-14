from app.core.config_cloudinary import cloudinary_uploader
import cloudinary.uploader
import logging
import re

def subir_imagen_cloudinary(base64_data: str, folder: str, public_id: str, is_perfil: bool = False) -> str:
    """
    Sube una imagen optimizada a Cloudinary.
    """
    try:
        # Cloudinary requiere el prefijo data URI; añadirlo si viene como base64 puro
        if not base64_data.startswith("data:"):
            base64_data = f"data:image/jpeg;base64,{base64_data}"
        # Aquí estamos aplicando exactamente f_auto y q_auto
        transformaciones = [
            {"fetch_format": "auto"},  # Equivalente a f_auto
            {"quality": "auto:good"}   # Equivalente a q_auto:good (peso mínimo, buena calidad visual)
        ]

        if is_perfil:
            # Añadimos el recorte inteligente facial
            # Equivalente en URL: c_fill,g_face,w_400,h_400
            transformaciones.insert(0, {
                "width": 400,
                "height": 400,
                "crop": "fill",
                "gravity": "face"
            })

        upload_result = cloudinary_uploader.upload(
            base64_data,
            folder=folder,
            public_id=public_id,
            overwrite=True,
            invalidate=True,
            transformation=transformaciones
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
    Sube un PDF a Cloudinary y devuelve su secure_url pública.
    Los PDFs subidos con resource_type="image" y type="upload" (default)
    son accesibles públicamente; no se necesita URL firmada.
    """
    try:
        import io
        pid = public_id.removesuffix(".pdf")
        upload_result = cloudinary.uploader.upload(
            io.BytesIO(pdf_bytes),
            public_id=pid,
            resource_type="image",
            format="pdf",
            overwrite=True,
            invalidate=True,
        )
        return upload_result["secure_url"]
    except Exception as e:
        logging.error(f"Error subiendo PDF (bytes) a Cloudinary: {str(e)}")
        raise Exception(f"Fallo al subir PDF a Cloudinary: {str(e)}")


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