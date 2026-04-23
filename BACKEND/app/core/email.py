import os
from fastapi_mail import FastMail, MessageSchema, ConnectionConfig, MessageType
from pydantic import EmailStr
from dotenv import load_dotenv

load_dotenv()

# Configuración de conexión con Gmail (VÍA RÁPIDA SSL)
# Configuración de conexión con Gmail (VÍA RÁPIDA SSL)
conf = ConnectionConfig(
    MAIL_USERNAME = os.getenv("MAIL_USERNAME"),
    MAIL_PASSWORD = os.getenv("MAIL_PASSWORD"),
    MAIL_FROM = os.getenv("MAIL_FROM"),
    MAIL_PORT = 465,        # <-- Forzamos el puerto 465
    MAIL_SERVER = "smtp.gmail.com",
    MAIL_FROM_NAME = os.getenv("MAIL_FROM_NAME", "E-SystemTic Soporte"),
    MAIL_STARTTLS = False,  # <-- APAGAMOS ESTO
    MAIL_SSL_TLS = True,    # <-- ENCENDEMOS ESTO
    USE_CREDENTIALS = True,
    VALIDATE_CERTS = True
)

async def enviar_correo_otp(email_destino: EmailStr, codigo_otp: str):
    # ... (tu código html sigue igual)
    html = f"""
    <html>
        <body style="font-family: sans-serif;">
            <h2>Verificación de Seguridad</h2>
            <p>Tu código de recuperación para <b>E-SystemTic</b> es:</p>
            <h1 style="color: #8dc63f; letter-spacing: 5px;">{codigo_otp}</h1>
            <p>Este código expira en 15 minutos.</p>
        </body>
    </html>
    """

    message = MessageSchema(
        subject="Código de Recuperación - E-SystemTic",
        recipients=[email_destino],
        body=html,
        subtype=MessageType.html
    )

    fm = FastMail(conf)
    await fm.send_message(message)