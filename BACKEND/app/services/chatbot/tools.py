"""
Herramientas (tools) del chatbot — TODAS de solo lectura.

Garantías de seguridad:
  - `empresa_id` se inyecta SIEMPRE desde el JWT (server-side), nunca desde el
    modelo → imposible filtrar datos de otra empresa.
  - Las entradas del modelo se pasan como parámetros enlazados (bind params),
    nunca por interpolación de strings → sin inyección SQL.
  - LIMIT acotado (máx. 50).
  - Herramientas sensibles (personal) verifican RBAC con `tiene_permiso`.

Para añadir una herramienta nueva (mejora continua):
  1) añade su esquema a TOOL_DEFS,
  2) escribe su función `_tool_xxx(db, payload, args) -> str`,
  3) regístrala en _DISPATCH.
"""
from __future__ import annotations

import json

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.permisos import tiene_permiso


# ─────────────────────────── helpers ────────────────────────────────────────

def _limite(args: dict, defecto: int = 20, tope: int = 50) -> int:
    try:
        return max(1, min(int(args.get("limite", defecto)), tope))
    except (TypeError, ValueError):
        return defecto


def _like(valor) -> str:
    return f"%{str(valor).strip()}%"


def _filas(db: Session, sql: str, params: dict) -> list[dict]:
    return [dict(m) for m in db.execute(text(sql), params).mappings().all()]


def _ok(filas: list[dict], **extra) -> str:
    payload = {"total": len(filas), "resultados": filas}
    payload.update(extra)
    return json.dumps(payload, default=str, ensure_ascii=False)


def _err(mensaje: str) -> str:
    return json.dumps({"error": mensaje}, ensure_ascii=False)


# ─────────────────────────── herramientas ───────────────────────────────────

