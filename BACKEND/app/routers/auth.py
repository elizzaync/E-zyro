from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from passlib.context import CryptContext

from app.schemas.auth import LoginData
from app.models.usuario import Usuario
from app.models.usuario_rol import UsuarioRol
from app.models.rol import Rol
from app.db.database import get_db

# IMPORTAMOS NUESTRA FÁBRICA DE TOKENS
from app.core.security import crear_token_acceso

router = APIRouter(prefix="/auth", tags=["Autenticacion"])
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

@router.post("/login")
def login_usuario(credenciales: LoginData, db: Session = Depends(get_db)):
    # 1. Validar Credenciales
    usuario_db = db.query(Usuario).filter(Usuario.username == credenciales.username).first()

    if not usuario_db or not pwd_context.verify(credenciales.password, usuario_db.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"}
        )

    # 2. OBTENER ROL REAL (El JOIN Mágico)
   rol_asignado = db.query(Rol.nombre).join(
    UsuarioRol, UsuarioRol.rol_id == Rol.id
).filter(UsuarioRol.usuario_id == usuario_db.id).first()

    # Si la consulta encuentra un rol, extraemos el texto (ej: "Supervisor"). Si no, ponemos un default.
    nombre_rol_real = rol_asignado[0] if rol_asignado else "Sin Rol Asignado"

    # 3. Empaquetar datos vitales
    datos_para_token = {
        "sub": usuario_db.username,
        "id": usuario_db.id,
        "empresa_id": usuario_db.empresa_id,
        "rol": nombre_rol_real
    }

    # 4. Generar el JWT
    token_real = crear_token_acceso(datos_para_token)

    return {
        "status": "success",
        "mensaje": "Autenticación exitosa",
        "data": {
            "nombre_completo": f"{usuario_db.nombre} {usuario_db.apellido}",
            "rol": nombre_rol_real, # También lo devolvemos aquí por si el Frontend quiere leerlo sin decodificar
            "token": token_real
        }
    }