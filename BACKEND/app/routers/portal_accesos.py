"""
Gestión de accesos al Portal Cliente — SOLO Admin/SuperAdmin.

Crea/lista/restablece/revoca el usuario portal (rol ClienteExterno) de un
cliente. Espejo administrado de lo que talma_seed.py hace para TALMA:
usuario dentro de la empresa operadora + rol ClienteExterno + portal_acceso.
La contraseña temporal se autogenera y se devuelve UNA sola vez.
"""
from __future__ import annotations

import re
import secrets
import unicodedata
import uuid
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Request
from passlib.context import CryptContext
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.permisos import exigir_solo_admin
from app.core.security import verificar_token
from app.db.database import get_db
from app.models.auditoria import Auditoria

router = APIRouter(prefix="/portal-accesos", tags=["Portal Accesos"])

_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")
_ZONA = ZoneInfo("America/Lima")

_ROL_NOMBRE = "ClienteExterno"
# Sin caracteres ambiguos (0/O, 1/l/I) para dictado telefónico.
_ALFABETO_PWD = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _admin_ctx(payload: dict) -> str:
    """Exige Admin/SuperAdmin y devuelve su empresa_id."""
    exigir_solo_admin(payload, "Solo administradores gestionan accesos del portal.")
    return str(payload["empresa_id"])


def _password_temporal() -> str:
    return "".join(secrets.choice(_ALFABETO_PWD) for _ in range(12))


def _slug(texto: str) -> str:
    s = unicodedata.normalize("NFKD", texto or "").encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")
    return s[:24] or "cliente"


def _username_libre(db: Session, base: str) -> str:
    """Devuelve `portal_<slug>` único a nivel global de la tabla usuario."""
    candidato = f"portal_{base}"
    n = 1
    while db.execute(
        text("SELECT 1 FROM usuario WHERE username = :u LIMIT 1"),
        {"u": candidato},
    ).fetchone():
        n += 1
        candidato = f"portal_{base}_{n}"
    return candidato


def _cliente_de_empresa(db: Session, empresa_id: str, cliente_id: str):
    row = db.execute(text("""
        SELECT id::text, razon_social FROM cliente
        WHERE id::text = :cid AND empresa_id::text = :eid
    """), {"cid": str(cliente_id), "eid": empresa_id}).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Cliente no encontrado en tu empresa.")
    return row


def _acceso_de_cliente(db: Session, empresa_id: str, cliente_id: str):
    """Usuario portal vigente de un cliente (si existe)."""
    return db.execute(text("""
        SELECT u.id::text, u.username, u.activo
        FROM portal_acceso pa
        JOIN usuario u ON u.id = pa.usuario_id
        WHERE pa.cliente_id::text = :cid AND u.empresa_id::text = :eid
        ORDER BY pa.created_at DESC
        LIMIT 1
    """), {"cid": str(cliente_id), "eid": empresa_id}).fetchone()


def _rol_cliente_externo(db: Session, empresa_id: str) -> str:
    """Devuelve (creando si falta) el id del rol ClienteExterno de la empresa."""
    row = db.execute(text("""
        SELECT id::text FROM rol
        WHERE empresa_id::text = :eid
          AND lower(replace(nombre,' ','')) = 'clienteexterno'
        LIMIT 1
    """), {"eid": empresa_id}).fetchone()
    if row:
        return row[0]
    rol_id = str(uuid.uuid4())
    db.execute(text("""
        INSERT INTO rol (id, empresa_id, nombre, descripcion, es_rol_sistema, created_at)
        VALUES (:id, :eid, :nombre, 'Portal de seguimiento para clientes externos', true, now())
    """), {"id": rol_id, "eid": empresa_id, "nombre": _ROL_NOMBRE})
    return rol_id


def _auditar(db: Session, payload: dict, request: Request, accion: str,
             registro_id: str, desc: str) -> None:
    db.add(Auditoria(
        id=str(uuid.uuid4()),
        empresa_id=str(payload["empresa_id"]),
        usuario_id=str(payload["id"]),
        tabla_afectada="portal_acceso",
        registro_id=registro_id,
        accion=accion,
        modulo="portal",
        descripcion=desc,
        ip=request.client.host if request.client else None,
        user_agent=(request.headers.get("user-agent", "") or "")[:255],
        fecha=datetime.now(_ZONA),
    ))


# ── 1. Listado: todos los clientes con su estado de acceso ───────────────────

@router.get("")
def listar_accesos(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
) -> list[dict[str, Any]]:
    empresa_id = _admin_ctx(payload)
    rows = db.execute(text("""
        SELECT
            c.id::text          AS cliente_id,
            c.razon_social,
            c.ruc,
            u.id::text          AS usuario_id,
            u.username,
            u.activo            AS usuario_activo,
            pa.created_at
        FROM cliente c
        LEFT JOIN portal_acceso pa ON pa.cliente_id::text = c.id::text
        LEFT JOIN usuario u
               ON u.id = pa.usuario_id AND u.empresa_id::text = :eid
        WHERE c.empresa_id::text = :eid AND c.activo = true
        ORDER BY c.razon_social
    """), {"eid": empresa_id}).fetchall()

    return [
        {
            "cliente_id":     r[0],
            "razon_social":   r[1],
            "ruc":            r[2],
            "tiene_acceso":   r[3] is not None,
            "usuario_id":     r[3],
            "username":       r[4],
            "usuario_activo": bool(r[5]) if r[5] is not None else None,
            "creado_en":      r[6].isoformat() if r[6] else None,
        }
        for r in rows
    ]


