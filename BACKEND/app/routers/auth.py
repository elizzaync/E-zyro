from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from sqlalchemy import and_
from passlib.context import CryptContext
from datetime import datetime, timedelta
import uuid

# Importaciones de tu proyecto
from app.schemas.auth import LoginData, PasswordResetRequest
from app.models.usuario import Usuario
from app.models.usuario_rol import UsuarioRol
from app.models.rol import Rol
from app.models.auditoria import Auditoria
from app.db.database import get_db
from app.core.security import crear_token_acceso

router = APIRouter(
    prefix="/auth",
    tags=["Autenticacion"]
)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# --- LOGIN ---
@router.post("/login")
def login_usuario(credenciales: LoginData, db: Session = Depends(get_db)):
    # 1. Validar Credenciales
    usuario_db = db.query(Usuario).filter(Usuario.username == credenciales.username).first()

    if not usuario_db or not pwd_context.verify(credenciales.password, usuario_db.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 2. Obtener rol real (AQUÍ ESTABA EL ERROR DE ESPACIOS)
    rol_asignado = db.query(Rol.nombre).join(
        UsuarioRol, UsuarioRol.rol_id == Rol.id
    ).filter(UsuarioRol.usuario_id == usuario_db.id).first()

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
            "rol": nombre_rol_real,
            "token": token_real
        }
    }

# --- RECUPERAR CONTRASEÑA ---
@router.post("/password-reset-request")
async def solicitar_recuperacion(payload: PasswordResetRequest, request: Request, db: Session = Depends(get_db)):
    user_agent = request.headers.get("user-agent")
    ip_cliente = request.client.host

    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="El correo electrónico no coincide con nuestros registros."
        )

    hace_30_dias = datetime.utcnow() - timedelta(days=30)

    ultimo_evento = db.query(Auditoria).filter(
        and_(
            Auditoria.usuario_id == usuario.id,
            Auditoria.accion.in_(["RESTORE_PASSWORD_REQUEST", "PASSWORD_CHANGED_SUCCESS"]),
            Auditoria.fecha >= hace_30_dias
        )
    ).order_by(Auditoria.fecha.desc()).first()

    if ultimo_evento:
        tiempo_transcurrido = datetime.utcnow() - ultimo_evento.fecha
        dias_restantes = 30 - tiempo_transcurrido.days
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Solo puedes restaurar tu contraseña una vez al mes. Faltan {dias_restantes} días."
        )

    nueva_auditoria = Auditoria(
        id=str(uuid.uuid4()),
        empresa_id=usuario.empresa_id,
        usuario_id=usuario.id,
        tabla_afectada="usuario",
        registro_id=usuario.id,
        accion="RESTORE_PASSWORD_REQUEST",
        modulo="seguridad",
        descripcion=f"Solicitud de enlace de recuperación para: {payload.email}",
        ip=ip_cliente,
        user_agent=user_agent,
        fecha=datetime.utcnow()
    )

    db.add(nueva_auditoria)
    db.commit()

    return {
        "status": "success",
        "mensaje": "Enlace de recuperación enviado al correo correctamente."
    }