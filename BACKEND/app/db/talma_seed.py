"""
Seed idempotente — Portal Cliente TALMA (HU-22).

El usuario 'cliente_talma' vive en la empresa OPERADORA (la empresa que
gestiona proyectos y equipos en el ERP), no en una empresa fantasma creada
para el portal. El seed detecta la empresa operadora buscando la empresa que
ya tiene un cliente llamado "TALMA" con registros de equipos intervenidos.
"""
from __future__ import annotations
import uuid
from passlib.context import CryptContext
from sqlalchemy import text

_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")

_USERNAME   = "cliente_talma"
_PASSWORD   = "Talma2026*"
_ROL_NOMBRE = "ClienteExterno"
_TALMA_RUC  = "20100173517"
_TALMA_RS   = "TALMA"   # fragmento para búsqueda ILIKE


def _find_operator_empresa(conn) -> str | None:
    """Devuelve el empresa_id del operador: el que ya tiene equipos de TALMA.

    Jerarquía de búsqueda:
    1. Empresa que tiene un cliente 'TALMA' con equipos intervenidos.
    2. Empresa que tiene un cliente 'TALMA' (aunque sin equipos aún).
    3. Cualquier empresa que NO sea la creada como portal-fantasma de TALMA
       (descarta las que tienen ruc=_TALMA_RUC o slug='talma').
    """
    # 1. Empresa con equipos de TALMA
    row = conn.execute(text("""
        SELECT DISTINCT ei.empresa_id
        FROM equipo_intervenido ei
        JOIN cliente c ON c.id = ei.cliente_id
        WHERE lower(c.razon_social) LIKE lower(:patron)
        ORDER BY ei.empresa_id
        LIMIT 1
    """), {"patron": f"%{_TALMA_RS}%"}).fetchone()
    if row:
        return str(row[0])

    # 2. Empresa con cliente 'TALMA' registrado
    row = conn.execute(text("""
        SELECT c.empresa_id
        FROM cliente c
        JOIN empresa e ON e.id = c.empresa_id
        WHERE lower(c.razon_social) LIKE lower(:patron)
          AND e.ruc != :ruc
        ORDER BY c.created_at
        LIMIT 1
    """), {"patron": f"%{_TALMA_RS}%", "ruc": _TALMA_RUC}).fetchone()
    if row:
        return str(row[0])

    # 3. Primera empresa que no sea la portal-fantasma de TALMA
    row = conn.execute(text("""
        SELECT id FROM empresa
        WHERE ruc != :ruc
        ORDER BY created_at
        LIMIT 1
    """), {"ruc": _TALMA_RUC}).fetchone()
    if row:
        return str(row[0])

    return None


def sembrar_talma(conn) -> None:
    """Crea (o reutiliza) el usuario portal para TALMA dentro de la empresa operadora."""

    # ── 1. Empresa operadora ──────────────────────────────────────────────────
    empresa_id = _find_operator_empresa(conn)
    if not empresa_id:
        print("  [talma_seed] ERROR: no se encontró empresa operadora — seed abortado.")
        return

    # ── 2. Cliente TALMA dentro del operador ──────────────────────────────────
    row = conn.execute(text("""
        SELECT id FROM cliente
        WHERE empresa_id = :eid
          AND (ruc = :ruc OR lower(razon_social) LIKE lower(:patron))
        ORDER BY
            CASE WHEN ruc = :ruc THEN 0 ELSE 1 END,
            created_at
        LIMIT 1
    """), {"eid": empresa_id, "ruc": _TALMA_RUC, "patron": f"%{_TALMA_RS}%"}).fetchone()

    cliente_id: str = str(row[0]) if row else str(uuid.uuid4())
    if not row:
        conn.execute(text("""
            INSERT INTO cliente (id, empresa_id, razon_social, ruc, activo, created_at)
            VALUES (:id, :eid, 'TALMA S.A.', :ruc, true, now())
        """), {"id": cliente_id, "eid": empresa_id, "ruc": _TALMA_RUC})

    # ── 3. Rol ClienteExterno dentro del operador ─────────────────────────────
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

    # ── 4. Usuario portal dentro del operador ─────────────────────────────────
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
                (:id, :eid, 'Cliente', 'TALMA', :uname, 'operaciones@talma.pe',
                 :pwd, true, true, now())
        """), {
            "id": usuario_id, "eid": empresa_id,
            "uname": _USERNAME,
            "pwd": _pwd.hash(_PASSWORD),
        })

    # ── 5. Asignación usuario → rol (solo ClienteExterno, nada más) ───────────
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

    # ── 6. portal_acceso → cliente_id en el JWT ───────────────────────────────
    row = conn.execute(text(
        "SELECT usuario_id FROM portal_acceso WHERE usuario_id = :uid LIMIT 1"
    ), {"uid": usuario_id}).fetchone()

    if not row:
        conn.execute(text("""
            INSERT INTO portal_acceso (usuario_id, cliente_id, created_at)
            VALUES (:uid, :cid, now())
        """), {"uid": usuario_id, "cid": cliente_id})
    else:
        # Asegurarse de que apunte al cliente correcto
        conn.execute(text("""
            UPDATE portal_acceso SET cliente_id = :cid
            WHERE usuario_id = :uid
        """), {"uid": usuario_id, "cid": cliente_id})

    # ── 7. Neutralizar usuarios duplicados con el mismo username ─────────────
    # Si hay otros usuarios 'cliente_talma' en OTRAS empresas (p.ej. la empresa
    # fantasma creada por versiones anteriores del seed), renombrarlos para que
    # el login no los devuelva y produzca datos vacíos.
    deprecated_ids = conn.execute(text("""
        SELECT id FROM usuario
        WHERE username = :uname
          AND empresa_id::text != :eid
    """), {"uname": _USERNAME, "eid": empresa_id}).fetchall()

    conn.execute(text("""
        UPDATE usuario
        SET username   = username || '_deprecated',
            activo     = false
        WHERE username = :uname
          AND empresa_id::text != :eid
    """), {"uname": _USERNAME, "eid": empresa_id})

    # ── 8. Invalidar sesiones de usuarios deprecados ──────────────────────────
    # Sus JWTs viejos duran 7 días pero portal_cliente.py ahora re-valida desde
    # la BD; esta limpieza es solo higiene (evita tokens zombie en el tracker).
    for (dep_id,) in deprecated_ids:
        conn.execute(text("""
            UPDATE sesion_usuario
            SET activa = false, fecha_cierre = now()
            WHERE usuario_id = :uid AND activa = true
        """), {"uid": str(dep_id)})

    conn.commit()

    # ── Resumen en stdout ─────────────────────────────────────────────────────
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
