"""
RBAC centralizado — verificación de permisos finos por (modulo, accion).

Modelo de datos (ya existente en la BD):
  - permiso(id, modulo, accion, descripcion)        ← catálogo GLOBAL, (modulo, accion) único
  - rol(id, empresa_id, ...) / rol_permiso(rol_id, permiso_id)
  - usuario_rol(usuario_id, rol_id, ...)             ← permiso vía rol
  - usuario_permiso(usuario_id, permiso_id, ...)     ← permiso directo al usuario

Convención de nombres: modulo/accion en MINÚSCULAS (coincide con la data sembrada:
'inventario/gestionar', 'empleados/ver', ...). SuperAdmin/Admin tienen bypass total.
"""
from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

_ROLES_ADMIN = {"superadmin", "admin", "administrador"}


def es_admin(payload: dict) -> bool:
    """SuperAdmin/Admin tienen permiso absoluto, sin consultar BD."""
    return (payload.get("rol") or "").lower().strip() in _ROLES_ADMIN


def tiene_permiso(db: Session, payload: dict, modulo: str, accion: str) -> bool:
    """True si el usuario es admin o tiene el permiso (vía rol o asignación directa)."""
    if es_admin(payload):
        return True
    usuario_id = payload.get("id")
    if not usuario_id:
        return False
    q = text(
        """
        SELECT 1 FROM permiso p
          JOIN rol_permiso rp ON rp.permiso_id = p.id
          JOIN usuario_rol  ur ON ur.rol_id    = rp.rol_id
         WHERE ur.usuario_id = :uid AND p.modulo = :m AND p.accion = :a
        UNION
        SELECT 1 FROM permiso p
          JOIN usuario_permiso up ON up.permiso_id = p.id
         WHERE up.usuario_id = :uid AND p.modulo = :m AND p.accion = :a
        LIMIT 1
        """
    )
    return db.execute(q, {"uid": usuario_id, "m": modulo, "a": accion}).first() is not None


def exigir_permiso(db: Session, payload: dict, modulo: str, accion: str) -> None:
    """Lanza 403 si el usuario no tiene el permiso (modulo.accion)."""
    if not tiene_permiso(db, payload, modulo, accion):
        raise HTTPException(status_code=403, detail=f"Sin permiso: {modulo}.{accion}")
