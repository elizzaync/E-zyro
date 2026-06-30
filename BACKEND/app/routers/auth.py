from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi import Security
from sqlalchemy import text, case, func
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from pydantic import BaseModel
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
from app.models.portal_acceso import PortalAcceso
from app.models.empleado import Empleado
from app.db.database import get_db
from app.core.security import crear_token_acceso, verificar_token, ACCESS_TOKEN_EXPIRE_MINUTES, ACCESS_TOKEN_EXPIRE_MINUTES_MOVIL, SECRET_KEY, ALGORITHM
from app.core.email import enviar_correo_otp
from app.core.session_cache import marcar_activa, invalidar
from app.core.session_events import manager as session_manager
from app.services.cloudinary_service import subir_imagen_cloudinary, eliminar_imagen_cloudinary
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
        datos_anteriores=datos_anteriores if datos_anteriores else None,
        datos_nuevos=datos_nuevos if datos_nuevos else None,
        descripcion=desc,
        ip=ip,
        user_agent=user_agent,
        fecha=datetime.now(ZONA_HORARIA)
    )
    db.add(nueva_auditoria)


# =========================================================================
# HELPERS: IP real + descripción legible del dispositivo (sin dependencias)
# =========================================================================
def _ip_real(request: Request) -> str | None:
    """IP real del cliente. Detrás del proxy de Railway, `request.client` es el
    proxy; el primer salto de `X-Forwarded-For` es el cliente original."""
    fwd = request.headers.get("X-Forwarded-For", "")
    if fwd:
        return fwd.split(",")[0].strip()[:45]
    return (request.client.host[:45] if request.client else None)


def _describir_dispositivo(user_agent: str) -> str:
    """Convierte el User-Agent crudo en algo legible: "📱 Celular Android · Chrome"
    / "💻 Computadora Windows · Edge". Parseo de strings, sin librerías externas."""
    ua = (user_agent or "").lower()

    es_movil = any(k in ua for k in ("mobile", "android", "iphone", "ipad", "ipod"))

    if "android" in ua:
        so = "Android"
    elif any(k in ua for k in ("iphone", "ipad", "ipod")):
        so = "iOS"
    elif "windows" in ua:
        so = "Windows"
    elif "mac os" in ua or "macintosh" in ua:
        so = "macOS"
    elif "linux" in ua:
        so = "Linux"
    else:
        so = "Desconocido"

    # Orden importa: Edge/Opera/Chrome comparten tokens "safari"/"chrome".
    if "edg" in ua:
        nav = "Edge"
    elif "opr" in ua or "opera" in ua:
        nav = "Opera"
    elif "crios" in ua:
        nav = "Chrome"
    elif "fxios" in ua or "firefox" in ua:
        nav = "Firefox"
    elif "chrome" in ua and "chromium" not in ua:
        nav = "Chrome"
    elif "safari" in ua:
        nav = "Safari"
    else:
        nav = "Navegador"

    icono = "📱" if es_movil else "💻"
    tipo = "Celular" if es_movil else "Computadora"
    return f"{icono} {tipo} {so} · {nav}"[:100]


# =========================================================================
# HELPER: rol + permisos efectivos de un usuario
# =========================================================================
def _rol_y_permisos(db: Session, usuario_id: str) -> tuple[str, list[str]]:
    """Devuelve (nombre_rol, [\"modulo:accion\", ...]) del usuario.

    Combina permisos vía rol (rol_permiso) y permisos directos (usuario_permiso).
    Fuente única usada por /login y /auth/me para que la app siempre reciba lo
    mismo y pueda autosanar su sesión.
    """
    # Si el usuario tiene varios roles, preferimos un rol administrativo para el
    # claim `rol` del token, de modo que el bypass es_admin/es_superadmin (que
    # mira el string del token) funcione en todo el backend. Los permisos finos
    # se combinan aparte vía rol_permiso + usuario_permiso (ver abajo).
    rol_row = (
        db.query(Rol)
        .join(UsuarioRol, UsuarioRol.rol_id == Rol.id)
        .filter(UsuarioRol.usuario_id == usuario_id)
        .order_by(
            case(
                (
                    func.replace(func.lower(Rol.nombre), " ", "").in_(
                        ("superadmin", "admin", "administrador")
                    ),
                    0,
                ),
                else_=1,
            ),
            Rol.created_at.asc(),
        )
        .first()
    )
    nombre_rol = rol_row.nombre if rol_row else "Sin Rol Asignado"

    rows = db.execute(
        text(
            """
            SELECT p.modulo, p.accion FROM permiso p
              JOIN rol_permiso rp ON rp.permiso_id = p.id
              JOIN usuario_rol  ur ON ur.rol_id    = rp.rol_id
             WHERE ur.usuario_id = :uid
            UNION
            SELECT p.modulo, p.accion FROM permiso p
              JOIN usuario_permiso up ON up.permiso_id = p.id
             WHERE up.usuario_id = :uid
            """
        ),
        {"uid": str(usuario_id)},
    ).all()
    permisos = [f"{m}:{a}" for (m, a) in rows]
    return nombre_rol, permisos


