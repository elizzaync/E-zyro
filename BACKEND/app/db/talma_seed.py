"""
Seed idempotente para TALMA — empresa + rol ClienteExterno + usuario portal.
Se ejecuta cada startup; no hace nada si los registros ya existen.
"""
from __future__ import annotations
import uuid
from passlib.context import CryptContext
from sqlalchemy import text

_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── Constantes del seed ────────────────────────────────────────────────────────
_SLUG      = "talma"
_RUC       = "20100173517"
_RAZON     = "TALMA S.A."
_EMAIL     = "operaciones@talma.pe"
_USERNAME  = "cliente_talma"
_PASSWORD  = "Talma2026*"
_ROL_NOMBRE = "ClienteExterno"


def sembrar_talma(conn) -> None:
    """Crea (o reutiliza) la empresa TALMA con su usuario portal cliente."""

    # ── 1. Empresa ────────────────────────────────────────────────────────────
    row = conn.execute(text(
        "SELECT id FROM empresa WHERE slug = :slug OR ruc = :ruc LIMIT 1"
    ), {"slug": _SLUG, "ruc": _RUC}).fetchone()

    empresa_id: str = str(row[0]) if row else str(uuid.uuid4())
    if not row:
        conn.execute(text("""
            INSERT INTO empresa
                (id, razon_social, ruc, email_contacto, slug, estado, created_at, fecha_registro)
            VALUES (:id, :rs, :ruc, :email, :slug, 'activo', now(), now())
        """), {"id": empresa_id, "rs": _RAZON, "ruc": _RUC,
               "email": _EMAIL, "slug": _SLUG})

    # ── 2. Rol ClienteExterno ─────────────────────────────────────────────────
    row = conn.execute(text("""
        SELECT id FROM rol
        WHERE empresa_id = :eid
          AND lower(replace(nombre,' ','')) = 'clienteexterno'
        LIMIT 1
    """), {"eid": empresa_id}).fetchone()

    rol_id: str = str(row[0]) if row else str(uuid.uuid4())
    if not row:
        conn.execute(text("""
            INSERT INTO rol
                (id, empresa_id, nombre, descripcion, es_rol_sistema, created_at)
            VALUES (:id, :eid, :nombre, 'Portal de seguimiento para clientes externos', true, now())
        """), {"id": rol_id, "eid": empresa_id, "nombre": _ROL_NOMBRE})

    # ── 3. Registro en tabla cliente (para el aislamiento de datos) ───────────
    row = conn.execute(text("""
        SELECT id FROM cliente
        WHERE empresa_id = :eid AND lower(razon_social) = lower(:rs)
        LIMIT 1
    """), {"eid": empresa_id, "rs": _RAZON}).fetchone()

    cliente_id: str = str(row[0]) if row else str(uuid.uuid4())
    if not row:
        conn.execute(text("""
            INSERT INTO cliente (id, empresa_id, razon_social, ruc, activo, created_at)
            VALUES (:id, :eid, :rs, :ruc, true, now())
        """), {"id": cliente_id, "eid": empresa_id, "rs": _RAZON, "ruc": _RUC})

    # ── 4. Usuario portal ─────────────────────────────────────────────────────
    row = conn.execute(text("""
        SELECT id FROM usuario
        WHERE empresa_id = :eid AND username = :uname
        LIMIT 1
    """), {"eid": empresa_id, "uname": _USERNAME}).fetchone()

    usuario_id: str = str(row[0]) if row else str(uuid.uuid4())
    if not row:
        conn.execute(text("""
            INSERT INTO usuario
                (id, empresa_id, nombre, apellido, username, email,
                 password_hash, activo, email_verificado, created_at)
            VALUES
                (:id, :eid, 'Cliente', 'TALMA', :uname, :email,
                 :pwd, true, true, now())
        """), {
            "id": usuario_id, "eid": empresa_id,
            "uname": _USERNAME, "email": _EMAIL,
            "pwd": _pwd.hash(_PASSWORD),
        })

    # ── 5. Asignación usuario → rol ───────────────────────────────────────────
    # Purgar roles incorrectos (p.ej. Administrador inyectado por sembrar_roles_sistema).
    # Este usuario debe tener SOLO el rol ClienteExterno.
    conn.execute(text("""
        DELETE FROM usuario_rol
        WHERE usuario_id = :uid AND rol_id <> :rid
    """), {"uid": usuario_id, "rid": rol_id})

    row = conn.execute(text("""
        SELECT id FROM usuario_rol
        WHERE usuario_id = :uid AND rol_id = :rid
        LIMIT 1
    """), {"uid": usuario_id, "rid": rol_id}).fetchone()

    if not row:
        conn.execute(text("""
            INSERT INTO usuario_rol (id, usuario_id, rol_id, empresa_id, created_at)
            VALUES (:id, :uid, :rid, :eid, now())
        """), {"id": str(uuid.uuid4()), "uid": usuario_id,
               "rid": rol_id, "eid": empresa_id})

    # ── 6. portal_acceso → aísla datos por cliente_id en el JWT ──────────────
    row = conn.execute(text(
        "SELECT usuario_id FROM portal_acceso WHERE usuario_id = :uid LIMIT 1"
    ), {"uid": usuario_id}).fetchone()

    if not row:
        conn.execute(text("""
            INSERT INTO portal_acceso (usuario_id, cliente_id, created_at)
            VALUES (:uid, :cid, now())
        """), {"uid": usuario_id, "cid": cliente_id})

    conn.commit()

    # ── Print en stdout (visible en los logs del servidor) ───────────────────
    print("")
    print("=" * 62)
    print("  SEED TALMA — CREDENCIALES PORTAL CLIENTE  ")
    print("=" * 62)
    print(f"  empresa_id : {empresa_id}")
    print(f"  cliente_id : {cliente_id}")
    print(f"  usuario_id : {usuario_id}")
    print(f"  username   : {_USERNAME}")
    print(f"  password   : {_PASSWORD}")
    print(f"  rol        : {_ROL_NOMBRE}")
    print("=" * 62)
    print("")
