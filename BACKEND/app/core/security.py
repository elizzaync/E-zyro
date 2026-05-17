import os
from dotenv import load_dotenv
from datetime import datetime, timedelta
from jose import jwt, JWTError
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
load_dotenv()
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 120  # 2 horas (reducido de 8 h para limitar ventana de ataque)
security = HTTPBearer()
def crear_token_acceso(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    token_codificado = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return token_codificado
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