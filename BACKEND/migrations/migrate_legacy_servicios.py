"""
Migración legacy `servicios` (MariaDB / esystemtic_erp) → nuevo esquema e-zyro (PostgreSQL).

Estrategia:
    1. Lee la tabla plana `servicios` del legacy.
    2. Agrupa por `orden_trabajo`:
         - 1 fila → 1 `proyecto` + 1 `proyecto_detalle`.
         - N filas → N `proyecto_servicio` vinculados al mismo proyecto.
    3. Resuelve cada FK contra el nuevo modelo:
         - id_empresaSolicitante  → cliente.id          (mapping configurable)
         - id_usuario             → usuario.id          (mapping configurable + fallback)
         - tipo_trabajo (texto)   → catalogo_servicio.id (lookup; auto-crea si falta)
         - id_zona                → string descriptivo (mapping opcional)
    4. Estado legacy → nuevos enums (Ejecutado → Completado, etc.).
    5. Es idempotente: usa ON CONFLICT (empresa_id, orden_trabajo) para reanudar.
    6. Corre dentro de UNA transacción por OT; si algo falla en esa OT se hace
       rollback parcial y se continúa con la siguiente.

Uso:
    pip install pymysql psycopg2-binary python-dotenv
    cp .env.example .env   # configura las cadenas de conexión
    python migrate_legacy_servicios.py --empresa-slug ezyro --dry-run
    python migrate_legacy_servicios.py --empresa-slug ezyro

ENV vars (o ajusta MIGRATION_CONFIG abajo):
    LEGACY_MYSQL_DSN   = mysql://user:pass@host:3306/esystemtic_erp
    TARGET_PG_DSN      = postgresql://user:pass@host:5432/ezyro
    DEFAULT_JEFE_EMAIL = jefe@ezyro.com   # empleado fallback para jefe_operaciones_id
"""
from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date
from typing import Any, Iterable, Optional
from urllib.parse import urlparse, unquote

import psycopg2
import psycopg2.extras
import pymysql
import pymysql.cursors

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# ============================================================
# CONFIGURACIÓN
# ============================================================

LEGACY_MYSQL_DSN = os.getenv("LEGACY_MYSQL_DSN", "mysql://root:@localhost:3306/esystemtic_erp")
TARGET_PG_DSN    = os.getenv("TARGET_PG_DSN",    "postgresql://postgres:postgres@localhost:5432/ezyro")
DEFAULT_JEFE_EMAIL = os.getenv("DEFAULT_JEFE_EMAIL", "")

# Mapeo legacy.id_empresaSolicitante → cliente.razon_social en la BD nueva.
# Carga las razones sociales reales aquí o pasa por ENV (LEGACY_CLIENTE_MAP).
LEGACY_CLIENTE_MAP: dict[int, str] = {
    1: "Ferreyros",
    2: "Cliente Lote 2",
    3: "Tecsup",
    4: "Cliente Ancón",
}

# Mapeo legacy.id_usuario → email del usuario en la BD nueva.
LEGACY_USUARIO_MAP: dict[int, str] = {
    1: "admin@ezyro.com",
    2: "tecnico2@ezyro.com",
    3: "tecnico3@ezyro.com",
    4: "tecnico4@ezyro.com",
    5: "tecnico5@ezyro.com",
    8: "tecnico8@ezyro.com",
}

# Mapeo legacy.id_zona → string descriptivo. Si no está, se guarda "Zona <id>".
LEGACY_ZONA_MAP: dict[int, str] = {
    1:  "Lima — Centro",
    2:  "Piura",
    3:  "Cámara de frío Importaciones",
    4:  "Lote 2",
    5:  "Almacén general",
    6:  "Importaciones",
    7:  "Cooperativa Norte",
    8:  "Omate",
    9:  "Talleres Docampo",
    10: "Cajamarca",
    # … completar con la realidad del cliente
}

ESTADO_MAP = {
    "Ejecutado": "Completado",
    "Pendiente": "Pendiente",
    "En Proceso": "En_Proceso",
    "EnProceso":  "En_Proceso",
    "Anulado":    "Cancelado",
}

TIPO_DOC_MAP = {
    "OC":   "OC",
    "PROF": "PROF",
    "":     "SIN_OC",
}

