# app/services/fcm_service.py
import os
import json
import firebase_admin
from firebase_admin import credentials, messaging
from sqlalchemy.orm import Session
from app.models.dispositivo_push import DispositivoPush

# 1. Inicializamos la conexión con Firebase de forma segura (Railway o Local)
try:
    firebase_json_str = os.environ.get("FIREBASE_JSON")

    if firebase_json_str:
        cred_dict = json.loads(firebase_json_str)
        cred = credentials.Certificate(cred_dict)
        print("🔧 Firebase inicializado usando Variable de Entorno (Producción)")
    else:
        # Si no existe la variable, usamos el archivo local (Para tu PC)
        cred = credentials.Certificate("firebase-credentials.json")
        print("🔧 Firebase inicializado usando Archivo Local (Desarrollo)")

    # Verificamos si ya está inicializada para evitar errores si se recarga el servidor
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)

except Exception as e:
    print(f"⚠️ Error al inicializar Firebase Admin: {e}")


def enviar_push_a_usuario(usuario_id: str, titulo: str, mensaje: str, db: Session):
    """
    Busca los tokens del usuario y le envía una notificación Push.
    """
    try:
        # Buscamos todos los dispositivos activos del usuario (puede tener PC y Celular)
        dispositivos = db.query(DispositivoPush).filter(
            DispositivoPush.usuario_id == usuario_id,
            DispositivoPush.activo == True
        ).all()

        if not dispositivos:
            print(f"No hay dispositivos registrados para el usuario {usuario_id}")
            return False

        # Le disparamos el mensaje a cada dispositivo que tenga
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
                print(f"✅ Push enviado con éxito a {disp.plataforma}: {response}")
            except Exception as e:
                print(f"❌ Error enviando push al token {disp.token_push}: {e}")

        return True
    except Exception as e:
        print(f"Error general en FCM: {e}")
        return False