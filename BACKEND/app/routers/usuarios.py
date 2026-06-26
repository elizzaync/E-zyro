"""
Router: /usuarios — Gestión de cuentas de usuario (Admin / permiso `usuarios:gestionar`).

Permite listar usuarios de la empresa, crear cuentas (con ficha de empleado
opcional), cambiar el rol, activar/desactivar y resetear la contraseña. Todo
acotado SIEMPRE a la empresa del token (multi-tenant: nunca cruza empresas).

Guardas de seguridad:
- Un admin no puede desactivar ni cambiarse el rol a sí mismo (evita auto-bloqueo).
- El rol asignado debe pertenecer a la misma empresa.
"""
from __future__ import annotations

import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from passlib.context import CryptContext
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..core.permisos import exigir_permiso
from ..core.security import verificar_token
from ..core.session_cache import invalidar_activo
from ..db.database import get_db
from ..models.usuario import Usuario
from ..services.fcm_service import enviar_push_a_usuario

router = APIRouter(prefix="/usuarios", tags=["usuarios"])
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def _avisar_cambio_acceso(db: Session, usuario_id: str) -> None:
    """Push 'perfil_actualizado' al usuario afectado para que su app refresque
    rol+permisos al instante (sin re-login). Best-effort: no rompe el endpoint."""
    try:
        enviar_push_a_usuario(
            usuario_id=str(usuario_id),
            titulo="Tus accesos cambiaron",
            mensaje="Tu rol o permisos en la app fueron actualizados.",
            db=db,
            tipo="perfil_actualizado",
            categoria="permisos",
        )
    except Exception:
        pass


# ── Schemas ───────────────────────────────────────────────────────────────
class UsuarioOut(BaseModel):
    id: str
    nombre: str
    apellido: str
    email: str
    username: str
    rol: Optional[str] = None
    rol_id: Optional[str] = None
    activo: bool
    tiene_ficha: bool


class RolOut(BaseModel):
    id: str
    nombre: str


class CrearUsuarioIn(BaseModel):
    nombre: str
    apellido: str
    email: str
    username: str
    password: str
    rol_id: str
    telefono: Optional[str] = None
    # Ficha de empleado opcional (necesaria para asistencia, vacaciones, etc.)
    crear_ficha: bool = False
    cargo: Optional[str] = None
    area: Optional[str] = None
    tipo: Optional[str] = "planilla"
    codigo: Optional[str] = None
    tipo_documento: Optional[str] = "DNI"
    numero_documento: Optional[str] = None
    sexo: Optional[str] = None
    fecha_ingreso: Optional[str] = None


class CambiarRolIn(BaseModel):
    rol_id: str


class CambiarActivoIn(BaseModel):
    activo: bool


class ResetPasswordIn(BaseModel):
    password: str


# ── Helpers ───────────────────────────────────────────────────────────────
def _guard(db: Session, payload: dict) -> None:
    exigir_permiso(db, payload, "usuarios", "gestionar")


_SELECT_USUARIO = """
    SELECT u.id::text AS id, u.nombre, u.apellido, u.email, u.username, u.activo,
           (SELECT string_agg(r.nombre, ', ')
              FROM usuario_rol ur JOIN rol r ON r.id = ur.rol_id
             WHERE ur.usuario_id = u.id) AS rol,
           (SELECT r.id::text
              FROM usuario_rol ur JOIN rol r ON r.id = ur.rol_id
             WHERE ur.usuario_id = u.id ORDER BY r.nombre LIMIT 1) AS rol_id,
           EXISTS(SELECT 1 FROM empleado e WHERE e.usuario_id = u.id) AS tiene_ficha
      FROM usuario u
     WHERE u.empresa_id::text = :emp
"""


def _row_to_out(r) -> UsuarioOut:
    return UsuarioOut(
        id=r["id"], nombre=r["nombre"] or "", apellido=r["apellido"] or "",
        email=r["email"] or "", username=r["username"] or "",
        rol=r["rol"], rol_id=r["rol_id"], activo=bool(r["activo"]),
        tiene_ficha=bool(r["tiene_ficha"]),
    )


def _get_one(db: Session, usuario_id: str, empresa_id: str) -> UsuarioOut:
    r = db.execute(text(_SELECT_USUARIO + " AND u.id::text = :id"),
                   {"emp": empresa_id, "id": usuario_id}).mappings().first()
    if not r:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return _row_to_out(r)


