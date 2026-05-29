"""
Sembrado idempotente de permisos para las migraciones de arranque.

Se llama desde `_run_migrations()` en main.py. Usa el índice único existente
`permiso(modulo, accion)` para no duplicar (ON CONFLICT DO NOTHING).
"""
from __future__ import annotations

import uuid
from sqlalchemy import text


def sembrar_permisos(conn, modulo: str, acciones: list[str], descripcion_base: str = "") -> None:
    """Inserta los permisos (modulo, accion) que falten. Idempotente."""
    for accion in acciones:
        desc = (f"{descripcion_base} {accion}").strip() or f"{modulo} {accion}"
        conn.execute(
            text(
                """
                INSERT INTO permiso (id, modulo, accion, descripcion)
                VALUES (:id, :m, :a, :d)
                ON CONFLICT (modulo, accion) DO NOTHING
                """
            ),
            {"id": str(uuid.uuid4()), "m": modulo, "a": accion, "d": desc},
        )


# ── Matriz rol → permisos (modulo:accion) ────────────────────────────────────
# Convención: nombres de rol tal como están en la tabla `rol`. El Administrador
# recibe TODOS los permisos del catálogo (además del bypass en core/permisos).
# Cada entrada es "modulo:accion".
MATRIZ_ROL_PERMISO: dict[str, list[str]] = {
    "Jefe de Operaciones": [
        "dashboard:ver", "reportes:ver",
        "proyectos:ver", "proyectos:crear", "proyectos:editar",
        "asistencia:ver", "asistencia:validar",
        "requerimientos:ver", "requerimientos:aprobar",
        "correctivo:ver", "correctivo:crear", "correctivo:editar",
        "correctivo:aprobar", "correctivo:finalizar",
        "observacion:ver", "observacion:crear", "observacion:editar", "observacion:eliminar",
        "itse:ver", "itse:crear", "itse:editar", "itse:finalizar",
        "informe_servicio:ver", "informe_servicio:generar",
        "equipo:ver_estado", "equipo:marcar_inoperativo", "equipo:reactivar",
        "calibracion:ver", "calibracion:crear", "calibracion:editar",
        "epp:ver", "inventario:ver", "empleados:ver",
        "galeria:ver", "galeria:subir",
    ],
    "Logístico": [
        "dashboard:ver",
        "inventario:ver", "inventario:gestionar",
        "requerimientos:ver", "requerimientos:aprobar",
        "epp:ver", "epp:crear", "epp:editar", "epp:entregar", "epp:ingresar", "epp:eliminar",
        "catalogos:ver", "catalogos:crear", "catalogos:editar", "catalogos:eliminar",
        "calibracion:ver", "calibracion:crear", "calibracion:editar",
        "equipo:ver_estado", "proyectos:ver",
        "galeria:ver", "galeria:subir",
    ],
    "Supervisor": [
        "dashboard:ver",
        "proyectos:ver", "proyectos:editar",
        "asistencia:ver", "asistencia:validar",
        "itse:ver", "itse:crear", "itse:editar", "itse:finalizar",
        "observacion:ver", "observacion:crear", "observacion:editar",
        "correctivo:ver", "correctivo:crear", "correctivo:editar",
        "equipo:ver_estado", "equipo:marcar_inoperativo",
        "informe_servicio:ver", "informe_servicio:generar",
        "requerimientos:ver", "epp:ver", "calibracion:ver",
        "galeria:ver", "galeria:subir",
    ],
    "Técnico de Campo": [
        "asistencia:registrar", "asistencia:ver",
        "proyectos:ver",
        "itse:ver", "itse:crear", "itse:editar",
        "observacion:ver", "observacion:crear",
        "correctivo:ver", "correctivo:crear",
        "equipo:ver_estado",
        "requerimientos:ver", "epp:ver", "calibracion:ver",
        "informe_servicio:ver",
        "galeria:ver", "galeria:subir",
    ],
}

# Roles que reciben TODO el catálogo de permisos.
ROLES_TODO_PERMISO = ("Administrador", "SuperAdmin", "Super Admin")


def _vincular(conn, rol_nombre: str, modulo: str, accion: str) -> None:
    """Vincula (rol por nombre) → (permiso por modulo,accion) si aún no existe.
    Aplica a TODAS las empresas que tengan un rol con ese nombre."""
    conn.execute(
        text(
            """
            INSERT INTO rol_permiso (rol_id, permiso_id)
            SELECT r.id, p.id
              FROM rol r
              JOIN permiso p ON p.modulo = :m AND p.accion = :a
             WHERE r.nombre = :rn
               AND NOT EXISTS (
                   SELECT 1 FROM rol_permiso rp
                    WHERE rp.rol_id = r.id AND rp.permiso_id = p.id
               )
            """
        ),
        {"rn": rol_nombre, "m": modulo, "a": accion},
    )


def sembrar_rol_permiso(conn) -> None:
    """Asigna permisos a los roles según MATRIZ_ROL_PERMISO. Idempotente.

    - Admin/SuperAdmin: todo el catálogo `permiso`.
    - Resto de roles: solo los (modulo,accion) listados en la matriz.
    """
    # Roles con todo el catálogo
    for rol_nombre in ROLES_TODO_PERMISO:
        conn.execute(
            text(
                """
                INSERT INTO rol_permiso (rol_id, permiso_id)
                SELECT r.id, p.id
                  FROM rol r CROSS JOIN permiso p
                 WHERE r.nombre = :rn
                   AND NOT EXISTS (
                       SELECT 1 FROM rol_permiso rp
                        WHERE rp.rol_id = r.id AND rp.permiso_id = p.id
                   )
                """
            ),
            {"rn": rol_nombre},
        )
    # Roles con matriz específica
    for rol_nombre, permisos in MATRIZ_ROL_PERMISO.items():
        for perm in permisos:
            modulo, _, accion = perm.partition(":")
            _vincular(conn, rol_nombre, modulo, accion)