def _cargo_de_usuario(db: Session, usuario_id: str) -> str:
    """Cargo (puesto laboral) de la ficha de empleado del usuario, si tiene una.
    Distinto del rol RBAC: el rol maneja permisos, el cargo es informativo
    (mismo campo que ya muestra la web en Personal)."""
    empleado = db.query(Empleado.cargo).filter(Empleado.usuario_id == usuario_id).first()
    return empleado.cargo if empleado and empleado.cargo else ""


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
    nombre_rol_real, lista_permisos = _rol_y_permisos(db, usuario_db.id)
    cargo_real = _cargo_de_usuario(db, usuario_db.id)

    # Plataforma: la app móvil manda plataforma='movil' → token largo (7d) para
    # operar offline y recibir push; la web (no la manda) → token corto (4h).
    es_movil = (credenciales.plataforma or "").lower() in {"movil", "móvil", "mobile", "android", "ios"}
    token_minutos = ACCESS_TOKEN_EXPIRE_MINUTES_MOVIL if es_movil else ACCESS_TOKEN_EXPIRE_MINUTES

    datos_para_token = {
        "sub": usuario_db.username,
        "id": str(usuario_db.id),
        "empresa_id": str(usuario_db.empresa_id),
        "rol": nombre_rol_real,
        # Bypass híbrido: el permiso meta 'sistema:admin_total' (vía rol o directo)
        # se embebe como claim para que es_admin/es_superadmin lo resuelvan sin BD.
        "admin_total": "sistema:admin_total" in lista_permisos,
        "plataforma": "movil" if es_movil else "web",
    }
    # Para usuarios del portal cliente, embebbe el cliente_id en el token
    if (nombre_rol_real or "").lower().replace(" ", "") == "clienteexterno":
        acc = db.query(PortalAcceso).filter(
            PortalAcceso.usuario_id == str(usuario_db.id)
        ).first()
        if acc:
            datos_para_token["cliente_id"] = str(acc.cliente_id)
            datos_para_token["tipo_usuario"] = "cliente"

    token_real = crear_token_acceso(datos_para_token, expires_minutes=token_minutos)

    # Registrar / actualizar sesión en sesion_usuario
    token_hash       = hashlib.sha256(token_real.encode()).hexdigest()
    es_nuevo_equipo  = False
    info_dispositivo = None
    sesion_id_actual = None
    try:
        ip_cliente  = _ip_real(request)
        user_agent  = request.headers.get("user-agent", "")[:255]
        dispositivo = _describir_dispositivo(user_agent)
        fecha_exp   = datetime.now(ZONA_HORARIA) + timedelta(minutes=token_minutos)
        device_id   = (credenciales.device_id or "")[:100] or None

        # Limpiar sesiones cerradas con más de 30 días (mantenimiento silencioso)
        cutoff = datetime.now(ZONA_HORARIA) - timedelta(days=30)
        db.query(SesionUsuario).filter(
            SesionUsuario.usuario_id  == str(usuario_db.id),
            SesionUsuario.activa      == False,
            SesionUsuario.fecha_cierre < cutoff,
        ).delete(synchronize_session=False)

        sesion_existente = None
        if device_id:
            # Buscar sesión previa del mismo dispositivo (activa o cerrada)
            sesion_existente = db.query(SesionUsuario).filter(
                SesionUsuario.usuario_id == str(usuario_db.id),
                SesionUsuario.device_id  == device_id,
            ).first()

        if sesion_existente:
            # Mismo equipo (mismo device_id): reutiliza el registro, NO es un
            # "nuevo dispositivo" → no se avisa a los demás.
            sesion_existente.token_hash       = token_hash
            sesion_existente.activa           = True
            sesion_existente.fecha_expiracion = fecha_exp
            sesion_existente.fecha_cierre     = None
            sesion_existente.ip               = ip_cliente
            sesion_existente.user_agent       = user_agent
            sesion_existente.dispositivo      = dispositivo
            sesion_id_actual = str(sesion_existente.id)
        else:
            # Equipo nuevo (otro device_id o sin device_id) → se avisará a las
            # sesiones ya abiertas del usuario.
            es_nuevo_equipo  = True
            sesion_id_actual = str(uuid.uuid4())
            db.add(SesionUsuario(
                id               = sesion_id_actual,
                usuario_id       = str(usuario_db.id),
                token_hash       = token_hash,
                device_id        = device_id,
                ip               = ip_cliente,
                user_agent       = user_agent,
                dispositivo      = dispositivo,
                activa           = True,
                fecha_expiracion = fecha_exp,
            ))

        db.commit()
        # Pre-cachea el token como válido para que el primer request protegido
        # no pague una consulta a BD (verificar_token).
        marcar_activa(token_hash)
        info_dispositivo = {
            "dispositivo": dispositivo,
            "ip":          ip_cliente or "—",
            "sesion_id":   sesion_id_actual,
            "fecha":       datetime.now(ZONA_HORARIA).isoformat(),
        }
    except Exception:
        db.rollback()  # No bloqueamos el login si falla el registro de sesión

    # Aviso en tiempo real al panel de Soporte TIC: nueva sesión iniciada.
    if info_dispositivo:
        try:
            from ..routers.soporte_ws import soporte_manager
            soporte_manager.emit(str(usuario_db.empresa_id), {
                "tipo": "sesion_nueva",
                "usuario": f"{usuario_db.nombre} {usuario_db.apellido}".strip(),
                "dispositivo": dispositivo,
                "ip": ip_cliente or "—",
            })
        except Exception:
            pass

    # Aviso en tiempo real a los equipos ya conectados: "alguien entró a tu cuenta".
    if es_nuevo_equipo and info_dispositivo:
        try:
            session_manager.notificar_nuevo_dispositivo(
                str(usuario_db.id), info_dispositivo, excluir_token_hash=token_hash
            )
        except Exception:
            pass

    return {
        "status": "success",
        "mensaje": "Autenticación exitosa",
        "data": {
            "id":              str(usuario_db.id),
            "nombre_completo": f"{usuario_db.nombre} {usuario_db.apellido}",
            "rol":             nombre_rol_real,
            "cargo":           cargo_real,
            "token":           token_real,
            "foto_url":        usuario_db.foto_url or "",
            "permisos":        lista_permisos,
        }
    }