def _tool_buscar_materiales(db, payload, args) -> str:
    emp = payload["empresa_id"]
    cond = ["m.empresa_id = :emp", "m.activo = true"]
    params = {"emp": emp, "lim": _limite(args)}

    tipo = args.get("tipo")
    if tipo in ("consumible", "herramienta"):
        cond.append("m.tipo = :tipo")
        params["tipo"] = tipo
    if args.get("query"):
        cond.append("(m.nombre ILIKE :q OR m.codigo ILIKE :q)")
        params["q"] = _like(args["query"])

    having = ""
    if args.get("solo_stock_bajo"):
        having = "HAVING COALESCE(SUM(s.cantidad),0) <= COALESCE(MAX(s.cantidad_minima),0)"

    sql = f"""
        SELECT m.nombre, m.codigo, m.tipo, m.unidad,
               COALESCE(c.nombre, 'Sin categoría') AS categoria,
               COALESCE(SUM(s.cantidad), 0)        AS stock_total,
               COALESCE(MAX(s.cantidad_minima), 0) AS stock_minimo
          FROM material m
          LEFT JOIN categoria_material c ON c.id = m.categoria_id
          LEFT JOIN stock s ON s.material_id = m.id
         WHERE {' AND '.join(cond)}
         GROUP BY m.id, m.nombre, m.codigo, m.tipo, m.unidad, c.nombre
         {having}
         ORDER BY m.nombre
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_equipos(db, payload, args) -> str:
    """Equipos propios de la empresa (activos electrónicos / herramientas tecnológicas)."""
    emp = payload["empresa_id"]
    cond = ["e.empresa_id = :emp"]
    params = {"emp": emp, "lim": _limite(args)}

    if args.get("query"):
        cond.append("(e.nombre ILIKE :q OR e.codigo ILIKE :q OR e.marca ILIKE :q OR e.numero_serie ILIKE :q)")
        params["q"] = _like(args["query"])
    if args.get("estado"):
        cond.append("e.estado = :estado")
        params["estado"] = args["estado"]
    if args.get("requiere_mantenimiento") is True:
        cond.append("e.requiere_mantenimiento = true")

    sql = f"""
        SELECT e.nombre, e.codigo, e.marca, e.modelo, e.numero_serie,
               e.estado, e.cantidad, e.requiere_mantenimiento,
               e.proxima_fecha_mantenimiento
          FROM equipo e
         WHERE {' AND '.join(cond)}
         ORDER BY e.nombre
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_equipos_intervenidos(db, payload, args) -> str:
    """Equipos del cliente que la empresa instala / mantiene (tableros, pozos, etc.)."""
    emp = payload["empresa_id"]
    cond = ["ei.empresa_id = :emp", "ei.activo = true"]
    params = {"emp": emp, "lim": _limite(args)}

    if args.get("query"):
        cond.append("(ei.nombre ILIKE :q OR ei.codigo ILIKE :q)")
        params["q"] = _like(args["query"])
    if args.get("cliente"):
        cond.append("cl.razon_social ILIKE :cli")
        params["cli"] = _like(args["cliente"])
    if args.get("estado"):
        cond.append("ei.estado = :estado")
        params["estado"] = args["estado"]

    sql = f"""
        SELECT ei.nombre, ei.codigo, ei.estado, ei.marca, ei.modelo,
               cl.razon_social AS cliente,
               u.nombre        AS ubicacion,
               z.nombre        AS zona,
               ei.area_descripcion AS area,
               p.nombre_proyecto   AS proyecto
          FROM equipo_intervenido ei
          LEFT JOIN cliente   cl ON cl.id = ei.cliente_id
          LEFT JOIN ubicacion u  ON u.id  = ei.ubicacion_id
          LEFT JOIN zona      z  ON z.id  = ei.zona_id
          LEFT JOIN proyecto  p  ON p.id  = ei.proyecto_id
         WHERE {' AND '.join(cond)}
         ORDER BY ei.nombre
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_epp(db, payload, args) -> str:
    emp = payload["empresa_id"]
    cond = ["empresa_id = :emp", "activo = true"]
    params = {"emp": emp, "lim": _limite(args)}

    if args.get("query"):
        cond.append("nombre ILIKE :q")
        params["q"] = _like(args["query"])
    if args.get("solo_stock_bajo"):
        cond.append("stock_actual <= stock_min")

    sql = f"""
        SELECT nombre, descripcion, stock_actual, stock_min, precio
          FROM epp
         WHERE {' AND '.join(cond)}
         ORDER BY nombre
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_proyectos(db, payload, args) -> str:
    emp = payload["empresa_id"]
    cond = ["p.empresa_id = :emp"]
    params = {"emp": emp, "lim": _limite(args)}

    if args.get("estado"):
        cond.append("p.estado = :estado")
        params["estado"] = args["estado"]
    if args.get("cliente"):
        cond.append("cl.razon_social ILIKE :cli")
        params["cli"] = _like(args["cliente"])

    sql = f"""
        SELECT p.nombre_proyecto, p.orden_trabajo, p.estado,
               cl.razon_social AS cliente,
               p.fecha_inicio, p.fecha_fin_estimada
          FROM proyecto p
          LEFT JOIN cliente cl ON cl.id = p.cliente_id
         WHERE {' AND '.join(cond)}
         ORDER BY p.created_at DESC
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_clientes(db, payload, args) -> str:
    emp = payload["empresa_id"]
    cond = ["empresa_id = :emp", "activo = true"]
    params = {"emp": emp, "lim": _limite(args)}
    if args.get("query"):
        cond.append("(razon_social ILIKE :q OR ruc ILIKE :q)")
        params["q"] = _like(args["query"])
    sql = f"""
        SELECT razon_social, ruc, contacto, telefono, email, direccion
          FROM cliente
         WHERE {' AND '.join(cond)}
         ORDER BY razon_social
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_proveedores(db, payload, args) -> str:
    emp = payload["empresa_id"]
    cond = ["empresa_id = :emp", "activo = true"]
    params = {"emp": emp, "lim": _limite(args)}
    if args.get("query"):
        cond.append("(razon_social ILIKE :q OR contacto ILIKE :q)")
        params["q"] = _like(args["query"])
    sql = f"""
        SELECT razon_social, ruc, contacto, telefono, email, direccion
          FROM proveedor
         WHERE {' AND '.join(cond)}
         ORDER BY razon_social
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_personal(db, payload, args) -> str:
    """Datos del personal — REQUIERE permiso empleados.ver (admin bypass)."""
    if not tiene_permiso(db, payload, "empleados", "ver"):
        return _err("El usuario no tiene permiso para consultar datos del personal.")
    emp = payload["empresa_id"]
    cond = ["e.empresa_id = :emp", "e.activo = true"]
    params = {"emp": emp, "lim": _limite(args)}
    if args.get("query"):
        cond.append("(u.nombre ILIKE :q OR u.apellido ILIKE :q OR e.cargo ILIKE :q)")
        params["q"] = _like(args["query"])
    if args.get("cargo"):
        cond.append("e.cargo ILIKE :cargo")
        params["cargo"] = _like(args["cargo"])

    sql = f"""
        SELECT TRIM(CONCAT(u.nombre, ' ', COALESCE(u.apellido, ''))) AS nombre,
               e.cargo, COALESCE(a.nombre, e.area) AS area, u.email, u.telefono,
               r.nombre AS rol
          FROM empleado e
          JOIN usuario u   ON u.id = e.usuario_id
          LEFT JOIN area a         ON a.id::text = e.area
          LEFT JOIN usuario_rol ur ON ur.usuario_id = u.id
          LEFT JOIN rol r          ON r.id = ur.rol_id
         WHERE {' AND '.join(cond)}
         ORDER BY nombre
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_consultar_asistencias(db, payload, args) -> str:
    """Registros de asistencia (entradas/salidas)."""
    emp = payload["empresa_id"]
    cond = ["ra.empresa_id = :emp"]
    params = {"emp": emp, "lim": _limite(args)}

    if args.get("empleado"):
        cond.append("(u.nombre ILIKE :nom OR u.apellido ILIKE :nom)")
        params["nom"] = _like(args["empleado"])
    if args.get("fecha_desde"):
        cond.append("ra.fecha_hora >= :desde")
        params["desde"] = args["fecha_desde"]
    if args.get("fecha_hasta"):
        cond.append("ra.fecha_hora <= :hasta")
        params["hasta"] = args["fecha_hasta"]

    sql = f"""
        SELECT TRIM(CONCAT(u.nombre, ' ', COALESCE(u.apellido, ''))) AS empleado,
               ra.tipo, ra.fecha_hora, ra.estado
          FROM registro_asistencia ra
          JOIN empleado e ON e.id = ra.empleado_id
          JOIN usuario  u ON u.id = e.usuario_id
         WHERE {' AND '.join(cond)}
         ORDER BY ra.fecha_hora DESC
         LIMIT :lim
    """
    return _ok(_filas(db, sql, params))