# ── 2. Crear acceso ───────────────────────────────────────────────────────────

class CrearAccesoBody(BaseModel):
    cliente_id: str


@router.post("", status_code=201)
def crear_acceso(
    body: CrearAccesoBody,
    request: Request,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    empresa_id = _admin_ctx(payload)
    cliente = _cliente_de_empresa(db, empresa_id, body.cliente_id)

    existente = _acceso_de_cliente(db, empresa_id, body.cliente_id)
    if existente:
        raise HTTPException(
            status_code=409,
            detail=f"El cliente ya tiene acceso al portal (usuario: {existente[1]}). "
                   "Usa restablecer contraseña o revoca el acceso primero.",
        )

    rol_id = _rol_cliente_externo(db, empresa_id)
    username = _username_libre(db, _slug(cliente[1]))
    password = _password_temporal()
    usuario_id = str(uuid.uuid4())
    # Email sintético único por username (la tabla exige unicidad por empresa).
    email = f"{username}@portal.e-zyro"

    db.execute(text("""
        INSERT INTO usuario
            (id, empresa_id, nombre, apellido, username, email,
             password_hash, activo, email_verificado, created_at)
        VALUES
            (:id, :eid, 'Portal', :apellido, :uname, :email,
             :pwd, true, true, now())
    """), {
        "id": usuario_id, "eid": empresa_id,
        "apellido": (cliente[1] or "Cliente")[:80],
        "uname": username, "email": email,
        "pwd": _pwd.hash(password),
    })
    db.execute(text("""
        INSERT INTO usuario_rol (id, usuario_id, rol_id, empresa_id, created_at)
        VALUES (:id, :uid, :rid, :eid, now())
    """), {"id": str(uuid.uuid4()), "uid": usuario_id, "rid": rol_id, "eid": empresa_id})
    db.execute(text("""
        INSERT INTO portal_acceso (usuario_id, cliente_id, created_at)
        VALUES (:uid, :cid, now())
    """), {"uid": usuario_id, "cid": cliente[0]})

    _auditar(db, payload, request, "crear", usuario_id,
             f"Acceso portal creado para cliente '{cliente[1]}' (usuario {username})")
    db.commit()

    # La contraseña viaja UNA sola vez; no queda en logs ni en auditoría.
    return {
        "cliente_id":        cliente[0],
        "usuario_id":        usuario_id,
        "username":          username,
        "password_temporal": password,
    }


# ── 3. Restablecer contraseña (y reactivar si estaba revocado) ───────────────

@router.post("/{cliente_id}/reset-password")
def reset_password(
    cliente_id: str,
    request: Request,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    empresa_id = _admin_ctx(payload)
    _cliente_de_empresa(db, empresa_id, cliente_id)
    acceso = _acceso_de_cliente(db, empresa_id, cliente_id)
    if not acceso:
        raise HTTPException(status_code=404, detail="El cliente no tiene acceso al portal.")

    password = _password_temporal()
    db.execute(text("""
        UPDATE usuario SET password_hash = :pwd, activo = true
        WHERE id::text = :uid
    """), {"pwd": _pwd.hash(password), "uid": acceso[0]})

    _auditar(db, payload, request, "reset_password", acceso[0],
             f"Contraseña del portal restablecida (usuario {acceso[1]})")
    db.commit()

    return {"username": acceso[1], "password_temporal": password}


# ── 4. Revocar acceso ─────────────────────────────────────────────────────────

@router.delete("/{cliente_id}")
def revocar_acceso(
    cliente_id: str,
    request: Request,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    empresa_id = _admin_ctx(payload)
    _cliente_de_empresa(db, empresa_id, cliente_id)
    acceso = _acceso_de_cliente(db, empresa_id, cliente_id)
    if not acceso:
        raise HTTPException(status_code=404, detail="El cliente no tiene acceso al portal.")

    # Desactiva (no borra: conserva auditoría e historial) y cierra sesiones.
    # _requires_client del portal exige usuario.activo, así que el bloqueo es
    # inmediato aunque su JWT siga vigente.
    db.execute(text("UPDATE usuario SET activo = false WHERE id::text = :uid"),
               {"uid": acceso[0]})
    db.execute(text("""
        UPDATE sesion_usuario SET activa = false, fecha_cierre = now()
        WHERE usuario_id::text = :uid AND activa = true
    """), {"uid": acceso[0]})

    _auditar(db, payload, request, "revocar", acceso[0],
             f"Acceso portal revocado (usuario {acceso[1]})")
    db.commit()

    return {"ok": True, "username": acceso[1]}
