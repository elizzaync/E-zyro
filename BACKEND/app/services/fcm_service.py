# app/services/fcm_service.py
import logging
import os
import json
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


# ── Resolución de canal Android por tipo/categoría ──────────────────────────────
# Debe coincidir con los canales declarados en el cliente Flutter
# (NotificationService._todos).
def _canal_android(tipo: str, categoria: str) -> str:
    t = (tipo or "").lower()
    c = (categoria or "").lower()
    if c == "almuerzo":
        return "esystemtic_almuerzo"
    if t == "warning" or c == "mantenimiento":
        return "esystemtic_alertas"
    if t.startswith("comunicado"):
        return "esystemtic_comunicados"
    if t == "servicio" or t.startswith("asignacion"):
        return "esystemtic_servicios"
    return "esystemtic_general"


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