def _tool_resumen_general(db, payload, args) -> str:
    """Cifras agregadas de la empresa (un vistazo general)."""
    emp = payload["empresa_id"]
    sql = """
        SELECT
          (SELECT COUNT(*) FROM material WHERE empresa_id=:emp AND activo AND tipo='consumible')  AS materiales_consumibles,
          (SELECT COUNT(*) FROM material WHERE empresa_id=:emp AND activo AND tipo='herramienta') AS herramientas,
          (SELECT COUNT(*) FROM equipo WHERE empresa_id=:emp)                                     AS equipos_propios,
          (SELECT COUNT(*) FROM equipo_intervenido WHERE empresa_id=:emp AND activo)              AS equipos_intervenidos,
          (SELECT COUNT(*) FROM epp WHERE empresa_id=:emp AND activo)                             AS tipos_epp,
          (SELECT COUNT(*) FROM epp WHERE empresa_id=:emp AND activo AND stock_actual<=stock_min) AS epp_stock_bajo,
          (SELECT COUNT(*) FROM proyecto WHERE empresa_id=:emp)                                   AS proyectos,
          (SELECT COUNT(*) FROM cliente WHERE empresa_id=:emp AND activo)                         AS clientes,
          (SELECT COUNT(*) FROM proveedor WHERE empresa_id=:emp AND activo)                       AS proveedores,
          (SELECT COUNT(*) FROM empleado WHERE empresa_id=:emp AND activo)                        AS empleados
    """
    filas = _filas(db, sql, {"emp": emp})
    return json.dumps({"resumen": filas[0] if filas else {}}, default=str, ensure_ascii=False)


# ─────────────────────────── registro ───────────────────────────────────────

