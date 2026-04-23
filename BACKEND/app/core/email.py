import os
from fastapi_mail import FastMail, MessageSchema, ConnectionConfig, MessageType
from pydantic import EmailStr
from dotenv import load_dotenv

load_dotenv()

# Configuración de conexión con Gmail
conf = ConnectionConfig(
    MAIL_USERNAME = os.getenv("MAIL_USERNAME"),
    MAIL_PASSWORD = os.getenv("MAIL_PASSWORD"),
    MAIL_FROM = os.getenv("MAIL_FROM"),
    MAIL_PORT = int(os.getenv("MAIL_PORT")),
    MAIL_SERVER = os.getenv("MAIL_SERVER"),
    MAIL_FROM_NAME = os.getenv("MAIL_FROM_NAME"),
    MAIL_STARTTLS = True,
    MAIL_SSL_TLS = False,
    USE_CREDENTIALS = True,
    VALIDATE_CERTS = True
)

async def enviar_correo_otp(email_destino: EmailStr, codigo_otp: str):
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