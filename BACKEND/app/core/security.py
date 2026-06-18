import os
from dotenv import load_dotenv
from datetime import datetime, timedelta
from jose import jwt, JWTError
from fastapi import HTTPException, Request, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.core.session_cache import sesion_activa, hash_token
load_dotenv()
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES        = 240    # 4 horas — web
ACCESS_TOKEN_EXPIRE_MINUTES_MOBILE = 10080  # 7 días  — app móvil
security = HTTPBearer()

def crear_token_acceso(data: dict, expire_minutes: int = ACCESS_TOKEN_EXPIRE_MINUTES):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=expire_minutes)
    to_encode.update({"exp": expire})
    token_codificado = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return token_codificado
_ROLES_ADMIN = {"superadmin", "admin", "administrador"}

def es_superadmin(payload: dict) -> bool:
    """SuperAdmin siempre tiene permiso absoluto — sin consulta a BD.
    Normaliza espacios para reconocer "Super Admin" además de "SuperAdmin"."""
    rol = (payload.get("rol") or "").lower().strip().replace(" ", "")
    return rol in _ROLES_ADMIN


# Prefijos accesibles para cuentas del Portal Cliente (rol ClienteExterno).
# Sin este candado, el usuario portal (que vive dentro de la empresa operadora)
# podría leer endpoints internos que solo exigen token: la mayoría de los GET
# no llaman tiene_permiso/exigir_*.
_PREFIJOS_PORTAL = ("/portal-cliente", "/auth")


def verificar_token(request: Request, credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        # Intentamos descifrar el token usando tu llave secreta
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        # Extraemos los datos útiles
        usuario_id: str = payload.get("id")
        empresa_id: str = payload.get("empresa_id")

        if usuario_id is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token inválido")

        rol = (payload.get("rol") or "").lower().strip().replace(" ", "")
        if rol == "clienteexterno" and not request.url.path.startswith(_PREFIJOS_PORTAL):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Acceso restringido al Portal Cliente.",
            )

        # Expulsión real: el JWT puede ser válido (firma + no expirado) pero la
        # sesión pudo cerrarse (logout / cierre remoto / "cerrar todas"). Si no
        # sigue activa en BD, el token queda revocado de inmediato. La validación
        # usa una caché con TTL (session_cache) para no consultar BD en cada
        # request — clave para escalar a miles de usuarios.
        if not sesion_activa(hash_token(token), usuario_id):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Tu sesión fue cerrada. Inicia sesión nuevamente.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Devolvemos los datos del usuario si todo está bien
        return payload
    except JWTError:
        # Si el token expiró o alguien lo alteró, el guardia bloquea el paso
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No se pudo validar las credenciales o el token ha expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )