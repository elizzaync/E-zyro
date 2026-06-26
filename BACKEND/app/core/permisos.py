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

# Nombres exactos de roles en BD (normalizados a minúsculas sin espacios extra)
# Rol en BD: "Técnico"  →  normalizado: "técnico"
_ROL_TECNICO          = "técnico"
_ROL_JEFE_OPERACIONES = "jefedeoperaciones"


def _normalizar_rol(payload: dict) -> str:
    return (payload.get("rol") or "").lower().strip().replace(" ", "").replace("\xa0", "")


def es_admin(payload: dict) -> bool:
    """SuperAdmin/Admin tienen permiso absoluto, sin consultar BD."""
    return _normalizar_rol(payload) in _ROLES_ADMIN


def es_tecnico(payload: dict) -> bool:
    """True si el usuario tiene el rol Técnico de Campo."""
    return _normalizar_rol(payload) == _ROL_TECNICO


def es_jefe_operaciones(payload: dict) -> bool:
    """True si el usuario tiene el rol Jefe de Operaciones."""
    return _normalizar_rol(payload) == _ROL_JEFE_OPERACIONES


def exigir_no_tecnico(payload: dict, mensaje: str = "Acción no permitida para Técnico") -> None:
    """Lanza 403 si el usuario es Técnico de Campo."""
    if es_tecnico(payload):
        raise HTTPException(status_code=403, detail=mensaje)


def exigir_solo_admin(payload: dict, mensaje: str = "Solo administradores pueden realizar esta acción") -> None:
    """Lanza 403 si el usuario no es admin (bloquea Técnico y Jefe de Operaciones)."""
    if not es_admin(payload):
        raise HTTPException(status_code=403, detail=mensaje)


def exigir_no_roles_operativos(payload: dict, mensaje: str = "Acceso no autorizado para este rol") -> None:
    """Lanza 403 si el usuario es Técnico o Jefe de Operaciones (módulos bloqueados para ambos)."""
    rol = _normalizar_rol(payload)
    if rol in (_ROL_TECNICO, _ROL_JEFE_OPERACIONES):
        raise HTTPException(status_code=403, detail=mensaje)


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


def usuarios_con_permiso(db: Session, empresa_id: str, modulo: str, accion: str) -> list[str]:
    """Reverse-lookup: IDs de usuarios activos de la empresa que tienen el permiso
    (modulo.accion) vía rol o asignación directa, MÁS los administradores (que por
    convención tienen permiso absoluto). Base para targetear notificaciones por
    permiso en vez de por nombre de rol.
    """
    q = text(
        """
        SELECT u.id FROM usuario u
          JOIN usuario_rol ur ON ur.usuario_id = u.id
          JOIN rol_permiso rp ON rp.rol_id = ur.rol_id
          JOIN permiso p      ON p.id = rp.permiso_id
         WHERE u.empresa_id = :emp AND u.activo = true
           AND p.modulo = :m AND p.accion = :a
        UNION
        SELECT u.id FROM usuario u
          JOIN usuario_permiso up ON up.usuario_id = u.id
          JOIN permiso p          ON p.id = up.permiso_id
         WHERE u.empresa_id = :emp AND u.activo = true
           AND p.modulo = :m AND p.accion = :a
        UNION
        SELECT u.id FROM usuario u
          JOIN usuario_rol ur ON ur.usuario_id = u.id
          JOIN rol r          ON r.id = ur.rol_id
         WHERE u.empresa_id = :emp AND u.activo = true
           AND replace(lower(r.nombre), ' ', '') IN ('superadmin','admin','administrador')
        """
    )
    rows = db.execute(q, {"emp": empresa_id, "m": modulo, "a": accion}).fetchall()
    return [r[0] for r in rows]