# =========================================================================
# /auth/me — rol y permisos actuales (para autosanar la sesión en la app)
# =========================================================================
@router.get("/me")
def obtener_mi_sesion(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    usuario_id = payload.get("id")
    usuario_db = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if not usuario_db:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    nombre_rol_real, lista_permisos = _rol_y_permisos(db, usuario_id)
    cargo_real = _cargo_de_usuario(db, usuario_id)
    return {
        "status": "success",
        "data": {
            "id":              str(usuario_db.id),
            "nombre_completo": f"{usuario_db.nombre} {usuario_db.apellido}",
            "rol":             nombre_rol_real,
            "cargo":           cargo_real,
            "foto_url":        usuario_db.foto_url or "",
            "permisos":        lista_permisos,
        }
    }


# =========================================================================
# /auth/me/foto — subir / quitar foto de perfil del usuario autenticado
# =========================================================================
class _FotoPerfilIn(BaseModel):
    imagen_base64: str


@router.post("/me/foto")
def subir_mi_foto(body: _FotoPerfilIn, payload: dict = Depends(verificar_token),
                  db: Session = Depends(get_db)):
    """Sube la foto de perfil del usuario autenticado a Cloudinary y persiste
    `usuario.foto_url`. Usa public_id = id del usuario → sobrescribe la anterior
    (sin huérfanos) y mantiene una URL estable por usuario."""
    if not body.imagen_base64:
        raise HTTPException(status_code=400, detail="imagen_base64 requerida")
    usuario_id = payload.get("id")
    empresa_id = payload.get("empresa_id")
    usuario_db = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if not usuario_db:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    folder = f"e-zyro/perfiles/{empresa_id}"
    try:
        url = subir_imagen_cloudinary(
            body.imagen_base64, folder=folder,
            public_id=str(usuario_id), is_perfil=True,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    usuario_db.foto_url = url
    db.commit()
    return {"status": "success", "data": {"foto_url": url or ""}}


@router.delete("/me/foto")
def quitar_mi_foto(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """Quita la foto de perfil (borra el asset en Cloudinary y limpia foto_url)."""
    usuario_id = payload.get("id")
    usuario_db = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if not usuario_db:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    if usuario_db.foto_url:
        eliminar_imagen_cloudinary(usuario_db.foto_url)
    usuario_db.foto_url = None
    db.commit()
    return {"status": "success", "data": {"foto_url": ""}}


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

        # Revoca el token al instante (no esperar al TTL de la caché): el JWT
        # deja de ser aceptado por verificar_token aunque no haya expirado.
        invalidar(token_hash)
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

    # Ventana de refresh según plataforma del token: móvil 30 días, web 24h.
    es_movil = (payload.get("plataforma") or "").lower() == "movil"
    ventana_refresh = (30 * 24 * 3600) if es_movil else (24 * 3600)
    token_minutos   = ACCESS_TOKEN_EXPIRE_MINUTES_MOVIL if es_movil else ACCESS_TOKEN_EXPIRE_MINUTES

    exp = payload.get("exp", 0)
    if (time.time() - exp) > ventana_refresh:
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
    # Re-derivar rol + bypass híbrido desde la BD para que un cambio de
    # privilegios (p. ej. otorgar/revocar 'sistema:admin_total' o cambio de rol)
    # se refleje al refrescar el token, SIN obligar a re-login con contraseña.
    try:
        _rol_actual, _permisos_actuales = _rol_y_permisos(db, usuario_id)
        new_payload["rol"]         = _rol_actual
        new_payload["admin_total"] = "sistema:admin_total" in _permisos_actuales
    except Exception:
        pass
    new_token   = crear_token_acceso(new_payload, expires_minutes=token_minutos)

    # Actualizar hash en BD con el nuevo token
    nuevo_hash = hashlib.sha256(new_token.encode()).hexdigest()
    sesion.token_hash       = nuevo_hash
    sesion.fecha_expiracion = datetime.now(ZONA_HORARIA) + timedelta(minutes=token_minutos)
    db.commit()

    # Rotación de token: el viejo hash queda revocado, el nuevo pre-cacheado.
    invalidar(token_hash)
    marcar_activa(nuevo_hash)

    return {"status": "success", "data": {"token": new_token}}

# =========================================================================
# SESIONES ACTIVAS (detección multi-dispositivo)
# =========================================================================
@router.get("/sesiones")
def listar_sesiones_activas(
    credentials: HTTPAuthorizationCredentials = Security(_http_bearer),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Lista las sesiones activas del usuario actual (excluye la sesión actual)."""
    usuario_id = payload.get("id")
    token_hash_actual = hashlib.sha256(credentials.credentials.encode()).hexdigest()

    sesiones = db.query(SesionUsuario).filter(
        SesionUsuario.usuario_id == usuario_id,
        SesionUsuario.activa == True,
    ).order_by(SesionUsuario.created_at.desc()).all()

    resultado = []
    for s in sesiones:
        resultado.append({
            "id": str(s.id),
            "dispositivo": s.dispositivo or "Dispositivo desconocido",
            "ip": s.ip or "—",
            "device_id": s.device_id,
            "created_at": s.created_at.isoformat() if s.created_at else None,
            "fecha_expiracion": s.fecha_expiracion.isoformat() if s.fecha_expiracion else None,
            "es_actual": s.token_hash == token_hash_actual,
        })

    return {"status": "success", "data": resultado}


@router.delete("/sesiones/{sesion_id}")
def cerrar_sesion_remota(
    sesion_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Cierra (revoca) una sesión activa del usuario actual por su ID."""
    usuario_id = payload.get("id")
    sesion = db.query(SesionUsuario).filter(
        SesionUsuario.id == sesion_id,
        SesionUsuario.usuario_id == usuario_id,
        SesionUsuario.activa == True,
    ).first()
    if not sesion:
        raise HTTPException(status_code=404, detail="Sesión no encontrada o ya cerrada.")
    token_hash_cerrado = sesion.token_hash
    sesion.activa = False
    sesion.fecha_cierre = datetime.now(ZONA_HORARIA)
    db.commit()

    # Expulsión real + inmediata del equipo cerrado:
    #  1) invalida el token en la caché → verificar_token lo rechaza ya.
    #  2) empuja "sesion_cerrada" por WS → el equipo hace logout al instante.
    invalidar(token_hash_cerrado)
    try:
        session_manager.notificar_sesion_cerrada(usuario_id, token_hash_cerrado)
    except Exception:
        pass
    return {"status": "success", "mensaje": "Sesión cerrada correctamente."}


@router.post("/logout-all")
def cerrar_todas_las_sesiones(
    credentials: HTTPAuthorizationCredentials = Security(_http_bearer),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Cierra TODAS las demás sesiones activas del usuario (mantiene la actual).

    Útil ante un acceso sospechoso: revoca todos los demás equipos al instante.
    """
    usuario_id = payload.get("id")
    token_hash_actual = hashlib.sha256(credentials.credentials.encode()).hexdigest()

    otras = db.query(SesionUsuario).filter(
        SesionUsuario.usuario_id == usuario_id,
        SesionUsuario.activa     == True,
        SesionUsuario.token_hash != token_hash_actual,
    ).all()

    hashes_cerrados = [s.token_hash for s in otras]
    ahora = datetime.now(ZONA_HORARIA)
    for s in otras:
        s.activa = False
        s.fecha_cierre = ahora
    db.commit()

    for th in hashes_cerrados:
        invalidar(th)
        try:
            session_manager.notificar_sesion_cerrada(usuario_id, th)
        except Exception:
            pass

    return {
        "status": "success",
        "mensaje": f"Se cerraron {len(hashes_cerrados)} sesión(es) en otros dispositivos.",
        "data": {"cerradas": len(hashes_cerrados)},
    }
