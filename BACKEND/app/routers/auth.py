from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from sqlalchemy import and_
from passlib.context import CryptContext
from datetime import datetime, timedelta
import uuid
import random

# Importaciones de tu proyecto
from app.schemas.auth import (
    LoginData,
    PasswordResetRequest,
    PasswordVerifyCode,
    PasswordResetConfirm
)
from app.models.usuario import Usuario
from app.models.usuario_rol import UsuarioRol
from app.models.rol import Rol
from app.models.auditoria import Auditoria
from app.models.recuperacion_password import RecuperacionPassword # Asegúrate de tener este modelo
from app.db.database import get_db
from app.core.security import crear_token_acceso

router = APIRouter(
    prefix="/auth",
    tags=["Autenticacion"]
)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# =========================================================================
# FUNCION HELPER PARA AUDITORÍA (Mantenlo centralizado)
# =========================================================================
def registrar_auditoria(db: Session, usuario_id: str, empresa_id: str, tabla: str, accion: str, ip: str, user_agent: str, desc: str):
    nueva_auditoria = Auditoria(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        usuario_id=usuario_id,
        tabla_afectada=tabla,
        accion=accion,
        modulo="seguridad",
        descripcion=desc,
        ip=ip,
        user_agent=user_agent,
        fecha=datetime.utcnow()
    )
    db.add(nueva_auditoria)

# --- LOGIN ---
@router.post("/login")
def login_usuario(credenciales: LoginData, db: Session = Depends(get_db)):
    usuario_db = db.query(Usuario).filter(Usuario.username == credenciales.username).first()

    if not usuario_db or not pwd_context.verify(credenciales.password, usuario_db.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )

    rol_asignado = db.query(Rol.nombre).join(
        UsuarioRol, UsuarioRol.rol_id == Rol.id
    ).filter(UsuarioRol.usuario_id == usuario_db.id).first()

    nombre_rol_real = rol_asignado[0] if rol_asignado else "Sin Rol Asignado"

    datos_para_token = {
        "sub": usuario_db.username,
        "id": usuario_db.id,
        "empresa_id": usuario_db.empresa_id,
        "rol": nombre_rol_real
    }

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

# =========================================================================
# 1. SOLICITAR CÓDIGO (POST /auth/password-recovery/request)
# =========================================================================
@router.post("/password-recovery/request")
async def solicitar_codigo(payload: PasswordResetRequest, request: Request, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Este correo no está registrado en el sistema.")

    # Generar código de 6 dígitos de forma segura
    codigo_plano = str(random.SystemRandom().randint(100000, 999999))

    # Guardar en BD (Encriptado)
    nuevo_registro = RecuperacionPassword(
        id=str(uuid.uuid4()),
        usuario_id=usuario.id,
        codigo_hash=pwd_context.hash(codigo_plano),
        ip_solicitud=request.client.host,
        fecha_expiracion=datetime.utcnow() + timedelta(minutes=15)
    )
    db.add(nuevo_registro)

    registrar_auditoria(db, usuario.id, usuario.empresa_id, "recuperacion_password",
                        "PASSWORD_RECOVERY_REQUEST", request.client.host,
                        request.headers.get("user-agent", "Desconocido"),
                        f"Solicitud OTP para {payload.email}")
    db.commit()

# =========================================================================
# 2. VERIFICAR CÓDIGO (POST /auth/password-recovery/verify)
# =========================================================================
@router.post("/password-recovery/verify")
async def verificar_codigo(payload: PasswordVerifyCode, request: Request, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")

    registro_otp = db.query(RecuperacionPassword).filter(
        RecuperacionPassword.usuario_id == usuario.id,
        RecuperacionPassword.usado == False
    ).order_by(RecuperacionPassword.created_at.desc()).first()

    if not registro_otp:
        raise HTTPException(status_code=400, detail="No has solicitado un código.")

    if datetime.utcnow() > registro_otp.fecha_expiracion:
        raise HTTPException(status_code=400, detail="El código ha expirado.")

    if registro_otp.intentos_fallidos >= 3:
        registrar_auditoria(db, usuario.id, usuario.empresa_id, "recuperacion_password",
                            "PASSWORD_RECOVERY_BLOCKED", request.client.host,
                            request.headers.get("user-agent", "Desconocido"), "Código bloqueado por intentos.")
        db.commit()
        raise HTTPException(status_code=403, detail="Demasiados intentos fallidos. Solicita uno nuevo.")

    if not pwd_context.verify(payload.code, registro_otp.codigo_hash):
        registro_otp.intentos_fallidos += 1
        registrar_auditoria(db, usuario.id, usuario.empresa_id, "recuperacion_password",
                            "PASSWORD_RECOVERY_FAILED", request.client.host,
                            request.headers.get("user-agent", "Desconocido"), f"Fallo OTP #{registro_otp.intentos_fallidos}")
        db.commit()
        raise HTTPException(status_code=400, detail="Código incorrecto.")

    return {"status": "success", "mensaje": "Código verificado correctamente."}

# =========================================================================
# 3. ACTUALIZAR CONTRASEÑA (POST /auth/password-recovery/reset)
# =========================================================================
@router.post("/password-recovery/reset")
async def actualizar_password(payload: PasswordResetConfirm, request: Request, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")

    registro_otp = db.query(RecuperacionPassword).filter(
        RecuperacionPassword.usuario_id == usuario.id,
        RecuperacionPassword.usado == False
    ).order_by(RecuperacionPassword.created_at.desc()).first()

    if not registro_otp or datetime.utcnow() > registro_otp.fecha_expiracion or registro_otp.intentos_fallidos >= 3:
        raise HTTPException(status_code=400, detail="La solicitud de cambio es inválida o ha expirado.")

    if not pwd_context.verify(payload.code, registro_otp.codigo_hash):
        raise HTTPException(status_code=400, detail="Validación fallida.")

    # Cambio de password final
    usuario.password_hash = pwd_context.hash(payload.new_password)
    usuario.updated_at = datetime.utcnow()
    registro_otp.usado = True

    registrar_auditoria(db, usuario.id, usuario.empresa_id, "usuario",
                        "PASSWORD_CHANGED_SUCCESS", request.client.host,
                        request.headers.get("user-agent", "Desconocido"), "Contraseña reseteada exitosamente.")
    db.commit()

    return {"status": "success", "mensaje": "Tu contraseña ha sido actualizada."}