_DISPATCH = {
    "buscar_materiales": _tool_buscar_materiales,
    "consultar_equipos": _tool_consultar_equipos,
    "consultar_equipos_intervenidos": _tool_consultar_equipos_intervenidos,
    "consultar_epp": _tool_consultar_epp,
    "consultar_proyectos": _tool_consultar_proyectos,
    "consultar_clientes": _tool_consultar_clientes,
    "consultar_proveedores": _tool_consultar_proveedores,
    "consultar_personal": _tool_consultar_personal,
    "consultar_asistencias": _tool_consultar_asistencias,
    "resumen_general": _tool_resumen_general,
}


def ejecutar_tool(db: Session, payload: dict, nombre: str, args: dict | None) -> str:
    fn = _DISPATCH.get(nombre)
    if not fn:
        return _err(f"herramienta desconocida: {nombre}")
    try:
        return fn(db, payload, args or {})
    except Exception as e:  # noqa: BLE001 — devolver el error al modelo, no romper el request
        db.rollback()
        return _err(f"Error ejecutando {nombre}: {e}")


# Esquemas de herramientas que se envían a la API (JSON Schema).
TOOL_DEFS = [
    {
        "name": "buscar_materiales",
        "description": (
            "Busca materiales del inventario. 'tipo'='consumible' (cables, insumos) "
            "o 'herramienta' (martillos, llaves, etc.). Devuelve stock total y mínimo."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Texto a buscar en nombre o código"},
                "tipo": {"type": "string", "enum": ["consumible", "herramienta"]},
                "solo_stock_bajo": {"type": "boolean", "description": "Solo ítems con stock <= mínimo"},
                "limite": {"type": "integer", "description": "Máx. resultados (1-50)"},
            },
        },
    },
    {
        "name": "consultar_equipos",
        "description": (
            "Lista equipos PROPIOS de la empresa (activos electrónicos, PCs, "
            "herramientas tecnológicas). Incluye estado y datos de mantenimiento."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "estado": {"type": "string"},
                "requiere_mantenimiento": {"type": "boolean"},
                "limite": {"type": "integer"},
            },
        },
    },
    {
        "name": "consultar_equipos_intervenidos",
        "description": (
            "Lista equipos del CLIENTE que la empresa instala o mantiene (tableros, "
            "pozos a tierra, transformadores). Incluye cliente, ubicación, zona y proyecto."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "cliente": {"type": "string"},
                "estado": {"type": "string"},
                "limite": {"type": "integer"},
            },
        },
    },
    {
        "name": "consultar_epp",
        "description": "Consulta EPP (equipos de protección personal): stock actual, mínimo y precio.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "solo_stock_bajo": {"type": "boolean"},
                "limite": {"type": "integer"},
            },
        },
    },
    {
        "name": "consultar_proyectos",
        "description": "Lista proyectos/servicios y su cliente. Estados típicos: 'Pendiente', 'En_Proceso'.",
        "input_schema": {
            "type": "object",
            "properties": {
                "estado": {"type": "string"},
                "cliente": {"type": "string"},
                "limite": {"type": "integer"},
            },
        },
    },
    {
        "name": "consultar_clientes",
        "description": "Directorio de clientes de la empresa (razón social, RUC, contacto).",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string"}, "limite": {"type": "integer"}},
        },
    },
    {
        "name": "consultar_proveedores",
        "description": "Directorio de proveedores de la empresa (razón social, contacto, rubro).",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string"}, "limite": {"type": "integer"}},
        },
    },
    {
        "name": "consultar_personal",
        "description": (
            "Datos del personal (nombre, cargo, área, rol, contacto). "
            "Requiere permiso; si el usuario no lo tiene, devuelve un aviso."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "cargo": {"type": "string"},
                "limite": {"type": "integer"},
            },
        },
    },
    {
        "name": "consultar_asistencias",
        "description": (
            "Registros de asistencia (entradas/salidas). Filtra por empleado y/o rango "
            "de fechas (formato YYYY-MM-DD)."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "empleado": {"type": "string"},
                "fecha_desde": {"type": "string", "description": "YYYY-MM-DD"},
                "fecha_hasta": {"type": "string", "description": "YYYY-MM-DD"},
                "limite": {"type": "integer"},
            },
        },
    },
    {
        "name": "resumen_general",
        "description": (
            "Cifras agregadas de la empresa (conteos de materiales, herramientas, equipos, "
            "EPP, proyectos, clientes, proveedores, empleados). Úsalo para una visión general."
        ),
        "input_schema": {"type": "object", "properties": {}},
    },
]
