# app/services/fcm_service.py
import os
import json
import firebase_admin
from firebase_admin import credentials, messaging
from sqlalchemy.orm import Session
from app.models.dispositivo_push import DispositivoPush


# ── Inicialización segura de Firebase (solo una vez) ──────────────────────────
def _inicializar_firebase():
    """
    Inicializa Firebase Admin SDK.
    - Producción (Railway): usa la variable de entorno FIREBASE_JSON
    - Desarrollo (local):   usa el archivo firebase-credentials.json
    Se protege contra doble inicialización con el chequeo de _apps.
    """
    if firebase_admin._apps:
        return   # ← ya está inicializado, salimos sin hacer nada

    try:
        firebase_json_str = os.environ.get("FIREBASE_JSON")

        if firebase_json_str:
            cred_dict = json.loads(firebase_json_str)
            cred = credentials.Certificate(cred_dict)
            print("🔧 Firebase inicializado usando Variable de Entorno (Producción)")
        else:
            cred = credentials.Certificate("firebase-credentials.json")
            print("🔧 Firebase inicializado usando Archivo Local (Desarrollo)")

        firebase_admin.initialize_app(cred)

    except Exception as e:
        print(f"⚠️  Error al inicializar Firebase Admin: {e}")


# Se llama una sola vez al importar el módulo
_inicializar_firebase()


# ── Función genérica de envío ──────────────────────────────────────────────────
def enviar_push_a_usuario(usuario_id: str, titulo: str, mensaje: str, db: Session) -> bool:
    """
    Busca los tokens activos del usuario y le envía una notificación Push.
    Retorna True si al menos un push fue enviado.
    """
    try:
        dispositivos = db.query(DispositivoPush).filter(
            DispositivoPush.usuario_id == usuario_id,
            DispositivoPush.activo == True
        ).all()

        if not dispositivos:
            print(f"⚠️  Sin dispositivos registrados para el usuario {usuario_id}")
            return False

        enviados = 0
        for disp in dispositivos:
            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=titulo,
                        body=mensaje
                    ),
                    token=disp.token_push
                )
                response = messaging.send(message)
                print(f"✅ Push enviado a {disp.plataforma} [{disp.token_push[:20]}...]: {response}")
                enviados += 1

            except messaging.UnregisteredError:
                # El token ya no es válido → lo desactivamos para no volver a usarlo
                print(f"🗑️  Token inválido detectado, desactivando: {disp.token_push[:20]}...")
                disp.activo = False
                db.commit()

            except Exception as e:
                print(f"❌ Error enviando push al token {disp.token_push[:20]}...: {e}")

        return enviados > 0

    except Exception as e:
        print(f"❌ Error general en FCM: {e}")
        return False


# ── Notificación de asignación de servicio a técnico ──────────────────────────
def notificar_asignacion_servicio(
    usuario_id_tecnico: str,
    nombre_tecnico: str,
    nombre_servicio: str,
    nombre_cliente: str,
    fecha_servicio: str,
    db: Session
) -> bool:
    """
    Notifica a un técnico que le acaban de asignar un nuevo servicio.

    Ejemplo de uso en tu router de proyectos/servicios:
    -------------------------------------------------------
    from app.services.fcm_service import notificar_asignacion_servicio

    notificar_asignacion_servicio(
        usuario_id_tecnico = tecnico.usuario_id,
        nombre_tecnico     = tecnico.nombre,
        nombre_servicio    = catalogo.nombre,
        nombre_cliente     = cliente.razon_social,
        fecha_servicio     = proyecto.fecha_inicio.strftime("%d/%m/%Y"),
        db                 = db
    )
    -------------------------------------------------------
    """
    titulo  = "🔧 Nuevo Servicio Asignado"
    mensaje = (
        f"Hola {nombre_tecnico}, tienes un nuevo servicio: "
        f"{nombre_servicio} para {nombre_cliente} el {fecha_servicio}."
    )

    print(f"[FCM] Notificando asignación al técnico {usuario_id_tecnico}")
    return enviar_push_a_usuario(
        usuario_id=usuario_id_tecnico,
        titulo=titulo,
        mensaje=mensaje,
        db=db
    )


# ── Notificación de recordatorio de calendario ─────────────────────────────────
def notificar_recordatorio_calendario(
    usuario_id: str,
    texto_nota: str,
    cuando: str,       # "hoy" o "mañana"
    db: Session
) -> bool:
    """
    Envía un recordatorio de una nota de calendario al usuario.
    Usado tanto por el scheduler como manualmente.
    """
    titulo  = "📅 Recordatorio de Calendario"
    mensaje = f"Tienes un evento {cuando}: {texto_nota}"

    return enviar_push_a_usuario(
        usuario_id=usuario_id,
        titulo=titulo,
        mensaje=mensaje,
        db=db
    )