# ── Endpoints ─────────────────────────────────────────────────────────────
@router.get("/roles", response_model=List[RolOut])
def listar_roles(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _guard(db, payload)
    rows = db.execute(
        text("SELECT id::text AS id, nombre FROM rol WHERE empresa_id::text = :emp ORDER BY nombre"),
        {"emp": payload["empresa_id"]},
    ).mappings().all()
    return [RolOut(id=r["id"], nombre=r["nombre"]) for r in rows]


@router.get("", response_model=List[UsuarioOut])
def listar(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _guard(db, payload)
    rows = db.execute(
        text(_SELECT_USUARIO + " ORDER BY u.nombre, u.apellido"),
        {"emp": payload["empresa_id"]},
    ).mappings().all()
    return [_row_to_out(r) for r in rows]


@router.post("", response_model=UsuarioOut, status_code=201)
def crear(body: CrearUsuarioIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _guard(db, payload)
    empresa_id = payload["empresa_id"]

    if len(body.password or "") < 6:
        raise HTTPException(status_code=422, detail="La contraseña debe tener al menos 6 caracteres")

    # username único global (el login es por username); email único en la empresa.
    if db.execute(text("SELECT 1 FROM usuario WHERE lower(username) = lower(:u)"),
                  {"u": body.username}).first():
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese nombre de usuario")
    if db.execute(text("SELECT 1 FROM usuario WHERE lower(email) = lower(:e) AND empresa_id::text = :emp"),
                  {"e": body.email, "emp": empresa_id}).first():
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese correo en la empresa")

    rol = db.execute(text("SELECT nombre FROM rol WHERE id::text = :r AND empresa_id::text = :emp"),
                     {"r": body.rol_id, "emp": empresa_id}).mappings().first()
    if not rol:
        raise HTTPException(status_code=404, detail="Rol no encontrado en la empresa")

    uid = str(uuid.uuid4())
    db.execute(text("""
        INSERT INTO usuario (id, empresa_id, email, username, nombre, apellido,
                             password_hash, telefono, activo, email_verificado,
                             debe_cambiar_password, created_at)
        VALUES (:id, :emp, :e, :un, :n, :a, :pwd, :tel, true, false, true, now())
    """), {"id": uid, "emp": empresa_id, "e": body.email, "un": body.username,
           "n": body.nombre, "a": body.apellido, "pwd": pwd_context.hash(body.password),
           "tel": body.telefono})
    db.execute(text("""
        INSERT INTO usuario_rol (usuario_id, rol_id, empresa_id)
        VALUES (:u, :r, :emp)
    """), {"u": uid, "r": body.rol_id, "emp": empresa_id})

    if body.crear_ficha:
        from datetime import date
        fi = body.fecha_ingreso or str(date.today())
        eid = str(uuid.uuid4())
        db.execute(text("""
            INSERT INTO empleado (id, usuario_id, empresa_id, codigo, cargo, area,
                                  tipo, tipo_documento, numero_documento, sexo,
                                  fecha_ingreso, activo)
            VALUES (:eid, :u, :emp, :cod, :cargo, :area, :tipo,
                    :tdoc, :ndoc, :sexo, :fi, true)
        """), {"eid": eid, "u": uid, "emp": empresa_id, "cod": body.codigo,
               "cargo": (body.cargo or "Sin cargo"), "area": body.area,
               "tipo": (body.tipo or "planilla"), "tdoc": (body.tipo_documento or "DNI"),
               "ndoc": body.numero_documento, "sexo": body.sexo, "fi": fi})

    db.commit()
    return _get_one(db, uid, empresa_id)


@router.put("/{usuario_id}/rol", response_model=UsuarioOut)
def cambiar_rol(usuario_id: str, body: CambiarRolIn,
                payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _guard(db, payload)
    empresa_id = payload["empresa_id"]
    if usuario_id == str(payload.get("id")):
        raise HTTPException(status_code=400, detail="No puedes cambiar tu propio rol")
    if not db.execute(text("SELECT 1 FROM usuario WHERE id::text = :id AND empresa_id::text = :emp"),
                      {"id": usuario_id, "emp": empresa_id}).first():
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    if not db.execute(text("SELECT 1 FROM rol WHERE id::text = :r AND empresa_id::text = :emp"),
                      {"r": body.rol_id, "emp": empresa_id}).first():
        raise HTTPException(status_code=404, detail="Rol no encontrado en la empresa")

    db.execute(text("DELETE FROM usuario_rol WHERE usuario_id::text = :u"), {"u": usuario_id})
    db.execute(text("INSERT INTO usuario_rol (usuario_id, rol_id, empresa_id) VALUES (:u, :r, :emp)"),
               {"u": usuario_id, "r": body.rol_id, "emp": empresa_id})
    db.commit()
    _avisar_cambio_acceso(db, usuario_id)
    return _get_one(db, usuario_id, empresa_id)


@router.put("/{usuario_id}/activo", response_model=UsuarioOut)
def cambiar_activo(usuario_id: str, body: CambiarActivoIn,
                   payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _guard(db, payload)
    empresa_id = payload["empresa_id"]
    if usuario_id == str(payload.get("id")) and not body.activo:
        raise HTTPException(status_code=400, detail="No puedes desactivar tu propia cuenta")
    usuario = (
        db.query(Usuario)
        .filter(Usuario.id == usuario_id, Usuario.empresa_id == empresa_id)
        .first()
    )
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    usuario.activo = body.activo
    db.commit()
    if not body.activo:
        invalidar_activo(usuario_id)
    return _get_one(db, usuario_id, empresa_id)


@router.post("/{usuario_id}/reset-password")
def reset_password(usuario_id: str, body: ResetPasswordIn,
                   payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _guard(db, payload)
    empresa_id = payload["empresa_id"]
    if len(body.password or "") < 6:
        raise HTTPException(status_code=422, detail="La contraseña debe tener al menos 6 caracteres")
    res = db.execute(text("""
        UPDATE usuario
           SET password_hash = :p, debe_cambiar_password = true
         WHERE id::text = :id AND empresa_id::text = :emp
    """), {"p": pwd_context.hash(body.password), "id": usuario_id, "emp": empresa_id})
    if res.rowcount == 0:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    db.commit()
    return {"status": "success", "mensaje": "Contraseña restablecida"}
