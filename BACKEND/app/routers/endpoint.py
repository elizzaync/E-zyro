# endpoint.py
import base64, io, logging, os
from datetime import datetime, timedelta

import face_recognition
import httpx
import numpy as np
import uvicorn
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database import get_db, RegistroAsistencia, Empleado, init_db

# ─────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────
CONFIG = {
    "UMBRAL_APROBADO":  0.42,
    "JITTER_NUM":       5,
    "MODELO_ENCODING":  "large",
    "JWT_SECRET":       os.getenv("JWT_SECRET", "cambia-esto-en-produccion"),
    "JWT_ALGORITHM":    "HS256",
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)
bearer_scheme = HTTPBearer()

app = FastAPI(title="API Asistencia Facial", version="2.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ─────────────────────────────────────────────
#  SCHEMAS
# ─────────────────────────────────────────────
class SolicitudAsistencia(BaseModel):
    imagen_selfie: str  = Field(..., description="Selfie en base64")
    tipo_registro: str  = Field(..., description="ENTRADA | SALIDA")
    latitud:       float | None = None
    longitud:      float | None = None
    plataforma:    str  = "mobile"

class RespuestaAsistencia(BaseModel):
    status:        str
    score:         float
    motivo:        str
    timestamp:     str
    tipo_registro: str
    empleado_id:   str
    registro_id:   str

# ─────────────────────────────────────────────
#  AUTH — valida JWT y devuelve employee_id
# ─────────────────────────────────────────────
def get_empleado_id(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    try:
        payload = jwt.decode(
            credentials.credentials,
            CONFIG["JWT_SECRET"],
            algorithms=[CONFIG["JWT_ALGORITHM"]],
        )
        employee_id: str = payload.get("sub")
        if not employee_id:
            raise HTTPException(status_code=401, detail="Token inválido: sin subject")
        return employee_id
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido o expirado")

# ─────────────────────────────────────────────
#  UTILIDADES
# ─────────────────────────────────────────────
def base64_a_imagen(b64_str: str) -> np.ndarray:
    try:
        datos = base64.b64decode(b64_str)
        return face_recognition.load_image_file(io.BytesIO(datos))
    except Exception as e:
        raise ValueError(f"Imagen base64 inválida: {e}")

async def descargar_foto_referencia(url: str) -> np.ndarray:
    """Descarga la foto de referencia desde la URL (S3 / Storage)."""
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(url)
        resp.raise_for_status()
    return face_recognition.load_image_file(io.BytesIO(resp.content))

def comparar_rostros(img_base: np.ndarray, img_selfie: np.ndarray) -> dict:
    ahora = datetime.utcnow().isoformat()

    loc_selfie = face_recognition.face_locations(img_selfie)
    num_rostros = len(loc_selfie)

    if num_rostros == 0:
        return {"status": "RECHAZADO", "score": 0.0,
                "motivo": "No se detectó ningún rostro en la selfie", "timestamp": ahora}
    if num_rostros > 1:
        return {"status": "RECHAZADO", "score": 0.0,
                "motivo": "Múltiples rostros detectados", "timestamp": ahora}

    loc_base = face_recognition.face_locations(img_base)
    if not loc_base:
        return {"status": "ERROR", "score": 0.0,
                "motivo": "La foto de referencia no contiene un rostro válido", "timestamp": ahora}

    enc_base   = face_recognition.face_encodings(img_base, [loc_base[0]], model=CONFIG["MODELO_ENCODING"])[0]
    encs_selfie = face_recognition.face_encodings(
        img_selfie, [loc_selfie[0]], num_jitters=CONFIG["JITTER_NUM"], model=CONFIG["MODELO_ENCODING"]
    )
    if not encs_selfie:
        return {"status": "ERROR", "score": 0.0,
                "motivo": "No se pudo generar el encoding de la selfie", "timestamp": ahora}

    distancia = float(face_recognition.face_distance([enc_base], encs_selfie[0])[0])
    aprobado  = distancia < CONFIG["UMBRAL_APROBADO"]
    score     = round((1 - distancia) * 100, 2)

    return {
        "status": "APROBADO" if aprobado else "RECHAZADO",
        "score":  score,
        "motivo": "Verificación exitosa" if aprobado else "La identidad no coincide",
        "timestamp": ahora,
    }

# ─────────────────────────────────────────────
#  ENDPOINT PRINCIPAL
# ─────────────────────────────────────────────
@app.post("/verificar-asistencia", response_model=RespuestaAsistencia)
async def verificar_asistencia(
    solicitud:   SolicitudAsistencia,
    empleado_id: str = Depends(get_empleado_id),
    db:          Session = Depends(get_db),
):
    logger.info(f"Solicitud de {empleado_id} | tipo: {solicitud.tipo_registro}")

    # 1. Buscar empleado en BD
    empleado = db.query(Empleado).filter(
        Empleado.id == empleado_id,
        Empleado.activo == True,
    ).first()

    if not empleado:
        raise HTTPException(status_code=404, detail="Empleado no encontrado o inactivo")
    if not empleado.foto_url:
        raise HTTPException(status_code=422, detail="El empleado no tiene foto de referencia configurada")

    # 2. Descargar foto de referencia desde el storage
    try:
        img_base = await descargar_foto_referencia(empleado.foto_url)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"No se pudo obtener la foto de referencia: {e}")

    # 3. Decodificar selfie
    try:
        img_selfie = base64_a_imagen(solicitud.imagen_selfie)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    # 4. Comparación facial
    try:
        resultado = comparar_rostros(img_base, img_selfie)
    except Exception as e:
        logger.error(f"Error en comparación: {e}")
        raise HTTPException(status_code=500, detail=f"Error en verificación facial: {e}")

    # 5. Guardar en BD siempre (APROBADO o RECHAZADO)
    registro = RegistroAsistencia(
        empleado_id   = empleado_id,
        tipo_registro = solicitud.tipo_registro,
        status        = resultado["status"],
        score         = resultado["score"],
        motivo        = resultado["motivo"],
        latitud       = solicitud.latitud,
        longitud      = solicitud.longitud,
        plataforma    = solicitud.plataforma,
        timestamp     = datetime.utcnow(),
    )
    db.add(registro)
    db.commit()
    db.refresh(registro)

    logger.info(f"Resultado: {resultado['status']} | score: {resultado['score']} | empleado: {empleado_id}")

    return RespuestaAsistencia(
        **resultado,
        tipo_registro = solicitud.tipo_registro,
        empleado_id   = str(empleado_id),
        registro_id   = str(registro.id),
    )

# ─────────────────────────────────────────────
#  HEALTH CHECK
# ─────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}

# ─────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────
if __name__ == "__main__":
    init_db()
    uvicorn.run("endpoint:app", host="0.0.0.0", port=8000, reload=True)