# Heurística: si el alcance original contiene marcadores tipo "sin oc" o "-",
# tratamos el documento como SIN_OC aunque el legacy diga "OC".
SIN_OC_HINTS = re.compile(r"^(sin\s*oc|-|\s*)$", re.IGNORECASE)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("migrate_servicios")


# ============================================================
# HELPERS
# ============================================================

def parse_mysql_dsn(dsn: str) -> dict[str, Any]:
    """`mysql://user:pass@host:port/db` → kwargs para pymysql.connect."""
    u = urlparse(dsn)
    return {
        "host":     u.hostname or "localhost",
        "port":     u.port or 3306,
        "user":     unquote(u.username or "root"),
        "password": unquote(u.password or ""),
        "database": (u.path or "/").lstrip("/"),
        "charset":  "utf8mb4",
        "cursorclass": pymysql.cursors.DictCursor,
    }


def normalize_alcance(raw: Optional[str]) -> Optional[str]:
    """Limpia el alcance legacy: quita marcadores `-~~-`, normaliza espacios."""
    if not raw:
        return None
    txt = raw.replace("-~~-", " · ").replace("\r\n", "\n").strip()
    return txt or None


def detectar_tipo_documento(legacy_tipo: str, legacy_nro: Optional[str], alcance: Optional[str]) -> str:
    """Decide el tipo de documento canónico, tolerando ruido del legacy."""
    tipo = (legacy_tipo or "").upper().strip()
    nro  = (legacy_nro or "").strip()
    base = TIPO_DOC_MAP.get(tipo, "SIN_OC")

    # Si el "nro" es "En Espera" o vacío y el alcance dice "SIN OC", forzamos SIN_OC.
    if not nro or nro.lower() in ("en espera", "espera del oc"):
        if alcance and SIN_OC_HINTS.match(alcance.strip()):
            return "SIN_OC"
        if base == "SIN_OC":
            return "SIN_OC"
        # Mantenemos tipo (OC/PROF) pero el nro será NULL.
    return base


def normalize_nro_documento(tipo: str, legacy_nro: Optional[str]) -> Optional[str]:
    if tipo == "SIN_OC":
        return None
    nro = (legacy_nro or "").strip()
    if not nro or nro.lower() in ("en espera", "espera del oc"):
        return None
    return nro


def derivar_acta_url(legacy_acta: Optional[str]) -> Optional[str]:
    """En el legacy las actas eran rutas relativas tipo `../../acta/...pdf`. Las
    dejamos tal cual: el backend nuevo las moverá a Cloudinary en una fase posterior."""
    if not legacy_acta:
        return None
    return legacy_acta.strip() or None


# ============================================================
# DATOS DE TRABAJO
# ============================================================

@dataclass
class ResolverCache:
    """Caches en memoria para no repetir SELECTs durante la migración."""
    empresa_id:           Optional[str]          = None
    jefe_empleado_id:     Optional[str]          = None
    catalogo_por_tipo:    dict[str, str]         = field(default_factory=dict)  # tipo_trabajo → catalogo.id
    cliente_por_legacy:   dict[int, str]         = field(default_factory=dict)  # id_empresaSolicitante → cliente.id
    usuario_por_legacy:   dict[int, str]         = field(default_factory=dict)  # id_usuario → usuario.id


# ============================================================
# RESOLUCIÓN DE FKs
# ============================================================

def resolver_empresa(pg_cur, slug: str) -> str:
    pg_cur.execute("SELECT id FROM empresa WHERE slug = %s OR razon_social = %s LIMIT 1", (slug, slug))
    row = pg_cur.fetchone()
    if not row:
        raise RuntimeError(f"No existe empresa con slug='{slug}'. Crea la empresa antes de migrar.")
    return row["id"]


def resolver_jefe_default(pg_cur, empresa_id: str, email: str) -> Optional[str]:
    if not email:
        return None
    pg_cur.execute(
        """
        SELECT e.id
        FROM empleado e
        JOIN usuario  u ON u.id = e.usuario_id
        WHERE e.empresa_id = %s AND u.email = %s
        LIMIT 1
        """,
        (empresa_id, email),
    )
    row = pg_cur.fetchone()
    if not row:
        log.warning("No se encontró empleado para el jefe default %s; los proyectos quedarán sin jefe.", email)
        return None
    return row["id"]


