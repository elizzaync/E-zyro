"""
Router: /privilegios — Gestión de permisos directos por usuario.

Permite a usuarios con `privilegios:gestionar` ver el catálogo de permisos,
consultar qué permisos directos tiene un usuario (sobre los de su rol),
otorgar y revocar permisos directos. Acotado siempre a la empresa del token.
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..core.permisos import exigir_permiso
from ..core.security import verificar_token
from ..db.database import get_db

router = APIRouter(prefix="/privilegios", tags=["privilegios"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class PermisoOut(BaseModel):
    id: str
    modulo: str
    accion: str
    descripcion: Optional[str]
    via_rol: bool        # True = lo tiene por su rol; False = solo directo
    directo: bool        # True = tiene asignación directa en usuario_permiso


class UsuarioResumenOut(BaseModel):
    id: str
    nombre: str
    apellido: str
    username: str
    rol: Optional[str]
    activo: bool
    permisos_directos: int   # cantidad de privilegios extras asignados


class OtorgarIn(BaseModel):
    permiso_id: str


class RevocarIn(BaseModel):
    permiso_id: str


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/usuarios")
def listar_usuarios(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Lista todos los usuarios activos de la empresa con sus permisos directos."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id = payload["empresa_id"]

    rows = db.execute(
        text(
            """
            SELECT
                u.id,
                u.nombre,
                u.apellido,
                u.username,
                r.nombre AS rol,
                u.activo,
                COUNT(up.permiso_id) AS permisos_directos
            FROM usuario u
            LEFT JOIN usuario_rol  ur ON ur.usuario_id = u.id
            LEFT JOIN rol          r  ON r.id = ur.rol_id
            LEFT JOIN usuario_permiso up ON up.usuario_id = u.id
            WHERE u.empresa_id = :emp
            GROUP BY u.id, u.nombre, u.apellido, u.username, r.nombre, u.activo
            ORDER BY u.nombre, u.apellido
            """
        ),
        {"emp": empresa_id},
    ).fetchall()

    return [
        {
            "id": str(r.id),
            "nombre": r.nombre,
            "apellido": r.apellido,
            "username": r.username,
            "rol": r.rol,
            "activo": r.activo,
            "permisos_directos": r.permisos_directos,
        }
        for r in rows
    ]


@router.get("/usuarios/{usuario_id}/permisos")
def permisos_usuario(
    usuario_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Devuelve TODO el catálogo de permisos indicando cuáles tiene el usuario
    (vía rol y/o directamente). Útil para renderizar el panel de checkboxes."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id = payload["empresa_id"]

    # Verificar que el usuario pertenece a la empresa
    row = db.execute(
        text("SELECT id FROM usuario WHERE id = :uid AND empresa_id = :emp"),
        {"uid": usuario_id, "emp": empresa_id},
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    rows = db.execute(
        text(
            """
            SELECT
                p.id,
                p.modulo,
                p.accion,
                p.descripcion,
                EXISTS (
                    SELECT 1 FROM rol_permiso rp
                      JOIN usuario_rol ur ON ur.rol_id = rp.rol_id
                     WHERE ur.usuario_id = :uid AND rp.permiso_id = p.id
                ) AS via_rol,
                EXISTS (
                    SELECT 1 FROM usuario_permiso up
                     WHERE up.usuario_id = :uid AND up.permiso_id = p.id
                ) AS directo
            FROM permiso p
            ORDER BY p.modulo, p.accion
            """
        ),
        {"uid": usuario_id},
    ).fetchall()

    return [
        {
            "id": str(r.id),
            "modulo": r.modulo,
            "accion": r.accion,
            "descripcion": r.descripcion,
            "via_rol": bool(r.via_rol),
            "directo": bool(r.directo),
        }
        for r in rows
    ]


@router.post("/usuarios/{usuario_id}/permisos")
def otorgar_permiso(
    usuario_id: str,
    body: OtorgarIn,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Asigna un permiso directo a un usuario (idempotente)."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id  = payload["empresa_id"]
    otorgado_por = payload["id"]

    # Usuario en la empresa
    row = db.execute(
        text("SELECT id FROM usuario WHERE id = :uid AND empresa_id = :emp"),
        {"uid": usuario_id, "emp": empresa_id},
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    # Permiso existe
    p = db.execute(
        text("SELECT id FROM permiso WHERE id = :pid"),
        {"pid": body.permiso_id},
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Permiso no encontrado")

    db.execute(
        text(
            """
            INSERT INTO usuario_permiso (usuario_id, permiso_id, asignado_por)
            VALUES (:uid, :pid, :por)
            ON CONFLICT (usuario_id, permiso_id) DO NOTHING
            """
        ),
        {"uid": usuario_id, "pid": body.permiso_id, "por": otorgado_por},
    )
    db.commit()
    return {"ok": True}


@router.delete("/usuarios/{usuario_id}/permisos/{permiso_id}")
def revocar_permiso(
    usuario_id: str,
    permiso_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Revoca un permiso directo de un usuario."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id = payload["empresa_id"]

    # Usuario en la empresa
    row = db.execute(
        text("SELECT id FROM usuario WHERE id = :uid AND empresa_id = :emp"),
        {"uid": usuario_id, "emp": empresa_id},
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    db.execute(
        text(
            "DELETE FROM usuario_permiso WHERE usuario_id = :uid AND permiso_id = :pid"
        ),
        {"uid": usuario_id, "pid": permiso_id},
    )
    db.commit()
    return {"ok": True}


@router.post("/usuarios/{usuario_id}/permisos/todos")
def otorgar_todos_permisos(
    usuario_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Asigna directamente TODOS los permisos del catálogo al usuario (bulk)."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id   = payload["empresa_id"]
    otorgado_por = payload["id"]

    row = db.execute(
        text("SELECT id FROM usuario WHERE id = :uid AND empresa_id = :emp"),
        {"uid": usuario_id, "emp": empresa_id},
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    db.execute(
        text(
            """
            INSERT INTO usuario_permiso (usuario_id, permiso_id, asignado_por)
            SELECT :uid, p.id, :por FROM permiso p
            ON CONFLICT (usuario_id, permiso_id) DO NOTHING
            """
        ),
        {"uid": usuario_id, "por": otorgado_por},
    )
    db.commit()
    total = db.execute(
        text("SELECT COUNT(*) FROM usuario_permiso WHERE usuario_id = :uid"),
        {"uid": usuario_id},
    ).scalar()
    return {"ok": True, "permisos_directos": total}


@router.delete("/usuarios/{usuario_id}/permisos")
def revocar_todos_permisos(
    usuario_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Elimina todos los permisos directos del usuario (deja solo los del rol)."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id = payload["empresa_id"]

    row = db.execute(
        text("SELECT id FROM usuario WHERE id = :uid AND empresa_id = :emp"),
        {"uid": usuario_id, "emp": empresa_id},
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    db.execute(
        text("DELETE FROM usuario_permiso WHERE usuario_id = :uid"),
        {"uid": usuario_id},
    )
    db.commit()
    return {"ok": True, "permisos_directos": 0}


@router.get("/modulos")
def listar_modulos(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Devuelve los módulos únicos del catálogo (para agrupar en la UI)."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    rows = db.execute(
        text("SELECT DISTINCT modulo FROM permiso ORDER BY modulo")
    ).fetchall()
    return [r.modulo for r in rows]
