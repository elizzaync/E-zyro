"""
Router: /privilegios — Gestión de permisos directos por usuario (extra sobre el rol).

Permite a usuarios con `privilegios:gestionar` ver el catálogo de permisos,
consultar qué permisos directos tiene un usuario (sobre los de su rol),
otorgar y revocar permisos directos. Acotado siempre a la empresa del token.
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.permisos import exigir_permiso
from ..core.security import verificar_token
from ..db.database import get_db
from ..models.permiso import Permiso
from ..models.rol import Rol
from ..models.rol_permiso import RolPermiso
from ..models.usuario import Usuario
from ..models.usuario_permiso import UsuarioPermiso
from ..models.usuario_rol import UsuarioRol

router = APIRouter(prefix="/privilegios", tags=["privilegios"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class PermisoOut(BaseModel):
    id: str
    modulo: str
    accion: str
    descripcion: Optional[str]
    via_rol: bool
    directo: bool


class UsuarioResumenOut(BaseModel):
    id: str
    nombre: str
    apellido: str
    username: str
    rol: Optional[str]
    activo: bool
    permisos_directos: int


class OtorgarIn(BaseModel):
    permiso_id: str


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/usuarios")
def listar_usuarios(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Lista todos los usuarios de la empresa con su rol y cantidad de permisos directos."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    empresa_id = payload["empresa_id"]

    # Subconsulta: permisos directos por usuario
    sub_directos = (
        db.query(UsuarioPermiso.usuario_id, func.count(UsuarioPermiso.permiso_id).label("cnt"))
        .group_by(UsuarioPermiso.usuario_id)
        .subquery()
    )

    rows = (
        db.query(
            Usuario.id,
            Usuario.nombre,
            Usuario.apellido,
            Usuario.username,
            Rol.nombre.label("rol"),
            Usuario.activo,
            func.coalesce(sub_directos.c.cnt, 0).label("permisos_directos"),
        )
        .outerjoin(UsuarioRol, UsuarioRol.usuario_id == Usuario.id)
        .outerjoin(Rol, Rol.id == UsuarioRol.rol_id)
        .outerjoin(sub_directos, sub_directos.c.usuario_id == Usuario.id)
        .filter(Usuario.empresa_id == empresa_id)
        .order_by(Usuario.nombre, Usuario.apellido)
        .all()
    )

    return [
        {
            "id": r.id,
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

    usuario = db.query(Usuario).filter(
        Usuario.id == usuario_id,
        Usuario.empresa_id == empresa_id,
    ).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    # IDs de permisos que el usuario tiene vía rol
    via_rol_ids: set[str] = {
        rp.permiso_id
        for ur in db.query(UsuarioRol).filter(UsuarioRol.usuario_id == usuario_id).all()
        for rp in db.query(RolPermiso).filter(RolPermiso.rol_id == ur.rol_id).all()
    }

    # IDs de permisos directos del usuario
    directos_ids: set[str] = {
        up.permiso_id
        for up in db.query(UsuarioPermiso).filter(UsuarioPermiso.usuario_id == usuario_id).all()
    }

    permisos = db.query(Permiso).order_by(Permiso.modulo, Permiso.accion).all()

    return [
        {
            "id": p.id,
            "modulo": p.modulo,
            "accion": p.accion,
            "descripcion": p.descripcion,
            "via_rol": p.id in via_rol_ids,
            "directo": p.id in directos_ids,
        }
        for p in permisos
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
    empresa_id   = payload["empresa_id"]
    otorgado_por = payload["id"]

    usuario = db.query(Usuario).filter(
        Usuario.id == usuario_id,
        Usuario.empresa_id == empresa_id,
    ).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    permiso = db.query(Permiso).filter(Permiso.id == body.permiso_id).first()
    if not permiso:
        raise HTTPException(status_code=404, detail="Permiso no encontrado")

    existe = db.query(UsuarioPermiso).filter(
        UsuarioPermiso.usuario_id == usuario_id,
        UsuarioPermiso.permiso_id == body.permiso_id,
    ).first()
    if not existe:
        db.add(UsuarioPermiso(
            usuario_id=usuario_id,
            permiso_id=body.permiso_id,
            asignado_por=otorgado_por,
        ))
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

    usuario = db.query(Usuario).filter(
        Usuario.id == usuario_id,
        Usuario.empresa_id == empresa_id,
    ).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    db.query(UsuarioPermiso).filter(
        UsuarioPermiso.usuario_id == usuario_id,
        UsuarioPermiso.permiso_id == permiso_id,
    ).delete()
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

    usuario = db.query(Usuario).filter(
        Usuario.id == usuario_id,
        Usuario.empresa_id == empresa_id,
    ).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    directos_existentes: set[str] = {
        up.permiso_id
        for up in db.query(UsuarioPermiso).filter(UsuarioPermiso.usuario_id == usuario_id).all()
    }
    todos = db.query(Permiso).all()
    for p in todos:
        if p.id not in directos_existentes:
            db.add(UsuarioPermiso(
                usuario_id=usuario_id,
                permiso_id=p.id,
                asignado_por=otorgado_por,
            ))
    db.commit()

    total = db.query(UsuarioPermiso).filter(UsuarioPermiso.usuario_id == usuario_id).count()
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

    usuario = db.query(Usuario).filter(
        Usuario.id == usuario_id,
        Usuario.empresa_id == empresa_id,
    ).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    db.query(UsuarioPermiso).filter(UsuarioPermiso.usuario_id == usuario_id).delete()
    db.commit()
    return {"ok": True, "permisos_directos": 0}


@router.get("/modulos")
def listar_modulos(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Devuelve los módulos únicos del catálogo (para agrupar en la UI)."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    modulos = (
        db.query(Permiso.modulo)
        .distinct()
        .order_by(Permiso.modulo)
        .all()
    )
    return [r.modulo for r in modulos]


@router.get("/catalogo")
def catalogo_permisos(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Devuelve el catálogo completo de permisos agrupado por módulo."""
    exigir_permiso(db, payload, "privilegios", "gestionar")
    permisos = db.query(Permiso).order_by(Permiso.modulo, Permiso.accion).all()
    return [
        {"id": p.id, "modulo": p.modulo, "accion": p.accion, "descripcion": p.descripcion}
        for p in permisos
    ]
