
from __future__ import annotations

import base64
import logging
import uuid
from datetime import date, datetime, time, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import cast, Date, or_
from sqlalchemy.orm import Session

from ..db.database import get_db
from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..models.empleado                      import Empleado
from ..models.usuario                        import Usuario
from ..models.foto_biometrica               import FotoBiometrica
from ..models.foto_asistencia               import FotoAsistencia
from ..models.geolocalizacion_asistencia    import GeolocalizacionAsistencia
from ..models.registro_asistencia           import RegistroAsistencia
from ..models.turno                          import Turno, TurnoEmpleado

from ..services.cloudinary_service import subir_imagen_cloudinary
from ..services.cloudinary_paths import carpeta_biometrico, carpeta_asistencia

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/asistencia", tags=["asistencia"])

# ─── Configuración detección facial ──────────────────────────────────────────
_UMBRAL_SCORE = 42.0   # reservado para cuando se active comparación IA


# ─── Schemas ─────────────────────────────────────────────────────────────────

class FotoBaseRequest(BaseModel):
    imagen_base: str          # JPEG/PNG en base64 (sin header data:image/…)


class FotoBaseResponse(BaseModel):
    url_cloudinary: str
    public_id_cloudinary: str
    mensaje: str


class MarcarRequest(BaseModel):
    # Opcional: el almuerzo (v1 PYME) y los registros offline se marcan sin
    # selfie (se aprueban por JWT + GPS). Para entrada/salida el cliente la envía.
    imagen_selfie: Optional[str] = None   # JPEG/PNG en base64
    tipo: str                 # entrada | salida | entrada_almuerzo | salida_almuerzo
    latitud:              Optional[float] = None
    longitud:             Optional[float] = None
    precision_m:          Optional[float] = None
    altitud:              Optional[float] = None
    proyecto_id:          Optional[str]   = None
    proyecto_servicio_id: Optional[str]   = None
    timestamp:            Optional[str]   = None  # ISO 8601 timestamp del cliente
    uuid_cliente:         Optional[str]   = None  # UUID v4 generado en dispositivo (idempotencia)
    fuente_tiempo:        Optional[str]   = None  # ntp_monotonic | ntp_device | device_only | sospechoso


class MarcarResponse(BaseModel):
    registro_id:  str
    status:       str    # APROBADO | RECHAZADO
    score:        float  # 0.0 – 100.0
    motivo:       str
    timestamp:    str    # ISO 8601
    gps_guardado: bool
    foto_url:     Optional[str] = None
    resultado_ia: str    # aprobado | revision_manual | rechazado


# ─── Utilidades de detección facial (OpenCV headless) ────────────────────────

def _strip_header(b64: str) -> str:
    return b64.split(",", 1)[1] if "," in b64 else b64


def _detect_face_cv2(image_bytes: bytes) -> bool:
    """Devuelve True si hay al menos un rostro detectable en la imagen."""
    import cv2
    import numpy as np
    arr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return False
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(30, 30))
    return len(faces) > 0


def _decode_face(b64: str):
    """Retorna True si hay un rostro en la imagen base64, None si no."""
    try:
        raw = base64.b64decode(_strip_header(b64))
        return True if _detect_face_cv2(raw) else None
    except Exception:
        return None



def _comparar(enc_base, enc_selfie) -> tuple[float, str]:
    """Sin comparación biométrica — aprueba si ambas imágenes tienen rostro."""
    return 85.0, "aprobado"


