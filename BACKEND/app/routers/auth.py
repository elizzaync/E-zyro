from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi import Security
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from datetime import datetime, timedelta
import uuid
import random
import json
import hashlib
from zoneinfo import ZoneInfo
# Importaciones de esquemas y modelos
from app.schemas.auth import (
    LoginData,
    PasswordResetRequest,
    PasswordVerifyCode,
    PasswordResetConfirm
)
from app.models.usuario import Usuario
from app.models.usuario_rol import UsuarioRol
from app.models.rol import Rol
from app.models.rol_permiso import RolPermiso
from app.models.permiso import Permiso
from app.models.auditoria import Auditoria
from app.models.recuperacion_password import RecuperacionPassword
from app.models.sesion_usuario import SesionUsuario
from app.db.database import get_db
from app.core.security import crear_token_acceso, verificar_token, ACCESS_TOKEN_EXPIRE_MINUTES, SECRET_KEY, ALGORITHM
from app.core.email import enviar_correo_otp
from jose import jwt, JWTError
router = APIRouter(prefix="/auth", tags=["Autenticacion"])
_http_bearer = HTTPBearer()
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
# LOGIN
# =========================================================================
@router.post("/login")
def login_usuario(credenciales: LoginData, request: Request, db: Session = Depends(get_db)):
    usuario_db = db.query(Usuario).filter(Usuario.username == credenciales.username).first()
    if not usuario_db or not pwd_context.verify(credenciales.password, usuario_db.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    rol_row = db.query(Rol).join(
        UsuarioRol, UsuarioRol.rol_id == Rol.id
    ).filter(UsuarioRol.usuario_id == usuario_db.id).first()
    nombre_rol_real = rol_row.nombre if rol_row else "Sin Rol Asignado"

    lista_permisos: list[str] = []
    if rol_row:
        permisos_rows = (
            db.query(Permiso.modulo, Permiso.accion)
            .join(RolPermiso, RolPermiso.permiso_id == Permiso.id)
            .filter(RolPermiso.rol_id == rol_row.id)
            .all()
        )
        lista_permisos = [f"{p.modulo}:{p.accion}" for p in permisos_rows]

    datos_para_token = {
        "sub": usuario_db.username,
        "id": str(usuario_db.id),
        "empresa_id": str(usuario_db.empresa_id),
        "rol": nombre_rol_real
    }
    token_real = crear_token_acceso(datos_para_token)

    # Registrar sesión en sesion_usuario
    try:
        ip_cliente  = request.client.host if request.client else None
        user_agent  = request.headers.get("user-agent", "")[:255]
        dispositivo = user_agent[:100]
        token_hash  = hashlib.sha256(token_real.encode()).hexdigest()
        fecha_exp   = datetime.now(ZONA_HORARIA) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)

        nueva_sesion = SesionUsuario(
            usuario_id       = str(usuario_db.id),
            token_hash       = token_hash,
            ip               = ip_cliente,
            user_agent       = user_agent,
            dispositivo      = dispositivo,
            activa           = True,
            fecha_expiracion = fecha_exp
        )
        db.add(nueva_sesion)
        db.commit()
    except Exception:
        db.rollback()  # No bloqueamos el login si falla el registro de sesión

    return {
        "status": "success",
        "mensaje": "Autenticación exitosa",
        "data": {
            "nombre_completo": f"{usuario_db.nombre} {usuario_db.apellido}",
            "rol": nombre_rol_real,
            "token": token_real,
            "foto_url": usuario_db.foto_url or "",
            "permisos": lista_permisos,
        }
    }