def resolver_cliente(pg_cur, empresa_id: str, cache: ResolverCache, legacy_id: Optional[int]) -> Optional[str]:
    if legacy_id is None:
        return None
    if legacy_id in cache.cliente_por_legacy:
        return cache.cliente_por_legacy[legacy_id]

    razon = LEGACY_CLIENTE_MAP.get(legacy_id)
    if not razon:
        log.warning("Cliente legacy id=%s sin mapeo; saltando.", legacy_id)
        return None

    pg_cur.execute(
        "SELECT id FROM cliente WHERE empresa_id = %s AND razon_social = %s LIMIT 1",
        (empresa_id, razon),
    )
    row = pg_cur.fetchone()
    if not row:
        log.warning("Cliente '%s' (legacy %s) no existe en la BD destino.", razon, legacy_id)
        return None
    cache.cliente_por_legacy[legacy_id] = row["id"]
    return row["id"]


def resolver_usuario(pg_cur, empresa_id: str, cache: ResolverCache, legacy_id: Optional[int]) -> Optional[str]:
    """Resuelve legacy.id_usuario → empleado.id (Técnico Líder).
    proyecto_servicio.responsable_id es FK a empleado(id), por eso resolvemos
    el usuario a su fila de empleado (no a usuario.id)."""
    if legacy_id is None:
        return None
    if legacy_id in cache.usuario_por_legacy:
        return cache.usuario_por_legacy[legacy_id]

    email = LEGACY_USUARIO_MAP.get(legacy_id)
    if not email:
        return None
    pg_cur.execute(
        """
        SELECT e.id
        FROM empleado e
        JOIN usuario  u ON u.id = e.usuario_id
        WHERE e.empresa_id = %s AND u.email = %s
        LIMIT 1
        """,
        (empresa_id, email),
    )
    row = pg_cur.fetchone()
    if not row:
        log.warning("Empleado para '%s' (legacy %s) no existe; servicio quedará sin técnico.", email, legacy_id)
        return None
    cache.usuario_por_legacy[legacy_id] = row["id"]
    return row["id"]


def resolver_catalogo(pg_cur, empresa_id: str, cache: ResolverCache, tipo_trabajo: str, auto_crear: bool) -> Optional[str]:
    """Busca catalogo_servicio por tipo_trabajo. Si no existe y `auto_crear`, lo crea."""
    key = (tipo_trabajo or "OTRO").strip().upper()
    if key in cache.catalogo_por_tipo:
        return cache.catalogo_por_tipo[key]

    pg_cur.execute(
        "SELECT id FROM catalogo_servicio WHERE empresa_id = %s AND UPPER(tipo_trabajo) = %s LIMIT 1",
        (empresa_id, key),
    )
    row = pg_cur.fetchone()
    if row:
        cache.catalogo_por_tipo[key] = row["id"]
        return row["id"]

    if not auto_crear:
        log.warning("Catálogo de servicios sin entrada para tipo_trabajo='%s'.", key)
        return None

    pg_cur.execute(
        """
        INSERT INTO catalogo_servicio (empresa_id, tipo_trabajo, nombre, descripcion, activo)
        VALUES (%s, %s, %s, %s, TRUE)
        RETURNING id
        """,
        (empresa_id, key, key.title(), f"Auto-creado desde migración legacy ({key})"),
    )
    new_id = pg_cur.fetchone()["id"]
    cache.catalogo_por_tipo[key] = new_id
    log.info("Catálogo auto-creado: tipo_trabajo='%s' → %s", key, new_id)
    return new_id


# ============================================================
# INSERCIÓN EN EL NUEVO ESQUEMA
# ============================================================

