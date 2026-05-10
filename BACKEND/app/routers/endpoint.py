"""
endpoint.py — Servidor FastAPI para verificación facial de asistencia.

Instalar dependencias:
    pip install fastapi uvicorn face_recognition opencv-python numpy

Ejecutar:
    uvicorn endpoint:app --host 0.0.0.0 --port 8000 --reload
"""

import base64
import io
import logging
from datetime import datetime

import face_recognition
import numpy as np
import uvicorn
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ─────────────────────────────────────────────
#  CONFIGURACIÓN
# ─────────────────────────────────────────────
CONFIG = {
    "UMBRAL_APROBADO": 0.42,
    # FIX: "small" es 5x más rápido que "large" con pérdida mínima de precisión.
    # FIX: jitters=1 elimina el principal cuello de botella de latencia.
    "JITTER_NUM": 1,
    "MODELO_ENCODING": "small",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
#  APP
# ─────────────────────────────────────────────
app = FastAPI(
    title="API de Verificación de Asistencia",
    description="Verifica identidad facial para marcar asistencia.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restringir en producción
    allow_methods=["POST"],
    allow_headers=["*"],
)


# ─────────────────────────────────────────────
#  SCHEMAS
# ─────────────────────────────────────────────
class SolicitudVerificacion(BaseModel):
    imagen_base: str = Field(..., description="Imagen de referencia en base64")
    imagen_selfie: str = Field(..., description="Selfie capturada en base64")
    metadata: dict = Field(default={}, description="Datos adicionales (id_empleado, sede, etc.)")


class RespuestaVerificacion(BaseModel):
    status: str          # APROBADO | RECHAZADO | ERROR
    score: float         # Porcentaje de similitud (0–100)
    motivo: str
    timestamp: str
    metadata: dict       # Eco de los metadatos recibidos


# ─────────────────────────────────────────────
#  UTILIDADES
# ─────────────────────────────────────────────
def base64_a_imagen(b64_str: str) -> np.ndarray:
    """Decodifica un string base64 a un array numpy (imagen RGB)."""
    try:
        datos = base64.b64decode(b64_str)
        img = face_recognition.load_image_file(io.BytesIO(datos))
        return img
    except Exception as e:
        raise ValueError(f"Imagen base64 inválida: {str(e)}")


# ─────────────────────────────────────────────
#  LÓGICA DE VERIFICACIÓN
# ─────────────────────────────────────────────
def _verificar(img_base: np.ndarray, img_selfie: np.ndarray) -> dict:
    ahora = datetime.now().isoformat()

    # ── Detección de rostros ──────────────────
    loc_base = face_recognition.face_locations(img_base)
    loc_selfie = face_recognition.face_locations(img_selfie)

    num_rostros = len(loc_selfie)

    if num_rostros == 0:
        return {"status": "RECHAZADO", "score": 0.0,
                "motivo": "No se detectó ningún rostro en la selfie", "timestamp": ahora}

    if num_rostros > 1:
        return {"status": "RECHAZADO", "score": 0.0,
                "motivo": "Múltiples rostros detectados. Debe aparecer solo una persona",
                "timestamp": ahora}

    if not loc_base:
        return {"status": "ERROR", "score": 0.0,
                "motivo": "La imagen de referencia no contiene un rostro válido", "timestamp": ahora}

    # ── Encodings ────────────────────────────
    enc_base = face_recognition.face_encodings(
        img_base, [loc_base[0]], model=CONFIG["MODELO_ENCODING"]
    )[0]

    encs_selfie = face_recognition.face_encodings(
        img_selfie, [loc_selfie[0]],
        num_jitters=CONFIG["JITTER_NUM"],
        model=CONFIG["MODELO_ENCODING"]
    )

    if not encs_selfie:
        return {"status": "ERROR", "score": 0.0,
                "motivo": "No se pudo generar el encoding de la selfie", "timestamp": ahora}

    # ── Comparación ──────────────────────────
    distancia = float(face_recognition.face_distance([enc_base], encs_selfie[0])[0])
    es_valido = distancia < CONFIG["UMBRAL_APROBADO"]
    score = round((1 - distancia) * 100, 2)

    return {
        "status": "APROBADO" if es_valido else "RECHAZADO",
        "score": score,
        "motivo": "Verificación exitosa" if es_valido else "La identidad no coincide con la imagen de referencia",
        "timestamp": ahora,
    }


# ─────────────────────────────────────────────
#  ENDPOINT PRINCIPAL
# ─────────────────────────────────────────────
@app.post(
    "/verificar-asistencia",
    response_model=RespuestaVerificacion,
    summary="Verificar identidad facial y marcar asistencia",
)
def verificar_asistencia(solicitud: SolicitudVerificacion):  # FIX: sync — face_recognition bloquea el event loop en async
    """
    Recibe dos imágenes en base64:
    - **imagen_base**: foto de referencia del empleado.
    - **imagen_selfie**: foto tomada al momento de marcar asistencia.

    Retorna el resultado de la comparación facial.
    """
    logger.info(f"Solicitud recibida | metadata: {solicitud.metadata}")

    # 1 ── Decodificar imágenes
    try:
        img_base = base64_a_imagen(solicitud.imagen_base)
        img_selfie = base64_a_imagen(solicitud.imagen_selfie)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(e),
        )

    # 2 ── Verificación facial
    try:
        resultado = _verificar(img_base, img_selfie)
    except Exception as e:
        logger.error(f"Error en verificación: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno durante la verificación: {str(e)}",
        )

    logger.info(f"Resultado: {resultado['status']} | score: {resultado['score']} | {solicitud.metadata}")

    return RespuestaVerificacion(**resultado, metadata=solicitud.metadata)


# ─────────────────────────────────────────────
#  HEALTH CHECK
# ─────────────────────────────────────────────
@app.get("/health", summary="Estado del servicio")
async def health():
    return {"status": "ok", "timestamp": datetime.now().isoformat()}


# ─────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────
if __name__ == "__main__":
    uvicorn.run("endpoint:app", host="0.0.0.0", port=8000, reload=True)