@router.post("/logout")
def logout_usuario(
    credentials: HTTPAuthorizationCredentials = Security(_http_bearer),
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
):
    try:
        token_hash = hashlib.sha256(credentials.credentials.encode()).hexdigest()
        usuario_id = current_user.get("id")

        sesion = db.query(SesionUsuario).filter(
            SesionUsuario.usuario_id == usuario_id,
            SesionUsuario.token_hash == token_hash,
            SesionUsuario.activa    == True
        ).first()

        if sesion:
            sesion.activa       = False
            sesion.fecha_cierre = datetime.now(ZONA_HORARIA)
            db.commit()

        return {"status": "success", "mensaje": "Sesión cerrada correctamente"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error al cerrar sesión")
# =========================================================================
# 1. SOLICITAR CÓDIGO
# =========================================================================
@router.post("/password-recovery/request")
async def solicitar_codigo(payload: PasswordResetRequest, request: Request, db: Session = Depends(get_db)):
    ip_cliente = request.client.host
    user_agent = request.headers.get("user-agent", "Desconocido")

    usuario = db.query(Usuario).filter(Usuario.email == payload.email).first()
    # Anti-enumeración: no revelar si el correo existe o no
    if not usuario:
        return {"status": "success", "mensaje": "Si el correo está registrado, recibirás un código de verificación."}
    # Generar código de 6 dígitos de forma segura
    codigo_plano = str(random.SystemRandom().randint(100000, 999999))
    # Guardar en BD (Encriptado)
    nuevo_registro = RecuperacionPassword(
        id=str(uuid.uuid4()),
        usuario_id=usuario.id,
        codigo_hash=pwd_context.hash(codigo_plano),
        ip_solicitud=ip_cliente,
        fecha_expiracion=datetime.utcnow() + timedelta(minutes=15)
    )
    db.add(nuevo_registro)
    # Registrar en Auditoría
    registrar_auditoria(
        db=db,
        usuario_id=usuario.id,
        empresa_id=usuario.empresa_id,
        tabla="recuperacion_password",
        accion="PASSWORD_RECOVERY_REQUEST",
        ip=ip_cliente,
        user_agent=user_agent,
        desc=f"Solicitud de código OTP para {payload.email}",
        registro_id=usuario.id
    )
    db.commit()
    # Envío de correo
    try:
        await enviar_correo_otp(payload.email, codigo_plano)
    except Exception:
        raise HTTPException(status_code=500, detail="Error al enviar el código. Intenta nuevamente.")
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
        raise HTTPException(status_code=400, detail="Código inválido o expirado.")
    # Buscar el último código activo pedido por este usuario
    registro_otp = db.query(RecuperacionPassword).filter(
        RecuperacionPassword.usuario_id == usuario.id,
        RecuperacionPassword.usado == False
    ).order_by(RecuperacionPassword.created_at.desc()).first()
    if not registro_otp:
        raise HTTPException(status_code=400, detail="No has solicitado un código de recuperación.")
    # Validaciones de Seguridad
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
        raise HTTPException(status_code=400, detail="La solicitud de cambio es inválida o ha expirado.")
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
        registro_id=usuario.id,
        datos_anteriores=None,
        datos_nuevos={"pwd": "privado"}
    )
    db.commit()

    return {"status": "success", "mensaje": "Tu contraseña ha sido actualizada de forma segura."}
# =========================================================================
# REFRESH TOKEN (para acceso biométrico sin re-login)
# =========================================================================
@router.post("/refresh")
def refresh_token(
    credentials: HTTPAuthorizationCredentials = Security(_http_bearer),
    db: Session = Depends(get_db),
):
    import time
    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            options={"verify_exp": False},
        )
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token inválido")

    exp = payload.get("exp", 0)
    if (time.time() - exp) > (30 * 24 * 3600):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesión expirada. Inicia sesión con tu contraseña para continuar.",
        )

    # Validar que la sesión siga activa en BD (evita reutilización de tokens revocados)
    token_hash  = hashlib.sha256(token.encode()).hexdigest()
    usuario_id  = payload.get("id")
    sesion = db.query(SesionUsuario).filter(
        SesionUsuario.usuario_id == usuario_id,
        SesionUsuario.token_hash == token_hash,
        SesionUsuario.activa     == True,
    ).first()
    if not sesion:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesión inválida o cerrada. Inicia sesión nuevamente.",
        )

    new_payload = {k: v for k, v in payload.items() if k != "exp"}
    new_token   = crear_token_acceso(new_payload)

    # Actualizar hash en BD con el nuevo token
    sesion.token_hash       = hashlib.sha256(new_token.encode()).hexdigest()
    sesion.fecha_expiracion = datetime.now(ZONA_HORARIA) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    db.commit()

    return {"status": "success", "data": {"token": new_token}}