def upsert_proyecto(pg_cur, empresa_id: str, cliente_id: str, jefe_id: Optional[str],
                    orden_trabajo: str, nombre: str, estado: str,
                    fecha_inicio: Optional[date], fecha_fin: Optional[date]) -> str:
    """
    Inserta o reusa un proyecto por (empresa_id, orden_trabajo).
    Si ya existe, actualiza fechas/estado si el legacy es más completo.
    """
    pg_cur.execute(
        """
        INSERT INTO proyecto (empresa_id, cliente_id, contrato_comercial_id, orden_trabajo,
                              jefe_operaciones_id, nombre_proyecto, estado,
                              fecha_inicio, fecha_fin_estimada)
        VALUES (%s, %s, NULL, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (empresa_id, orden_trabajo) DO UPDATE
           SET nombre_proyecto    = COALESCE(EXCLUDED.nombre_proyecto, proyecto.nombre_proyecto),
               estado             = EXCLUDED.estado,
               fecha_inicio       = COALESCE(EXCLUDED.fecha_inicio,       proyecto.fecha_inicio),
               fecha_fin_estimada = COALESCE(EXCLUDED.fecha_fin_estimada, proyecto.fecha_fin_estimada),
               updated_at         = NOW()
        RETURNING id
        """,
        (empresa_id, cliente_id, orden_trabajo, jefe_id, nombre, estado, fecha_inicio, fecha_fin),
    )
    return pg_cur.fetchone()["id"]


def upsert_proyecto_detalle(pg_cur, proyecto_id: str, empresa_id: str,
                            orden_compra_marco: Optional[str]) -> None:
    pg_cur.execute(
        """
        INSERT INTO proyecto_detalle (proyecto_id, empresa_id, orden_compra_cliente, updated_at)
        VALUES (%s, %s, %s, NOW())
        ON CONFLICT (proyecto_id) DO UPDATE
           SET orden_compra_cliente = COALESCE(EXCLUDED.orden_compra_cliente,
                                               proyecto_detalle.orden_compra_cliente),
               updated_at           = NOW()
        """,
        (proyecto_id, empresa_id, orden_compra_marco),
    )


def insert_proyecto_servicio(pg_cur, *, proyecto_id: str, empresa_id: str,
                             catalogo_id: str, responsable_id: Optional[str],
                             nombre: str, descripcion: Optional[str], orden: int,
                             estado: str, fecha_programada: Optional[date],
                             fecha_inicio: Optional[date], fecha_fin: Optional[date],
                             zona_ejecucion: Optional[str], alcance: Optional[str],
                             tipo_doc: str, nro_doc: Optional[str],
                             nro_conformidad: str, acta_url: Optional[str]) -> str:
    pg_cur.execute(
        """
        INSERT INTO proyecto_servicio
            (proyecto_id, empresa_id, catalogo_servicio_id, responsable_id,
             nombre, descripcion, orden, estado,
             fecha_programada, fecha_inicio, fecha_fin,
             zona_ejecucion, alcance, tipo_documento_cliente, nro_documento,
             nro_conformidad, acta_url)
        VALUES (%s, %s, %s, %s,
                %s, %s, %s, %s,
                %s, %s, %s,
                %s, %s, %s, %s,
                %s, %s)
        RETURNING id
        """,
        (proyecto_id, empresa_id, catalogo_id, responsable_id,
         nombre, descripcion, orden, estado,
         fecha_programada, fecha_inicio, fecha_fin,
         zona_ejecucion, alcance, tipo_doc, nro_doc,
         nro_conformidad, acta_url),
    )
    return pg_cur.fetchone()["id"]


def already_migrated_service(pg_cur, proyecto_id: str, nombre: str, orden: int) -> bool:
    """Idempotencia para servicios: evita duplicar si re-corremos el script."""
    pg_cur.execute(
        "SELECT 1 FROM proyecto_servicio WHERE proyecto_id = %s AND orden = %s AND nombre = %s LIMIT 1",
        (proyecto_id, orden, nombre),
    )
    return pg_cur.fetchone() is not None


# ============================================================
# CORE
# ============================================================

def fetch_legacy_rows(mysql_conn) -> list[dict[str, Any]]:
    with mysql_conn.cursor() as cur:
        cur.execute(
            """
            SELECT *
            FROM servicios
            WHERE orden_trabajo IS NOT NULL AND orden_trabajo <> ''
            ORDER BY orden_trabajo, id_servicios
            """
        )
        return cur.fetchall()


