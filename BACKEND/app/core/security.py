import os
from dotenv import load_dotenv
from datetime import datetime, timedelta
from jose import jwt, JWTError
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

# ¡NUEVO! Le decimos a Python que lea el archivo oculto .env
load_dotenv()

# 1. Configuración de tu cerradura
# En lugar de escribir la clave, la jalamos de forma segura usando os.getenv
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 480 # 8 horas

# Esto le dice a FastAPI que busque el token en la cabecera (Header) de las peticiones
security = HTTPBearer()

# 2. Función para CREAR el token (Dar la pulsera)
def crear_token_acceso(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})

    # Creamos la firma uniendo los datos con tu SECRET_KEY
    token_codificado = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return token_codificado

# 3. Función para VERIFICAR el token (El guardia de seguridad)
def verificar_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        # Intentamos descifrar el token usando tu llave secreta
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])

        # Extraemos los datos útiles
        usuario_id: str = payload.get("id")
        empresa_id: str = payload.get("empresa_id")

        if usuario_id is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token inválido")

        # Devolvemos los datos del usuario si todo está bien
        return payload

    except JWTError:
        # Si el token expiró o alguien lo alteró, el guardia bloquea el paso
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No se pudo validar las credenciales o el token ha expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )