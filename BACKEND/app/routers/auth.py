from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from app.schemas.auth import LoginData
from app.models.usuario import Usuario
from app.db.database import get_db
# Creamos el router
router = APIRouter(
    prefix="/auth",
    tags=["Autenticacion"]
)
# Configuramos el motor de encriptación (Bcrypt)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
@router.post("/login")
def login_usuario(credenciales: LoginData, db: Session = Depends(get_db)):

    # 1. Buscar al usuario en Postgres usando el username (que recibe 'admin_zyro')
    usuario_db = db.query(Usuario).filter(Usuario.username == credenciales.username).first()

    if not usuario_db:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # 2. Verificar que la contraseña '123456' coincida con el hash de la BD
    if not pwd_context.verify(credenciales.password, usuario_db.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # 3. Éxito: Extraemos sus UUIDs reales y su nombre
    return {
        "status": "success",
        "mensaje": "Autenticacion exitosa",
        "data": {
            "usuario_id": usuario_db.id,
            "empresa_id": usuario_db.empresa_id,
            "nombre_completo": f"{usuario_db.nombre} {usuario_db.apellido}",
            "rol": "Técnico", # En el próximo sprint podemos sacar esto de la tabla 'rol'
            "token": "fake-jwt-token-12345"
        }
    }