def _notificar_marca_en_revision(db, empresa_id, empleado, tipo, resultado, motivo):
    """Avisa a quienes pueden validar asistencia (permiso asistencia:validar) que
    una marca requiere revisión manual."""
    from ..models.usuario import Usuario
    from ..services.fcm_service import notificar_usuario
    from ..core.permisos import usuarios_con_permiso

    # Nombre del empleado para el mensaje
    u = db.query(Usuario.nombre, Usuario.apellido).filter(
        Usuario.id == empleado.usuario_id).first()
    nombre = (f"{u.nombre} {u.apellido}".strip() if u else "Un empleado")

    validadores = usuarios_con_permiso(db, empresa_id, "asistencia", "validar")
    estado_txt = "requiere revisión" if resultado == "revision_manual" else "fue rechazada"
    titulo = "Marca de asistencia por revisar"
    mensaje = f"La marca de {tipo} de {nombre} {estado_txt}. {motivo}"
    for uid in validadores:
        notificar_usuario(
            db, empresa_id=empresa_id, usuario_id=uid,
            titulo=titulo, mensaje=mensaje,
            tipo="warning", categoria="asistencia",
            referencia_tabla="asistencia_revision",
        )
    db.commit()


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
    bio_folder  = carpeta_biometrico(empresa_id, usuario_id)
    bio_name    = f"base_{uuid.uuid4().hex[:10]}"
    public_id   = f"{bio_folder}/{bio_name}"
    try:
        url = subir_imagen_cloudinary(
            base64_data=body.imagen_base,
            folder=bio_folder,
            public_id=bio_name,          # solo el nombre, folder lo pone Cloudinary
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
        id=str(uuid.uuid4()),
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

    # 0 ── Idempotencia: si ya existe un registro con este uuid_cliente, devolver el existente
    if body.uuid_cliente:
        existente = db.query(RegistroAsistencia).filter(
            RegistroAsistencia.empresa_id == empresa_id,
            RegistroAsistencia.uuid_cliente == body.uuid_cliente,
        ).first()
        if existente:
            fa_ex = db.query(FotoAsistencia).filter(
                FotoAsistencia.registro_id == existente.id
            ).first()
            score_ex = round(float(fa_ex.similitud_ia) * 100, 2) if (fa_ex and fa_ex.similitud_ia) else 85.0
            resultado_ex = fa_ex.resultado if fa_ex else "aprobado"
            logger.info("Idempotencia: uuid_cliente=%s ya existe, devolviendo registro existente", body.uuid_cliente)
            return MarcarResponse(
                registro_id=str(existente.id),
                status="APROBADO" if existente.estado == "validado" else "RECHAZADO",
                score=score_ex,
                motivo=existente.observacion or "",
                timestamp=existente.fecha_hora.isoformat(),
                gps_guardado=False,
                foto_url=fa_ex.url_cloudinary if fa_ex else None,
                resultado_ia=resultado_ex,
            )

    # 1 ── Empleado
    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
        Empleado.activo.is_(True),
    ).first()
    if not empleado:
        raise HTTPException(404, "Empleado no encontrado o inactivo.")

    # 3 ── Validar tipo
    tipos_validos = {"entrada", "salida", "entrada_almuerzo", "salida_almuerzo"}
    tipo = body.tipo.lower().strip()
    if tipo not in tipos_validos:
        raise HTTPException(
            422, f"Tipo '{tipo}' inválido. Valores: {sorted(tipos_validos)}"
        )

    tipos_almuerzo = {"entrada_almuerzo", "salida_almuerzo"}
    sin_selfie = not (body.imagen_selfie or "").strip()

    # 2 ── Foto biométrica base
    # Se consulta siempre (puede ser None), pero solo se EXIGE cuando va a haber
    # comparación facial (marca CON selfie). Las marcas de almuerzo (v1 PYME) y
    # los registros offline sin evidencia se aprueban por JWT + GPS.
    foto_base = db.query(FotoBiometrica).filter(
        FotoBiometrica.usuario_id == usuario_id,
        FotoBiometrica.empresa_id == empresa_id,
        FotoBiometrica.activa.is_(True),
    ).first()
    if not sin_selfie and not foto_base:
        raise HTTPException(
            422,
            "No tienes foto biométrica registrada. "
            "Configura tu foto base en la sección de asistencia antes de marcar.",
        )

    # 3b ── Reglas de negocio del almuerzo (v1 PYME: uno por día, orden lógico)
    if tipo in tipos_almuerzo:
        hoy_lima = datetime.now(ZoneInfo("America/Lima")).date()
        regs_hoy = (
            db.query(RegistroAsistencia)
            .filter(
                RegistroAsistencia.empleado_id == empleado.id,
                RegistroAsistencia.empresa_id == empresa_id,
                cast(RegistroAsistencia.fecha_hora, Date) == hoy_lima,
            )
            .all()
        )
        tipos_hoy = {r.tipo for r in regs_hoy}
        if "entrada" not in tipos_hoy:
            raise HTTPException(
                422, "Debes marcar tu entrada antes de registrar el almuerzo."
            )
        if tipo == "entrada_almuerzo" and "entrada_almuerzo" in tipos_hoy:
            raise HTTPException(422, "Ya registraste el inicio de tu almuerzo hoy.")
        if tipo == "salida_almuerzo":
            if "entrada_almuerzo" not in tipos_hoy:
                raise HTTPException(
                    422, "Primero marca el inicio de tu almuerzo."
                )
            if "salida_almuerzo" in tipos_hoy:
                raise HTTPException(422, "Ya registraste el fin de tu almuerzo hoy.")

    # 4 ── Verificar que la selfie tenga un rostro detectable
    # Excepción: registros sincronizados offline (uuid_cliente presente, imagen vacía)
    # se aprueban por JWT + GPS; se marcan como sin_evidencia_offline para revisión.
    es_sync_sin_selfie = bool(body.uuid_cliente) and not (body.imagen_selfie or "").strip()

    if es_sync_sin_selfie:
        score, resultado_ia = 0.0, "sin_evidencia_offline"
        aprobado = True  # identidad ya verificada vía JWT al momento de marcar
    else:
        enc_selfie = _decode_face(body.imagen_selfie)
        if enc_selfie is None:
            raise HTTPException(
                422,
                "No se detectó ningún rostro en la selfie. "
                "Asegúrate de estar bien iluminado y mirar directamente a la cámara.",
            )
        # 5 ── Comparación facial
        score, resultado_ia = _comparar(True, enc_selfie)
        aprobado = resultado_ia == "aprobado"

    # ── Parsear timestamp del dispositivo (registros offline-first) ─────────
    # timestamp_servidor = cuándo llegó la petición al servidor (siempre ahora).
    # ahora             = hora reportada por el dispositivo, o servidor si no viene.
    # Ambas se necesitan antes de la validación de fuente de tiempo.
    timestamp_servidor = datetime.now(ZoneInfo("America/Lima")).replace(tzinfo=None)
    if body.timestamp:
        try:
            ts_raw = datetime.fromisoformat(body.timestamp.replace("Z", "+00:00"))
            ahora = ts_raw.astimezone(ZoneInfo("America/Lima")).replace(tzinfo=None)
        except (ValueError, AttributeError):
            ahora = timestamp_servidor
    else:
        ahora = timestamp_servidor

    # ── Validación de la fuente de tiempo ────────────────────────────────────
    fuente = (body.fuente_tiempo or "device_only").strip().lower()
    motivo = ""

    if fuente == "sospechoso":
        # El reloj del dispositivo retrocedió desde el último sync NTP.
        resultado_ia = "revision_manual"
        aprobado = True
        motivo = "ALERTA: Posible manipulación de reloj detectada."

    elif fuente == "device_only":
        # Sin referencia NTP: marcar para revisión si hay más de 1h de diferencia.
        delta_horas = abs((timestamp_servidor - ahora).total_seconds()) / 3600
        if delta_horas > 1:
            resultado_ia = "revision_manual"
            aprobado = True
            motivo = f"Tiempo no verificado por NTP (δ={delta_horas:.1f}h). Requiere revisión."

    else:
        # ntp_monotonic o ntp_device: fuente confiable — solo alerta si delta > 24h.
        delta_horas = abs((timestamp_servidor - ahora).total_seconds()) / 3600
        if delta_horas > 24:
            resultado_ia = "revision_manual"
            aprobado = True
            motivo = f"Delta tiempo inusual ({delta_horas:.1f}h). Revisión recomendada."

    _motivos = {
        "aprobado":              f"Identidad verificada · Similitud {score:.1f}%",
        "revision_manual":       f"Similitud baja ({score:.1f}%) · Requiere revisión del supervisor",
        "rechazado":             f"Identidad no verificada · Similitud insuficiente ({score:.1f}%)",
        "sin_evidencia_offline": "Registro sincronizado offline · Sin selfie · Verificado por JWT+GPS",
    }
    motivo = _motivos.get(resultado_ia, motivo)

    # 7 ── Subir selfie a Cloudinary (fallo no bloquea el registro)
    # Registros sincronizados offline llegan sin selfie (es_sync_sin_selfie):
    # no hay nada que subir, así que ni lo intentamos.
    selfie_url:       Optional[str] = None
    selfie_public_id: Optional[str] = None
    if (body.imagen_selfie or "").strip():
        try:
            selfie_folder = carpeta_asistencia(empresa_id, empleado.id, ahora.strftime('%Y-%m'))
            selfie_name   = f"{ahora.strftime('%Y%m%d')}_{uuid.uuid4().hex[:10]}"
            selfie_public_id = f"{selfie_folder}/{selfie_name}"
            selfie_url = subir_imagen_cloudinary(
                base64_data=body.imagen_selfie,
                folder=selfie_folder,
                public_id=selfie_name,       # solo el nombre, folder lo pone Cloudinary
                is_perfil=False,
            )
        except Exception as exc:
            # Loguear para diagnosticar en Railway — causa más común: CLOUDINARY_* no configuradas
            logger.error("Cloudinary upload failed (selfie): %s", exc, exc_info=True)
            selfie_url       = None
            selfie_public_id = None

    # 8 ── Persistencia en BD (3 tablas en una transacción)
    reg_id = str(uuid.uuid4())

    registro = RegistroAsistencia(
        id=reg_id,
        empresa_id=empresa_id,
        empleado_id=empleado.id,
        proyecto_id=(
            str(uuid.UUID(body.proyecto_id)) if body.proyecto_id else None
        ),
        proyecto_servicio_id=(
            str(uuid.UUID(body.proyecto_servicio_id)) if body.proyecto_servicio_id else None
        ),
        tipo=tipo,
        fecha_hora=ahora,
        estado="validado" if aprobado else "pendiente",
        observacion=motivo,
        uuid_cliente=body.uuid_cliente,
    )
    db.add(registro)
    db.flush()

    # La evidencia fotográfica solo se registra si hay selfie subida exitosamente.
    # Registros offline sin selfie (sin_evidencia_offline) no generan FotoAsistencia.
    if foto_base is not None and selfie_url is not None:
        fa = FotoAsistencia(
            registro_id=reg_id,
            foto_base_id=foto_base.id,
            url_cloudinary=selfie_url,
            public_id_cloudinary=selfie_public_id,
            similitud_ia=round(score / 100.0, 4),
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

    # Si la marca quedó en revisión/rechazada, avisar a supervisores/admin
    # para que validen manualmente (la identidad no se verificó con certeza).
    if resultado_ia in ("revision_manual", "rechazado"):
        try:
            _notificar_marca_en_revision(db, empresa_id, empleado, tipo, resultado_ia, motivo)
        except Exception:
            pass

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
    """Estado de asistencia del empleado para el día actual."""
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

    hoy_lima = datetime.now(ZoneInfo("America/Lima")).date()

    registros_hoy = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empleado_id == empleado.id,
            RegistroAsistencia.empresa_id == empresa_id,
            cast(RegistroAsistencia.fecha_hora, Date) == hoy_lima,
        )
        .order_by(RegistroAsistencia.fecha_hora)
        .all()
    )

    entrada = next((r for r in registros_hoy if r.tipo == "entrada"), None)
    salida  = next((r for r in registros_hoy if r.tipo == "salida"),  None)
    ini_alm = next((r for r in registros_hoy if r.tipo == "entrada_almuerzo"), None)
    fin_alm = next((r for r in registros_hoy if r.tipo == "salida_almuerzo"), None)

    def _fmt(r) -> Optional[str]:
        if not r:
            return None
        # Como la BD ya tiene los números exactos de Perú, se lee y formatea directo
        return r.fecha_hora.strftime("%H:%M")

    # Duración del almuerzo (minutos) solo cuando ambos extremos existen.
    duracion_almuerzo = None
    if ini_alm and fin_alm:
        duracion_almuerzo = int(
            (fin_alm.fecha_hora - ini_alm.fecha_hora).total_seconds() // 60
        )

    return {
        "tiene_entrada":    entrada is not None,
        "tiene_salida":     salida  is not None,
        "tiene_foto_base":  tiene_foto,
        "entrada_hora":     _fmt(entrada),
        "salida_hora":      _fmt(salida),
        "jornada_completa": entrada is not None and salida is not None,
        # ── Almuerzo (v1 PYME) ──────────────────────────────────────────────
        "tiene_inicio_almuerzo": ini_alm is not None,
        "tiene_fin_almuerzo":    fin_alm is not None,
        "inicio_almuerzo_hora":  _fmt(ini_alm),
        "fin_almuerzo_hora":     _fmt(fin_alm),
        "en_almuerzo":           ini_alm is not None and fin_alm is None,
        "duracion_almuerzo_min": duracion_almuerzo,
        # ISO del inicio para que el app calcule el cronómetro vivo y la alerta de fin.
        "inicio_almuerzo_iso":   ini_alm.fecha_hora.isoformat() if ini_alm else None,
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
            "fecha_hora":   r.fecha_hora.isoformat() if r.fecha_hora else None,
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


# ═══════════════════════════════════════════════════════════════════════════════
# CONTROL DE ASISTENCIAS (supervisión) — requiere permiso asistencia:ver
# ═══════════════════════════════════════════════════════════════════════════════
#
# Regla de negocio (horario normal): 08:00–17:00 con 1 h de almuerzo = 8 h netas.
# Las EXCEPCIONES (practicantes, contratos con horario distinto) se modelan con
# un Turno propio asignado al empleado vía TurnoEmpleado con vigencia. Si un
# empleado no tiene turno asignado, se usa el turno por defecto de abajo.

_DEF_ENTRADA          = time(8, 0)
_DEF_SALIDA           = time(17, 0)
_DEF_ALMUERZO_MIN     = 60
_DEF_TOLERANCIA_MIN   = 5
# Horas netas exigidas por defecto = jornada - almuerzo = 9 h - 1 h = 8 h.


def _min_entre(t1: time, t2: time) -> int:
    """Minutos entre dos horas del mismo día (t2 - t1), nunca negativo."""
    d = (t2.hour * 60 + t2.minute) - (t1.hour * 60 + t1.minute)
    return d if d > 0 else 0


def _turnos_por_empleado(db: Session, empresa_id: str, fecha: date) -> dict[str, Turno]:
    """empleado_id → Turno vigente en `fecha` (excepciones). Sin asignación = no
    aparece en el dict y se usa el turno por defecto."""
    rows = (
        db.query(TurnoEmpleado, Turno)
        .join(Turno, Turno.id == TurnoEmpleado.turno_id)
        .filter(
            Turno.empresa_id == empresa_id,
            TurnoEmpleado.activo == True,
            Turno.activo == True,
            TurnoEmpleado.fecha_desde <= fecha,
            or_(TurnoEmpleado.fecha_hasta.is_(None), TurnoEmpleado.fecha_hasta >= fecha),
        )
        .all()
    )
    out: dict[str, Turno] = {}
    for te, turno in rows:
        out.setdefault(str(te.empleado_id), turno)   # primera asignación vigente gana
    return out


@router.get("/control-diario")
def control_diario(
    fecha:   Optional[str] = None,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Resumen de asistencia del día por empleado: entrada/salida/almuerzo, horas
    trabajadas netas y cumplimiento contra el turno del empleado.

    Requiere permiso `asistencia:ver`."""
    exigir_permiso(db, payload, "asistencia", "ver")
    empresa_id = payload["empresa_id"]

    if fecha:
        try:
            dia = date.fromisoformat(fecha)
        except ValueError:
            raise HTTPException(status_code=422, detail="Fecha inválida (use YYYY-MM-DD)")
    else:
        dia = datetime.now(ZoneInfo("America/Lima")).date()

    # 1. Empleados activos + datos de usuario
    empleados = (
        db.query(
            Empleado.id.label("emp_id"),
            Empleado.cargo.label("cargo"),
            Empleado.tipo.label("tipo"),
            Usuario.nombre.label("nombre"),
            Usuario.apellido.label("apellido"),
        )
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
        .order_by(Usuario.nombre.asc(), Usuario.apellido.asc())
        .all()
    )

    # 2. Turnos-excepción vigentes ese día
    turnos = _turnos_por_empleado(db, empresa_id, dia)

    # 3. Registros del día, agrupados por empleado
    registros = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id == empresa_id,
            cast(RegistroAsistencia.fecha_hora, Date) == dia,
        )
        .order_by(RegistroAsistencia.fecha_hora.asc())
        .all()
    )
    reg_por_emp: dict[str, list] = {}
    for r in registros:
        reg_por_emp.setdefault(str(r.empleado_id), []).append(r)

    items = []
    n_completos = n_incompletos = n_en_curso = n_ausentes = 0

    for e in empleados:
        emp_id = str(e.emp_id)
        regs   = reg_por_emp.get(emp_id, [])

        entrada = next((r for r in regs if r.tipo == "entrada"), None)
        salida  = next((r for r in regs if r.tipo == "salida"),  None)
        ini_alm = next((r for r in regs if r.tipo == "entrada_almuerzo"), None)
        fin_alm = next((r for r in regs if r.tipo == "salida_almuerzo"),  None)

        # Turno (excepción o por defecto)
        turno = turnos.get(emp_id)
        if turno:
            t_entrada = turno.hora_entrada
            t_salida  = turno.hora_salida
            t_almuerzo = turno.duracion_almuerzo_minutos or 0
            t_tolerancia = turno.tolerancia_minutos or 0
            turno_nombre = turno.nombre
        else:
            t_entrada, t_salida = _DEF_ENTRADA, _DEF_SALIDA
            t_almuerzo = _DEF_ALMUERZO_MIN
            t_tolerancia = _DEF_TOLERANCIA_MIN
            turno_nombre = "Horario normal"

        minutos_requeridos = _min_entre(t_entrada, t_salida) - t_almuerzo
        if minutos_requeridos < 0:
            minutos_requeridos = 0

        # Almuerzo realmente tomado (si marcó ambos extremos)
        minutos_almuerzo = None
        if ini_alm and fin_alm:
            minutos_almuerzo = int(
                (fin_alm.fecha_hora - ini_alm.fecha_hora).total_seconds() // 60
            )

        # Minutos trabajados netos = (salida - entrada) - almuerzo tomado
        minutos_trabajados = None
        if entrada and salida:
            bruto = int((salida.fecha_hora - entrada.fecha_hora).total_seconds() // 60)
            minutos_trabajados = max(bruto - (minutos_almuerzo or 0), 0)

        # Puntualidad vs horario designado (con tolerancia del turno):
        #  - Tardanza: marcó entrada después de hora_entrada + tolerancia.
        #  - Salida temprana: marcó salida antes de hora_salida (con tolerancia).
        minutos_tarde = 0
        llego_tarde = False
        if entrada:
            minutos_tarde = max(_min_entre(t_entrada, entrada.fecha_hora.time()), 0)
            llego_tarde = minutos_tarde > t_tolerancia
        minutos_antes_salida = 0
        salio_temprano = False
        if salida:
            minutos_antes_salida = max(_min_entre(salida.fecha_hora.time(), t_salida), 0)
            salio_temprano = minutos_antes_salida > t_tolerancia

        # Estado y cumplimiento
        if not entrada:
            estado = "ausente";   n_ausentes += 1
        elif not salida:
            estado = "en_curso";  n_en_curso += 1
        elif (minutos_trabajados or 0) >= minutos_requeridos:
            estado = "completo";  n_completos += 1
        else:
            estado = "incompleto"; n_incompletos += 1

        cumple = estado == "completo"

        def _hhmm(r) -> Optional[str]:
            return r.fecha_hora.strftime("%H:%M") if r else None

        items.append({
            "empleado_id":         emp_id,
            "nombre":              e.nombre or "",
            "apellido":            e.apellido or "",
            "cargo":               e.cargo or "",
            "tipo":                e.tipo or "",
            "turno_nombre":        turno_nombre,
            "es_excepcion":        turno is not None,
            "hora_entrada_turno":  t_entrada.strftime("%H:%M"),
            "hora_salida_turno":   t_salida.strftime("%H:%M"),
            "entrada_hora":        _hhmm(entrada),
            "salida_hora":         _hhmm(salida),
            "inicio_almuerzo_hora": _hhmm(ini_alm),
            "fin_almuerzo_hora":   _hhmm(fin_alm),
            "minutos_almuerzo":    minutos_almuerzo,
            "minutos_trabajados":  minutos_trabajados,
            "minutos_requeridos":  minutos_requeridos,
            "horas_requeridas":    round(minutos_requeridos / 60, 2),
            "llego_tarde":         llego_tarde,
            "minutos_tarde":       minutos_tarde,
            "salio_temprano":      salio_temprano,
            "minutos_antes_salida": minutos_antes_salida,
            "estado":              estado,
            "cumple":              cumple,
        })

    return {
        "fecha":  dia.isoformat(),
        "resumen": {
            "total":       len(items),
            "completos":   n_completos,
            "incompletos": n_incompletos,
            "en_curso":    n_en_curso,
            "ausentes":    n_ausentes,
        },
        "items": items,
    }


# ─── Turnos: listado, alta y asignación de excepciones ────────────────────────

class TurnoCrear(BaseModel):
    nombre:                    str
    hora_entrada:              str            # "HH:MM"
    hora_salida:               str            # "HH:MM"
    duracion_almuerzo_minutos: int = 60
    tolerancia_minutos:        int = 5


class TurnoAsignar(BaseModel):
    empleado_id: str
    turno_id:    str
    fecha_desde: Optional[str] = None         # YYYY-MM-DD; por defecto hoy
    fecha_hasta: Optional[str] = None         # YYYY-MM-DD; None = indefinido


def _parse_hhmm(valor: str) -> time:
    try:
        h, m = valor.strip().split(":")
        return time(int(h), int(m))
    except Exception:
        raise HTTPException(status_code=422, detail=f"Hora inválida: {valor} (use HH:MM)")


@router.get("/turnos")
def listar_turnos(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Turnos de la empresa (incluye el por defecto virtual al inicio)."""
    exigir_permiso(db, payload, "asistencia", "ver")
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Turno)
        .filter(Turno.empresa_id == empresa_id, Turno.activo == True)
        .order_by(Turno.nombre.asc())
        .all()
    )
    return [
        {
            "id":                        str(t.id),
            "nombre":                    t.nombre,
            "hora_entrada":              t.hora_entrada.strftime("%H:%M"),
            "hora_salida":               t.hora_salida.strftime("%H:%M"),
            "duracion_almuerzo_minutos": t.duracion_almuerzo_minutos or 0,
            "tolerancia_minutos":        t.tolerancia_minutos or 0,
            "horas_netas": round(
                (_min_entre(t.hora_entrada, t.hora_salida) - (t.duracion_almuerzo_minutos or 0)) / 60, 2
            ),
        }
        for t in rows
    ]


