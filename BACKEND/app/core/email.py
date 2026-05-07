import requests

# Reemplaza esto con la URL larguísima que te dio Google
URL_GOOGLE_SCRIPT = "https://script.google.com/macros/s/AKfycbyq5y-h2R0JPVL4REIL1Q5FQIUf15JSy-nnfvCTNBWIkdbK-4MPVNyZlyaYa-j59muS/exec"

async def enviar_correo_otp(email_destino: str, codigo_otp: str):
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

    payload = {
        "to": email_destino,
        "subject": "Código de Recuperación - E-SystemTic",
        "html": html
    }

    # Enviamos por la puerta 443 (HTTPS). Railway no puede bloquear esto.
    requests.post(URL_GOOGLE_SCRIPT, json=payload)