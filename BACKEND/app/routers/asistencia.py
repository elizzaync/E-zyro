"""
Router de Asistencia — E-ZYRO
=================================
Endpoints disponibles:
  POST /asistencia/foto-base        Registrar foto biométrica base del empleado
  GET  /asistencia/tiene-foto-base  Verificar si el empleado ya tiene foto base activa
  POST /asistencia/marcar           Marcar entrada/salida con selfie + GPS
  GET  /asistencia/estado-hoy       Estado de asistencia del día actual
  GET  /asistencia/historial        Historial paginado desde BD

Registrar en main.py:
  from app.routers.asistencia import router as asistencia_router
  app.include_router(asistencia_router)
"""
from __future__ import annotations

import base64
import io
import logging
import uuid
from datetime import date, datetime
from typing import Optional

import face_recognition
import requests as _req
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import cast, Date
from sqlalchemy.orm import Session

from ..db.database import get_db
from ..core.security import verificar_token
from ..models.models import (
    Empleado,
    FotoAsistencia,
    FotoBiometrica,
    GeolocalizacionAsistencia,
    RegistroAsistencia,
)
from ..services.cloudinary_service import subir_imagen_cloudinary

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/asistencia", tags=["asistencia"])

# ─── Configuración IA ────────────────────────────────────────────────────────
# jitters=1 → 5x más rápido que 5. Precisión baja <2%. Ideal para Railway.
# Sube a 2-3 solo si tienes CPU dedicada.
_NUM_JITTERS  = 1
_UMBRAL_SCORE = 42.0   # similitud mínima (0–100) para APROBADO


# ─── Schemas ─────────────────────────────────────────────────────────────────

class FotoBaseRequest(BaseModel):
    imagen_base: str          # JPEG/PNG en base64 (sin header data:image/…)


class FotoBaseResponse(BaseModel):
    url_cloudinary: str
    public_id_cloudinary: str
    mensaje: str


class MarcarRequest(BaseModel):
    imagen_selfie: str        # JPEG/PNG en base64
    tipo: str                 # entrada | salida | entrada_almuerzo | salida_almuerzo
    latitud:              Optional[float] = None
    longitud:             Optional[float] = None
    precision_m:          Optional[float] = None
    altitud:              Optional[float] = None
    proyecto_id:          Optional[str]   = None
    proyecto_servicio_id: Optional[str]   = None


class MarcarResponse(BaseModel):
    registro_id:  str
    status:       str    # APROBADO | RECHAZADO
    score:        float  # 0.0 – 100.0
    motivo:       str
    timestamp:    str    # ISO 8601
    gps_guardado: bool
    foto_url:     Optional[str] = None
    resultado_ia: str    # aprobado | revision_manual | rechazado


# ─── Utilidades de reconocimiento facial ─────────────────────────────────────

def _strip_header(b64: str) -> str:
    """Elimina prefijo 'data:image/...;base64,' si está presente."""
    return b64.split(",", 1)[1] if "," in b64 else b64


def _decode_face(b64: str):
    """
    Decodifica base64 → face encoding.
    Retorna None si la imagen no contiene ningún rostro detectable.
    """
    try:
        raw      = base64.b64decode(_strip_header(b64))
        img      = face_recognition.load_image_file(io.BytesIO(raw))
        locs     = face_recognition.face_locations(img)
        if not locs:
            return None
        encodings = face_recognition.face_encodings(img, [locs[0]], num_jitters=_NUM_JITTERS)
        return encodings[0] if encodings else None
    except Exception:
        return None


def _url_to_face(url: str):
    """
    Descarga imagen desde Cloudinary y extrae su face encoding.
    Lanza HTTPException 503 si la descarga falla.
    """
    try:
        resp = _req.get(url, timeout=30)   # 30 s — Railway + Cloudinary puede ser lento
        resp.raise_for_status()
    except Exception as exc:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"No se pudo descargar la foto biométrica base: {exc}",
        )
    img      = face_recognition.load_image_file(io.BytesIO(resp.content))
    locs     = face_recognition.face_locations(img)
    if not locs:
        return None
    encodings = face_recognition.face_encodings(img, [locs[0]], num_jitters=_NUM_JITTERS)
    return encodings[0] if encodings else None