def group_by_orden(rows: Iterable[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        grouped[r["orden_trabajo"]].append(r)
    return grouped


def construir_nombre_proyecto(rows: list[dict[str, Any]]) -> str:
    """Si todos los servicios comparten un tipo_trabajo común lo usamos; si no,
    tomamos el primer nombreservicios como representante."""
    tipos = {(r.get("tipo_trabajo") or "").strip().upper() for r in rows if r.get("tipo_trabajo")}
    if len(tipos) == 1:
        tipo = tipos.pop()
        primer = (rows[0].get("nombreservicios") or "").strip() or tipo
        return f"OT {rows[0]['orden_trabajo']} — {tipo}: {primer}"[:200]
    return f"OT {rows[0]['orden_trabajo']} — {(rows[0].get('nombreservicios') or 'Servicios varios').strip()}"[:200]


def determinar_oc_marco(rows: list[dict[str, Any]]) -> Optional[str]:
    """Si todas las filas comparten el mismo nro_documento (y tipo OC), ese es el OC marco."""
    ocs = {(r.get("nro_documento") or "").strip() for r in rows
           if (r.get("tipo_documento_cliente") or "").upper() == "OC"}
    ocs.discard("")
    ocs.discard("En Espera")
    if len(ocs) == 1:
        return ocs.pop()
    return None


def estado_proyecto_de_servicios(rows: list[dict[str, Any]]) -> str:
    """Si TODOS los servicios están Ejecutados, el proyecto está Completado.
       Si alguno está en Proceso → En_Proceso. Si todos Pendientes → Pendiente."""
    estados = {ESTADO_MAP.get((r.get("estado") or "").strip(), "Pendiente") for r in rows}
    if estados == {"Completado"}:
        return "Completado"
    if "En_Proceso" in estados:
        return "En_Proceso"
    if estados == {"Cancelado"}:
        return "Cancelado"
    return "Pendiente"


def fechas_proyecto(rows: list[dict[str, Any]]) -> tuple[Optional[date], Optional[date]]:
    inicios = [r["fechaInicio"] for r in rows if r.get("fechaInicio")]
    finales = [r["fechaFin"]    for r in rows if r.get("fechaFin")]
    return (min(inicios) if inicios else None, max(finales) if finales else None)


def migrar_ot(pg_conn, cache: ResolverCache, ot: str, rows: list[dict[str, Any]],
              dry_run: bool, auto_crear_catalogo: bool) -> tuple[int, int]:
    """Migra una orden de trabajo completa. Retorna (servicios_migrados, servicios_omitidos)."""
    pg_cur = pg_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    migrados = omitidos = 0

    cliente_legacy_id = rows[0].get("id_empresaSolicitante")
    cliente_id = resolver_cliente(pg_cur, cache.empresa_id, cache, cliente_legacy_id)
    if not cliente_id:
        log.error("OT %s: cliente legacy %s sin mapeo válido — OT saltada.", ot, cliente_legacy_id)
        return (0, len(rows))

    nombre_proy = construir_nombre_proyecto(rows)
    estado_proy = estado_proyecto_de_servicios(rows)
    fini, ffin  = fechas_proyecto(rows)
    oc_marco    = determinar_oc_marco(rows)

    if dry_run:
        log.info("[DRY] OT %s → proyecto '%s' (%s, %d servicios)", ot, nombre_proy, estado_proy, len(rows))
        return (len(rows), 0)

    try:
        proyecto_id = upsert_proyecto(
            pg_cur, cache.empresa_id, cliente_id, cache.jefe_empleado_id,
            ot, nombre_proy, estado_proy, fini, ffin,
        )
        upsert_proyecto_detalle(pg_cur, proyecto_id, cache.empresa_id, oc_marco)

        for idx, r in enumerate(rows, start=1):
            nombre = (r.get("nombreservicios") or f"Servicio {idx}").strip()[:200]
            if already_migrated_service(pg_cur, proyecto_id, nombre, idx):
                omitidos += 1
                continue

            tipo_trabajo = (r.get("tipo_trabajo") or "OTRO").strip().upper()
            catalogo_id = resolver_catalogo(pg_cur, cache.empresa_id, cache, tipo_trabajo, auto_crear_catalogo)
            if not catalogo_id:
                log.warning("OT %s · servicio #%d: sin catálogo → omitido.", ot, idx)
                omitidos += 1
                continue

            responsable_id = resolver_usuario(pg_cur, cache.empresa_id, cache, r.get("id_usuario"))

            alcance_raw = normalize_alcance(r.get("alcance"))
            tipo_doc    = detectar_tipo_documento(r.get("tipo_documento_cliente"), r.get("nro_documento"), alcance_raw)
            nro_doc     = normalize_nro_documento(tipo_doc, r.get("nro_documento"))

            zona_legacy_id = r.get("id_zona")
            zona_txt = LEGACY_ZONA_MAP.get(zona_legacy_id) if zona_legacy_id is not None else None
            if not zona_txt and zona_legacy_id is not None:
                zona_txt = f"Zona {zona_legacy_id}"

            estado_servicio = ESTADO_MAP.get((r.get("estado") or "").strip(), "Pendiente")
            conformidad     = (r.get("nro_conformidad") or "En Espera").strip() or "En Espera"

            insert_proyecto_servicio(
                pg_cur,
                proyecto_id=proyecto_id,
                empresa_id=cache.empresa_id,
                catalogo_id=catalogo_id,
                responsable_id=responsable_id,
                nombre=nombre,
                descripcion=None,
                orden=idx,
                estado=estado_servicio,
                fecha_programada=r.get("fechaCaptura"),
                fecha_inicio=r.get("fechaInicio"),
                fecha_fin=r.get("fechaFin"),
                zona_ejecucion=zona_txt,
                alcance=alcance_raw,
                tipo_doc=tipo_doc,
                nro_doc=nro_doc,
                nro_conformidad=conformidad,
                acta_url=derivar_acta_url(r.get("acta")),
            )
            migrados += 1

        pg_conn.commit()
        log.info("OT %s ✓ (proyecto %s, %d servicios migrados, %d omitidos)",
                 ot, proyecto_id, migrados, omitidos)
    except Exception as exc:
        pg_conn.rollback()
        log.exception("OT %s ✗ — rollback. Detalle: %s", ot, exc)
        return (migrados, len(rows) - migrados)
    finally:
        pg_cur.close()

    return (migrados, omitidos)


# ============================================================
# ENTRYPOINT
# ============================================================

def main() -> int:
    parser = argparse.ArgumentParser(description="Migra `servicios` legacy a proyecto + proyecto_servicio.")
    parser.add_argument("--empresa-slug", required=True,
                        help="Slug (o razón social) de la empresa destino.")
    parser.add_argument("--dry-run", action="store_true",
                        help="No inserta nada; solo reporta lo que migraría.")
    parser.add_argument("--no-auto-catalogo", action="store_true",
                        help="No auto-crea catalogo_servicio para tipo_trabajo inexistentes.")
    parser.add_argument("--limit", type=int, default=None,
                        help="Limita a las primeras N órdenes (debug).")
    args = parser.parse_args()

    log.info("Conectando legacy MySQL …")
    mysql_conn = pymysql.connect(**parse_mysql_dsn(LEGACY_MYSQL_DSN))
    log.info("Conectando PostgreSQL destino …")
    pg_conn = psycopg2.connect(TARGET_PG_DSN)

    try:
        pg_cur = pg_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cache = ResolverCache()
        cache.empresa_id       = resolver_empresa(pg_cur, args.empresa_slug)
        cache.jefe_empleado_id = resolver_jefe_default(pg_cur, cache.empresa_id, DEFAULT_JEFE_EMAIL)
        pg_cur.close()
        log.info("empresa_id=%s · jefe_default=%s", cache.empresa_id, cache.jefe_empleado_id or "—")

        rows = fetch_legacy_rows(mysql_conn)
        grouped = group_by_orden(rows)
        log.info("Legacy: %d filas en %d órdenes de trabajo.", len(rows), len(grouped))

        ordenes = list(grouped.items())
        if args.limit:
            ordenes = ordenes[: args.limit]

        total_mig = total_om = 0
        for ot, ot_rows in ordenes:
            mig, om = migrar_ot(pg_conn, cache, ot, ot_rows,
                                dry_run=args.dry_run,
                                auto_crear_catalogo=not args.no_auto_catalogo)
            total_mig += mig
            total_om  += om

        log.info("Hecho. Servicios migrados: %d · omitidos: %d (dry_run=%s).",
                 total_mig, total_om, args.dry_run)
    finally:
        mysql_conn.close()
        pg_conn.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
