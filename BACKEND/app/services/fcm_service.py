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


# ── Función genérica de envío ──────────────────────────────────────────────────
def enviar_push_a_usuario(
    usuario_id: str,
    titulo: str,
    mensaje: str,
    db: Session,
    tipo: str = "general",
    referencia_id: str = "",
    referencia_tabla: str = "",
) -> bool:
    """
    Busca los tokens activos del usuario y envía una notificación push.

    Parámetros de data para el cliente Flutter:
      tipo            → categoria de la notificación (general|comunicado|servicio|recordatorio)
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
            "ref_id": referencia_id or "",
            "ref_tabla": referencia_tabla or "",
        }

        enviados = 0
        for disp in dispositivos:
            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=titulo,
                        body=mensaje,
                    ),
                    data=data_payload,
                    token=disp.token_push,
                    # Android: prioridad alta para que llegue en background
                    android=messaging.AndroidConfig(
                        priority="high",
                        notification=messaging.AndroidNotification(
                            channel_id="esystemtic_general",
                            sound="default",
                        ),
                    ),
                    # iOS: sonido y badge
                    apns=messaging.APNSConfig(
                        payload=messaging.APNSPayload(
                            aps=messaging.Aps(
                                sound="default",
                                badge=1,
                            )
                        )
                    ),
                )
                messaging.send(message)
                logger.info("Push enviado a %s.", disp.plataforma)
                enviados += 1

            except messaging.UnregisteredError:
                logger.warning("Token inválido, desactivando.")
                disp.activo = False
                db.commit()

            except Exception as e:
                logger.error("Error enviando push: %s", type(e).__name__)

        return enviados > 0

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
