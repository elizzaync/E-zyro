# app/services/fcm_service.py
import logging
import os
import json
import uuid as _uuid
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, messaging
from sqlalchemy.orm import Session
from app.models.dispositivo_push import DispositivoPush

logger = logging.getLogger(__name__)


# ── Inicialización segura de Firebase (solo una vez) ──────────────────────────
def _inicializar_firebase():
    if firebase_admin._apps:
        return

    try:
        firebase_json_str = os.environ.get("FIREBASE_JSON")
        if firebase_json_str:
            cred_dict = json.loads(firebase_json_str)
            cred = credentials.Certificate(cred_dict)
            logger.info("Firebase inicializado usando Variable de Entorno.")
        else:
            cred = credentials.Certificate("firebase-credentials.json")
            logger.info("Firebase inicializado usando Archivo Local.")
        firebase_admin.initialize_app(cred)
    except Exception as e:
        logger.error("Error al inicializar Firebase Admin: %s", type(e).__name__)


_inicializar_firebase()


# ── Grupo de preferencia / canal por tipo+categoría ─────────────────────────────
# Los 6 grupos coinciden con los canales Android y con las preferencias del usuario.
PREF_CATEGORIAS = ["general", "almuerzo", "alertas", "comunicados", "servicios", "chat"]
# Default de cada grupo cuando el usuario no tiene fila de preferencia:
PREF_DEFAULT = {
    "general": True, "almuerzo": True, "alertas": True,
    "comunicados": True, "servicios": True, "chat": False,
}


def _grupo_preferencia(tipo: str, categoria: str) -> str:
    """Mapea (tipo, categoria) al grupo de preferencia/canal."""
    t = (tipo or "").lower()
    c = (categoria or "").lower()
    if c == "chat" or t == "chat":
        return "chat"
    if c == "almuerzo":
        return "almuerzo"
    if t.startswith("comunicado") or c == "comunicado":
        return "comunicados"
    if t == "servicio" or t.startswith("asignacion") or c == "servicio":
        return "servicios"
    if t == "warning" or c in ("mantenimiento", "finanzas", "rrhh",
                               "calibracion", "asistencia", "prestamos"):
        return "alertas"
    return "general"


_CANAL_POR_GRUPO = {
    "almuerzo":    "esystemtic_almuerzo",
    "alertas":     "esystemtic_alertas",
    "comunicados": "esystemtic_comunicados",
    "servicios":   "esystemtic_servicios",
    "chat":        "esystemtic_general",
    "general":     "esystemtic_general",
}


def _canal_android(tipo: str, categoria: str) -> str:
    return _CANAL_POR_GRUPO.get(_grupo_preferencia(tipo, categoria), "esystemtic_general")


def _push_habilitado(db: Session, usuario_id: str, grupo: str) -> bool:
    """Consulta la preferencia del usuario para el grupo. Sin fila → default."""
    try:
        from app.models.preferencia_notificacion import PreferenciaNotificacion
        pref = db.query(PreferenciaNotificacion.activo).filter(
            PreferenciaNotificacion.usuario_id == usuario_id,
            PreferenciaNotificacion.categoria == grupo,
        ).first()
        if pref is not None:
            return bool(pref.activo)
    except Exception:
        pass
    return PREF_DEFAULT.get(grupo, True)