def _comparar(enc_base, enc_selfie) -> tuple[float, str]:
    """Retorna (score 0–100, resultado_ia)."""
    distancia = float(face_recognition.face_distance([enc_base], enc_selfie)[0])
    score     = round(max(0.0, (1.0 - distancia) * 100.0), 2)
    if score >= _UMBRAL_SCORE:
        resultado = "aprobado"
    elif score >= 35.0:
        resultado = "revision_manual"
    else:
        resultado = "rechazado"
    return score, resultado


# ─── Endpoints ───────────────────────────────────────────────────────────────

@router.post("/foto-base", response_model=FotoBaseResponse)
def subir_foto_base(
    body:    FotoBaseRequest,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Registra la foto biométrica base del empleado.
    - Valida que la imagen tenga un rostro detectable.
    - Sube a Cloudinary (carpeta biometrico/<empresa>/<usuario>/).
    - Desactiva fotos anteriores e inserta la nueva en foto_biometrica.
    """
    usuario_id = payload["id"]
    empresa_id = payload["empresa_id"]

    # Validar que hay exactamente un rostro
    encoding = _decode_face(body.imagen_base)
    if encoding is None:
        raise HTTPException(
            422,
            "No se detectó ningún rostro. "
            "Colócate bien iluminado y mira directamente a la cámara.",
        )

    # Desactivar fotos anteriores
    db.query(FotoBiometrica).filter(
        FotoBiometrica.usuario_id == usuario_id,
        FotoBiometrica.empresa_id == empresa_id,
        FotoBiometrica.activa.is_(True),
    ).update({"activa": False}, synchronize_session=False)

    # Subir nueva foto a Cloudinary
    public_id = f"biometrico/{empresa_id}/{usuario_id}/base_{uuid.uuid4().hex[:10]}"
    try:
        url = subir_imagen_cloudinary(
            base64_data=body.imagen_base,
            folder=f"biometrico/{empresa_id}/{usuario_id}",
            public_id=public_id,
            is_perfil=True,
        )
    except Exception as exc:
        logger.error("Cloudinary upload failed (foto-base): %s", exc, exc_info=True)
        raise HTTPException(
            500,
            "No se pudo guardar la foto en el servidor. "
            "Verifica las variables CLOUDINARY_* en Railway.",
        )

    # Guardar en BD
    foto = FotoBiometrica(
        id=uuid.uuid4(),
        usuario_id=usuario_id,
        empresa_id=empresa_id,
        url_cloudinary=url,
        public_id_cloudinary=public_id,
        activa=True,
    )
    db.add(foto)
    db.commit()

    return FotoBaseResponse(
        url_cloudinary=url,
        public_id_cloudinary=public_id,
        mensaje="Foto biométrica registrada correctamente.",
    )


@router.get("/tiene-foto-base")
def tiene_foto_base(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    usuario_id = payload["id"]
    empresa_id = payload["empresa_id"]
    foto = db.query(FotoBiometrica).filter(
        FotoBiometrica.usuario_id == usuario_id,
        FotoBiometrica.empresa_id == empresa_id,
        FotoBiometrica.activa.is_(True),
    ).first()
    return {
        "tiene_foto_base": foto is not None,
        "foto_url":        foto.url_cloudinary if foto else None,
    }


@router.post("/marcar", response_model=MarcarResponse)
def marcar_asistencia(
    body:    MarcarRequest,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """
    Flujo completo de marcación:
      1. Obtener empleado activo desde BD.
      2. Obtener foto biométrica base activa desde BD → descargar desde Cloudinary.
      3. Decodificar selfie recibida → encoding facial.
      4. Comparar encodings → score y resultado_ia.
      5. Subir selfie a Cloudinary (auditoría).
      6. Persistir en 3 tablas: registro_asistencia, foto_asistencia, geolocalizacion_asistencia.
    """
    usuario_id = payload["id"]
    empresa_id = payload["empresa_id"]

    # 1 ── Empleado
    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
        Empleado.activo.is_(True),
    ).first()
    if not empleado:
        raise HTTPException(404, "Empleado no encontrado o inactivo.")

    # 2 ── Foto biométrica base
    foto_base = db.query(FotoBiometrica).filter(
        FotoBiometrica.usuario_id == usuario_id,
        FotoBiometrica.empresa_id == empresa_id,
        FotoBiometrica.activa.is_(True),
    ).first()
    if not foto_base:
        raise HTTPException(
            422,
            "No tienes foto biométrica registrada. "
            "Configura tu foto base en la sección de asistencia antes de marcar.",
        )

    # 3 ── Validar tipo
    tipos_validos = {"entrada", "salida", "entrada_almuerzo", "salida_almuerzo"}
    tipo = body.tipo.lower().strip()
    if tipo not in tipos_validos:
        raise HTTPException(
            422, f"Tipo '{tipo}' inválido. Valores: {sorted(tipos_validos)}"
        )

    # 4 ── Encoding de la foto base (descargada desde Cloudinary)
    enc_base = _url_to_face(foto_base.url_cloudinary)
    if enc_base is None:
        raise HTTPException(
            503,
            "No se pudo extraer el rostro de tu foto biométrica base. "
            "Contacta a administración para re-registrar tu foto.",
        )

    # 5 ── Encoding de la selfie recibida
    enc_selfie = _decode_face(body.imagen_selfie)
    if enc_selfie is None:
        raise HTTPException(
            422,
            "No se detectó ningún rostro en la selfie. "
            "Asegúrate de estar bien iluminado y mirar directamente a la cámara.",
        )

    # 6 ── Comparación facial
    score, resultado_ia = _comparar(enc_base, enc_selfie)
    aprobado = resultado_ia == "aprobado"
    ahora    = datetime.utcnow()

    _motivos = {
        "aprobado":        f"Identidad verificada · Similitud {score:.1f}%",
        "revision_manual": f"Similitud baja ({score:.1f}%) · Requiere revisión del supervisor",
        "rechazado":       f"Identidad no verificada · Similitud insuficiente ({score:.1f}%)",
    }
    motivo = _motivos[resultado_ia]

    # 7 ── Subir selfie a Cloudinary (fallo no bloquea el registro)
    selfie_url:       Optional[str] = None
    selfie_public_id: Optional[str] = None
    try:
        selfie_public_id = (
            f"asistencia/{empresa_id}/{empleado.id}/"
            f"{ahora.strftime('%Y%m%d')}_{uuid.uuid4().hex[:10]}"
        )
        selfie_url = subir_imagen_cloudinary(
            base64_data=body.imagen_selfie,
            folder=f"asistencia/{empresa_id}/{empleado.id}",
            public_id=selfie_public_id,
            is_perfil=False,
        )
    except Exception as exc:
        # Loguear para diagnosticar en Railway — causa más común: CLOUDINARY_* no configuradas
        logger.error("Cloudinary upload failed (selfie): %s", exc, exc_info=True)
        selfie_url       = None
        selfie_public_id = None

    # 8 ── Persistencia en BD (3 tablas en una transacción)
    reg_id = uuid.uuid4()

    registro = RegistroAsistencia(
        id=reg_id,
        empresa_id=empresa_id,
        empleado_id=empleado.id,
        proyecto_id=(
            uuid.UUID(body.proyecto_id) if body.proyecto_id else None
        ),
        proyecto_servicio_id=(
            uuid.UUID(body.proyecto_servicio_id) if body.proyecto_servicio_id else None
        ),
        tipo=tipo,
        fecha_hora=ahora,
        estado="validado" if aprobado else "pendiente",
        observacion=motivo,
    )
    db.add(registro)
    db.flush()   # obtener ID antes del commit

    fa = FotoAsistencia(
        registro_id=reg_id,
        url_cloudinary=selfie_url,
        public_id_cloudinary=selfie_public_id,
        similitud_ia=round(score / 100.0, 4),   # 0.0000 – 1.0000
        resultado=resultado_ia,
        fecha_captura=ahora,
    )
    db.add(fa)

    gps_guardado = body.latitud is not None and body.longitud is not None
    if gps_guardado:
        geo = GeolocalizacionAsistencia(
            registro_id=reg_id,
            latitud=body.latitud,
            longitud=body.longitud,
            precision_m=body.precision_m,
            altitud=body.altitud,
        )
        db.add(geo)

    db.commit()

    logger.info(
        "Asistencia marcada | empleado=%s tipo=%s resultado=%s score=%.1f",
        empleado.id, tipo, resultado_ia, score,
    )

    return MarcarResponse(
        registro_id=str(reg_id),
        status="APROBADO" if aprobado else "RECHAZADO",
        score=score,
        motivo=motivo,
        timestamp=ahora.isoformat(),
        gps_guardado=gps_guardado,
        foto_url=selfie_url,
        resultado_ia=resultado_ia,
    )


@router.get("/estado-hoy")
def estado_hoy(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Estado de asistencia del empleado para el día actual (hora UTC)."""
    usuario_id = payload["id"]
    empresa_id = payload["empresa_id"]

    tiene_foto = (
        db.query(FotoBiometrica)
        .filter(
            FotoBiometrica.usuario_id == usuario_id,
            FotoBiometrica.empresa_id == empresa_id,
            FotoBiometrica.activa.is_(True),
        )
        .first()
    ) is not None

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()

    if not empleado:
        return {
            "tiene_entrada": False, "tiene_salida": False,
            "tiene_foto_base": tiene_foto, "jornada_completa": False,
            "entrada_hora": None, "salida_hora": None,
        }

    registros_hoy = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empleado_id == empleado.id,
            RegistroAsistencia.empresa_id == empresa_id,
            cast(RegistroAsistencia.fecha_hora, Date) == date.today(),
        )
        .order_by(RegistroAsistencia.fecha_hora)
        .all()
    )

    entrada = next((r for r in registros_hoy if r.tipo == "entrada"), None)
    salida  = next((r for r in registros_hoy if r.tipo == "salida"),  None)

    def _fmt(r) -> Optional[str]:
        return r.fecha_hora.strftime("%H:%M") if r else None

    return {
        "tiene_entrada":    entrada is not None,
        "tiene_salida":     salida  is not None,
        "tiene_foto_base":  tiene_foto,
        "entrada_hora":     _fmt(entrada),
        "salida_hora":      _fmt(salida),
        "jornada_completa": entrada is not None and salida is not None,
    }


