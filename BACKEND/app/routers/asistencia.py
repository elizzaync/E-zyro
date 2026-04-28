
import face_recognition
import cv2
import numpy as np
import json
import requests
import base64
import os
from datetime import datetime

# ─────────────────────────────────────────────
#  CONFIGURACIÓN
# ─────────────────────────────────────────────
CONFIG = {
    "UMBRAL_APROBADO": 0.42,
    "JITTER_NUM": 5,
    "MODELO_ENCODING": "large",
    "ENDPOINT_URL": "http://localhost:8000/verificar-asistencia",  # Cambiar según entorno
    "TIMEOUT_SEGUNDOS": 30,
}


# ─────────────────────────────────────────────
#  VERIFICACIÓN FACIAL LOCAL (pre-validación)
# ─────────────────────────────────────────────
def verificar_asistencia_local(ruta_base: str, ruta_selfie: str) -> dict:
    """
    Realiza una pre-validación local antes de enviar al endpoint.
    Útil para evitar peticiones innecesarias con selfies claramente inválidas.
    """
    ahora = datetime.now().isoformat()

    try:
        img_selfie = face_recognition.load_image_file(ruta_selfie)
        loc_selfie = face_recognition.face_locations(img_selfie)

        num_rostros = len(loc_selfie)

        if num_rostros == 0:
            return {
                "status": "RECHAZADO",
                "motivo": "No se detectó ningún rostro en la selfie",
                "score": 0.0,
                "timestamp": ahora,
                "origen": "local",
            }

        if num_rostros > 1:
            return {
                "status": "RECHAZADO",
                "motivo": "Múltiples rostros detectados. Debe aparecer solo una persona",
                "score": 0.0,
                "timestamp": ahora,
                "origen": "local",
            }

        return None  # Selfie válida → continuar con el endpoint

    except Exception as e:
        return {
            "status": "ERROR",
            "motivo": f"Error en validación local: {str(e)}",
            "score": 0.0,
            "timestamp": ahora,
            "origen": "local",
        }


# ─────────────────────────────────────────────
#  ENVÍO AL ENDPOINT
# ─────────────────────────────────────────────
def _imagen_a_base64(ruta: str) -> str:
    """Convierte una imagen a string base64."""
    with open(ruta, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def marcar_asistencia(ruta_base: str, ruta_selfie: str, metadata: dict = None) -> dict:
    """
    Flujo principal:
      1. Pre-validación local (rápida, sin red).
      2. Envío al endpoint para verificación facial completa.
      3. Retorna la respuesta del servidor (o el error capturado).

    Args:
        ruta_base:  Ruta a la imagen de referencia (foto de perfil / DNI).
        ruta_selfie: Ruta a la selfie capturada en el momento.
        metadata:   Datos adicionales opcionales (ej: id_empleado, id_sede).

    Returns:
        dict con claves: status, score, motivo, timestamp, origen.
    """
    # 1 ── Pre-validación local
    resultado_local = verificar_asistencia_local(ruta_base, ruta_selfie)
    if resultado_local is not None:
        return resultado_local

    # 2 ── Preparar payload
    try:
        payload = {
            "imagen_base": _imagen_a_base64(ruta_base),
            "imagen_selfie": _imagen_a_base64(ruta_selfie),
            "metadata": metadata or {},
        }
    except FileNotFoundError as e:
        return {
            "status": "ERROR",
            "motivo": f"Archivo no encontrado: {str(e)}",
            "score": 0.0,
            "timestamp": datetime.now().isoformat(),
            "origen": "local",
        }

    # 3 ── Petición al endpoint
    try:
        response = requests.post(
            CONFIG["ENDPOINT_URL"],
            json=payload,
            timeout=CONFIG["TIMEOUT_SEGUNDOS"],
            headers={"Content-Type": "application/json"},
        )
        response.raise_for_status()
        resultado = response.json()
        resultado["origen"] = "servidor"
        return resultado

    except requests.exceptions.ConnectionError:
        return {
            "status": "ERROR",
            "motivo": "No se pudo conectar con el servidor de verificación",
            "score": 0.0,
            "timestamp": datetime.now().isoformat(),
            "origen": "red",
        }
    except requests.exceptions.Timeout:
        return {
            "status": "ERROR",
            "motivo": f"Tiempo de espera agotado ({CONFIG['TIMEOUT_SEGUNDOS']}s)",
            "score": 0.0,
            "timestamp": datetime.now().isoformat(),
            "origen": "red",
        }
    except requests.exceptions.HTTPError as e:
        return {
            "status": "ERROR",
            "motivo": f"Error HTTP {response.status_code}: {response.text}",
            "score": 0.0,
            "timestamp": datetime.now().isoformat(),
            "origen": "servidor",
        }
    except Exception as e:
        return {
            "status": "ERROR",
            "motivo": f"Error inesperado: {str(e)}",
            "score": 0.0,
            "timestamp": datetime.now().isoformat(),
            "origen": "desconocido",
        }


# ─────────────────────────────────────────────
#  USO DIRECTO (prueba rápida)
# ─────────────────────────────────────────────
if __name__ == "__main__":
    resultado = marcar_asistencia(
        ruta_base="foto_perfil.jpg",
        ruta_selfie="selfie.jpg",
        metadata={"id_empleado": "EMP-001", "id_sede": "SEDE-LIMA"},
    )
    print(json.dumps(resultado, indent=2, ensure_ascii=False))
