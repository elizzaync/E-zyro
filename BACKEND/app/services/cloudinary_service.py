from app.core.config_cloudinary import cloudinary_uploader
import logging

def subir_imagen_cloudinary(base64_data: str, folder: str, public_id: str, is_perfil: bool = False) -> str:
    """
    Sube una imagen optimizada a Cloudinary.
    """
    try:
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