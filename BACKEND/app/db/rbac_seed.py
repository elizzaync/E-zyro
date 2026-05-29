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