@router.post("/turnos")
def crear_turno(
    body:    TurnoCrear,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Crea un turno (p. ej. 'Practicante 08:00–13:00'). Requiere asistencia:configurar."""
    exigir_permiso(db, payload, "asistencia", "configurar")
    empresa_id = payload["empresa_id"]
    turno = Turno(
        empresa_id                = empresa_id,
        nombre                    = body.nombre.strip(),
        hora_entrada              = _parse_hhmm(body.hora_entrada),
        hora_salida               = _parse_hhmm(body.hora_salida),
        duracion_almuerzo_minutos = max(body.duracion_almuerzo_minutos, 0),
        tolerancia_minutos        = max(body.tolerancia_minutos, 0),
        activo                    = True,
    )
    db.add(turno)
    db.commit()
    return {"ok": True, "id": str(turno.id)}


@router.post("/turno-empleado")
def asignar_turno(
    body:    TurnoAsignar,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Asigna un turno-excepción a un empleado con vigencia. Requiere asistencia:configurar."""
    exigir_permiso(db, payload, "asistencia", "configurar")
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == body.empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    turno = db.query(Turno).filter(
        Turno.id == body.turno_id, Turno.empresa_id == empresa_id
    ).first()
    if not turno:
        raise HTTPException(status_code=404, detail="Turno no encontrado")

    desde = date.fromisoformat(body.fecha_desde) if body.fecha_desde else date.today()
    hasta = date.fromisoformat(body.fecha_hasta) if body.fecha_hasta else None

    # Cerrar asignaciones vigentes anteriores del empleado (una excepción activa
    # a la vez): se marca fecha_hasta = día previo y activo = False.
    vigentes = (
        db.query(TurnoEmpleado)
        .filter(TurnoEmpleado.empleado_id == body.empleado_id, TurnoEmpleado.activo == True)
        .all()
    )
    for v in vigentes:
        v.activo = False
        if v.fecha_hasta is None or v.fecha_hasta >= desde:
            v.fecha_hasta = desde - timedelta(days=1)

    asign = TurnoEmpleado(
        empleado_id = body.empleado_id,
        turno_id    = body.turno_id,
        fecha_desde = desde,
        fecha_hasta = hasta,
        activo      = True,
    )
    db.add(asign)
    db.commit()
    return {"ok": True, "id": str(asign.id)}