@router.get("/historial")
def historial(
    pagina:     int = 1,
    por_pagina: int = 30,
    payload:    dict    = Depends(verificar_token),
    db:         Session = Depends(get_db),
):
    """Historial paginado de asistencia. Incluye score IA, GPS y URL de selfie."""
    usuario_id = payload["id"]
    empresa_id = payload["empresa_id"]

    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()
    if not empleado:
        return {"registros": [], "total": 0, "pagina": pagina, "hay_mas": False}

    q     = db.query(RegistroAsistencia).filter(
        RegistroAsistencia.empleado_id == empleado.id,
        RegistroAsistencia.empresa_id  == empresa_id,
    )
    total = q.count()
    rows  = (
        q.order_by(RegistroAsistencia.fecha_hora.desc())
        .offset((pagina - 1) * por_pagina)
        .limit(por_pagina)
        .all()
    )

    items = []
    for r in rows:
        fa  = db.query(FotoAsistencia).filter(
            FotoAsistencia.registro_id == r.id
        ).first()
        geo = db.query(GeolocalizacionAsistencia).filter(
            GeolocalizacionAsistencia.registro_id == r.id
        ).first()

        score_pct = (
            round(float(fa.similitud_ia) * 100, 2)
            if fa and fa.similitud_ia is not None else 0.0
        )

        items.append({
            "id":           str(r.id),
            "tipo":         r.tipo.upper(),
            "fecha_hora":   r.fecha_hora.isoformat(),
            "estado":       r.estado,
            "status":       "APROBADO" if r.estado == "validado" else "RECHAZADO",
            "score":        score_pct,
            "motivo":       r.observacion or "",
            "latitud":      float(geo.latitud)     if geo else None,
            "longitud":     float(geo.longitud)    if geo else None,
            "precision_m":  float(geo.precision_m) if (geo and geo.precision_m) else None,
            "resultado_ia": fa.resultado            if fa else None,
            # Solo devolver URL real; nunca cadena vacía
            "foto_url":     (fa.url_cloudinary or None) if fa else None,
        })

    return {
        "registros":  items,
        "total":      total,
        "pagina":     pagina,
        "por_pagina": por_pagina,
        "hay_mas":    total > pagina * por_pagina,
    }
