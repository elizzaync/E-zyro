from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from datetime import datetime, timedelta
import uuid
import random
from app.schemas.auth import (
    LoginData,
    PasswordResetRequest,
    PasswordVerifyCode,
    PasswordResetConfirm
)
from app.models.usuario import Usuario
from app.models.auditoria import Auditoria
from app.models.recuperacion_password import RecuperacionPassword
from app.db.database import get_db
from app.core.security import crear_token_acceso
import json
from zoneinfo import ZoneInfo
from app.core.email import enviar_correo_otp
router = APIRouter(prefix="/auth", tags=["Autenticacion"])
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
ZONA_HORARIA = ZoneInfo("America/Lima")
# =========================================================================
# FUNCION HELPER PARA AUDITORÍA
# =========================================================================
def registrar_auditoria(db: Session, usuario_id: str, empresa_id: str, tabla: str, accion: str, ip: str, user_agent: str, desc: str, registro_id: str = None, datos_anteriores: dict = None, datos_nuevos: dict = None):
    nueva_auditoria = Auditoria(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        usuario_id=usuario_id,
        tabla_afectada=tabla,
        registro_id=registro_id,
        accion=accion,
        modulo="seguridad",
        datos_anteriores=json.dumps(datos_anteriores) if datos_anteriores else None,
        datos_nuevos=json.dumps(datos_nuevos) if datos_nuevos else None,
        descripcion=desc,
        ip=ip,
        user_agent=user_agent,
        fecha=datetime.now(ZONA_HORARIA)
    )
    db.add(nueva_auditoria)

# =========================================================================
# 1. SOLICITAR CÓDIGO
# =========================================================================
@router.post("/password-recovery/request")
async def solicitar_codigo(payload: PasswordResetRequest, request: Request, db: Session = Depends(get_db)):
    ip_cliente = request.client.host
    user_agent = request.headers.get("user-agent", "Desconocido")

    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Este correo no está registrado en el sistema.")

    # 1. Generar código de 6 dígitos de forma segura
    codigo_plano = str(random.SystemRandom().randint(100000, 999999))

    # 2. Encriptar el código para la BD
    codigo_encriptado = pwd_context.hash(codigo_plano)
    fecha_exp = datetime.utcnow() + timedelta(minutes=15)

    # 3. Guardar registro temporal
    nuevo_registro = RecuperacionPassword(
        id=str(uuid.uuid4()),
        usuario_id=usuario.id,
        codigo_hash=codigo_encriptado,
        ip_solicitud=ip_cliente,
        fecha_expiracion=fecha_exp,
        created_at=datetime.utcnow()
    )
    db.add(nuevo_registro)

    # 4. Registrar en Auditoría
    registrar_auditoria(
        db=db,
        usuario_id=usuario.id,
        empresa_id=usuario.empresa_id,
        tabla="recuperacion_password",
        accion="PASSWORD_RECOVERY_REQUEST",
        ip=ip_cliente,
        user_agent=user_agent,
        desc=f"Solicitud de código OTP para {payload.email}",
        registro_id=usuario.id  # <-- Añadido
    )
    db.commit()

    try:
        await enviar_correo_otp(payload.email, codigo_plano)
    except Exception as e:
        print(f"Error enviando correo: {e}")

    return {"status": "success", "mensaje": "Código de seguridad enviado al correo."}

# =========================================================================
# 2. VERIFICAR CÓDIGO
# =========================================================================
@router.post("/password-recovery/verify")
async def verificar_codigo(payload: PasswordVerifyCode, request: Request, db: Session = Depends(get_db)):
    ip_cliente = request.client.host
    user_agent = request.headers.get("user-agent", "Desconocido")

    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")

    # Buscar el último código activo pedido por este usuario
    registro_otp = db.query(RecuperacionPassword).filter(
        RecuperacionPassword.usuario_id == usuario.id,
        RecuperacionPassword.usado == False
    ).order_by(RecuperacionPassword.created_at.desc()).first()

    if not registro_otp:
        raise HTTPException(status_code=400, detail="No has solicitado un código de recuperación.")

    # Validaciones de Seguridad (Expiración e Intentos)
    if datetime.utcnow() > registro_otp.fecha_expiracion:
        raise HTTPException(status_code=400, detail="El código de seguridad ha expirado.")

    if registro_otp.intentos_fallidos >= 3:
        registrar_auditoria(
            db=db, usuario_id=usuario.id, empresa_id=usuario.empresa_id,
            tabla="recuperacion_password", accion="PASSWORD_RECOVERY_BLOCKED",
            ip=ip_cliente, user_agent=user_agent,
            desc="Código bloqueado por superar límite de intentos.",
            registro_id=usuario.id
        )
        db.commit()
        raise HTTPException(status_code=403, detail="Código bloqueado. Solicita uno nuevo.")

    # Verificar el código enviado contra el hash de la BD
    if not pwd_context.verify(payload.code, registro_otp.codigo_hash):
        registro_otp.intentos_fallidos += 1
        registrar_auditoria(
            db=db, usuario_id=usuario.id, empresa_id=usuario.empresa_id,
            tabla="recuperacion_password", accion="PASSWORD_RECOVERY_FAILED",
            ip=ip_cliente, user_agent=user_agent,
            desc=f"Intento fallido #{registro_otp.intentos_fallidos}",
            registro_id=usuario.id
        )
        db.commit()
        raise HTTPException(status_code=400, detail="El código ingresado es incorrecto.")

    return {"status": "success", "mensaje": "Código verificado correctamente."}

# =========================================================================
# 3. ACTUALIZAR CONTRASEÑA
# =========================================================================
@router.post("/password-recovery/reset")
async def actualizar_password(payload: PasswordResetConfirm, request: Request, db: Session = Depends(get_db)):
    ip_cliente = request.client.host
    user_agent = request.headers.get("user-agent", "Desconocido")

    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")

    registro_otp = db.query(RecuperacionPassword).filter(
        RecuperacionPassword.usuario_id == usuario.id,
        RecuperacionPassword.usado == False
    ).order_by(RecuperacionPassword.created_at.desc()).first()

    # Verificación final de seguridad
    if not registro_otp or datetime.utcnow() > registro_otp.fecha_expiracion or registro_otp.intentos_fallidos >= 3:
        raise HTTPException(status_code=400, detail="La solicitud de cambio es inválida o ha expirado.")

    if not pwd_context.verify(payload.code, registro_otp.codigo_hash):
        raise HTTPException(status_code=400, detail="Validación de código fallida.")

    # 1. Actualizar el password_hash del usuario
    usuario.password_hash = pwd_context.hash(payload.new_password)
    usuario.updated_at = datetime.utcnow()

    # 2. Invalidar el código utilizado
    registro_otp.usado = True

    # 3. Registrar el éxito en Auditoría
    registrar_auditoria(
        db=db,
        usuario_id=usuario.id,
        empresa_id=usuario.empresa_id,
        tabla="usuario",
        accion="PASSWORD_CHANGED_SUCCESS",
        ip=ip_cliente,
        user_agent=user_agent,
        desc="Contraseña actualizada exitosamente",
        registro_id=usuario.id,           # <-- El ID del usuario afectado
        datos_anteriores=None,            # <-- NULL por seguridad
        datos_nuevos={"pwd": "privado"}   # <-- Opcional: un pequeño JSON indicando que es privado, o simplemente None.
    )
    db.commit()

    return {"status": "success", "mensaje": "Tu contraseña ha sido actualizada de forma segura."}