# ── Función genérica de envío ──────────────────────────────────────────────────
def enviar_push_a_usuario(
    usuario_id: str,
    titulo: str,
    mensaje: str,
    db: Session,
    tipo: str = "general",
    referencia_id: str = "",
    referencia_tabla: str = "",
    categoria: str = "",
) -> bool:
    """
    Busca los tokens activos del usuario y envía una notificación push a TODOS
    sus dispositivos en una sola llamada multicast.

    Parámetros de data para el cliente Flutter:
      tipo            → tipo de la notificación (general|comunicado|servicio|recordatorio|warning)
      categoria       → subcategoría (almuerzo|mantenimiento|...) — elige el canal
      referencia_id   → UUID del objeto relacionado (opcional)
      referencia_tabla→ nombre de la tabla relacionada (opcional)

    Retorna True si al menos un push fue enviado correctamente.
    """
    try:
        # Respetar la preferencia del usuario para este grupo de notificación.
        grupo = _grupo_preferencia(tipo, categoria)
        if not _push_habilitado(db, usuario_id, grupo):
            logger.info("Push omitido por preferencia (%s) del usuario.", grupo)
            return False

        dispositivos = db.query(DispositivoPush).filter(
            DispositivoPush.usuario_id == usuario_id,
            DispositivoPush.activo == True,
        ).all()

        if not dispositivos:
            logger.warning("Sin dispositivos registrados para usuario.")
            return False

        # Payload de datos que Flutter recibe al tocar la notificación
        data_payload = {
            "tipo": tipo,
            "categoria": categoria or "",
            "ref_id": referencia_id or "",
            "ref_tabla": referencia_tabla or "",
        }

        canal = _canal_android(tipo, categoria)
        # tag/collapse: avisos del mismo asunto se reemplazan en vez de apilarse.
        tag = (f"{referencia_tabla}:{referencia_id}"
               if referencia_tabla else (categoria or tipo))[:64]

        tokens = [d.token_push for d in dispositivos]
        multicast = messaging.MulticastMessage(
            notification=messaging.Notification(title=titulo, body=mensaje),
            data=data_payload,
            tokens=tokens,
            android=messaging.AndroidConfig(
                priority="high",
                collapse_key=tag,
                notification=messaging.AndroidNotification(
                    channel_id=canal,
                    sound="default",
                    tag=tag,
                ),
            ),
            apns=messaging.APNSConfig(
                headers={"apns-collapse-id": tag},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound="default",
                        badge=1,
                        thread_id=tag,
                    )
                ),
            ),
        )

        resp = messaging.send_each_for_multicast(multicast)

        # Desactivar tokens que Firebase reporta como inválidos.
        hubo_invalidos = False
        for idx, r in enumerate(resp.responses):
            if r.success:
                continue
            exc = r.exception
            if isinstance(exc, (messaging.UnregisteredError,
                                messaging.SenderIdMismatchError)):
                dispositivos[idx].activo = False
                hubo_invalidos = True
            else:
                logger.error("Error enviando push: %s",
                             type(exc).__name__ if exc else "desconocido")
        if hubo_invalidos:
            db.commit()

        logger.info("Push multicast: %d/%d entregados.",
                    resp.success_count, len(tokens))
        return resp.success_count > 0

    except Exception as e:
        logger.error("Error general en FCM: %s", type(e).__name__)
        return False


# ── Helper para routers: persistir in-app + enviar push ─────────────────────────
def notificar_usuario(
    db: Session,
    *,
    empresa_id: str,
    usuario_id: str,
    titulo: str,
    mensaje: str,
    tipo: str = "general",
    categoria: str = "",
    referencia_id: str = "",
    referencia_tabla: str = "",
) -> bool:
    """Crea la fila Notificacion (campana in-app) y dispara el push FCM.
    No bloquea el flujo del router si algo falla. Devuelve True si el push salió.

    Nota: referencia_id de la tabla notificacion es uuid → se deja NULL; el
    contexto de deep-link viaja en referencia_tabla y en el data payload del push.
    """
    from app.models.notificacion import Notificacion
    fcm_ok = False
    try:
        n = Notificacion(
            id=str(_uuid.uuid4()),
            empresa_id=empresa_id,
            usuario_id=usuario_id,
            tipo=tipo,
            categoria=categoria or None,
            titulo=titulo,
            mensaje=mensaje,
            leido=False,
            enviado=False,
            fecha_envio=datetime.utcnow(),
            referencia_tabla=referencia_tabla or None,
            referencia_id=None,
        )
        db.add(n)
        db.flush()
        fcm_ok = enviar_push_a_usuario(
            usuario_id=usuario_id, titulo=titulo, mensaje=mensaje, db=db,
            tipo=tipo, categoria=categoria,
            referencia_id=referencia_id or "", referencia_tabla=referencia_tabla or "",
        )
        n.enviado = fcm_ok
    except Exception as e:
        logger.error("notificar_usuario falló: %s", type(e).__name__)
    return fcm_ok


# ── Notificación de asignación de servicio ────────────────────────────────────
def notificar_asignacion_servicio(
    usuario_id_tecnico: str,
    nombre_tecnico: str,
    nombre_servicio: str,
    nombre_cliente: str,
    fecha_servicio: str,
    db: Session,
    proyecto_id: str = "",
) -> bool:
    titulo  = "🔧 Nuevo Servicio Asignado"
    mensaje = (
        f"Hola {nombre_tecnico}, tienes un nuevo servicio: "
        f"{nombre_servicio} para {nombre_cliente} el {fecha_servicio}."
    )
    logger.info("Notificando asignación de servicio.")
    return enviar_push_a_usuario(
        usuario_id=usuario_id_tecnico,
        titulo=titulo,
        mensaje=mensaje,
        tipo="servicio",
        referencia_id=proyecto_id,
        referencia_tabla="proyecto",
        db=db,
    )


# ── Notificación de recordatorio de calendario ────────────────────────────────
def notificar_recordatorio_calendario(
    usuario_id: str,
    texto_nota: str,
    cuando: str,
    db: Session,
    recordatorio_id: str = "",
) -> bool:
    titulo  = "📅 Recordatorio de Calendario"
    mensaje = f"Tienes un evento {cuando}: {texto_nota}"
    return enviar_push_a_usuario(
        usuario_id=usuario_id,
        titulo=titulo,
        mensaje=mensaje,
        tipo="recordatorio",
        referencia_id=recordatorio_id,
        referencia_tabla="recordatorio",
        db=db,
    )
