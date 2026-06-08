"""
Sembrado idempotente del catálogo de cuentas PCGE (Plan Contable General
Empresarial — Perú) por empresa. Fase 1 del módulo de finanzas.

Se llama desde `_run_migrations()` en main.py. Idempotente: verifica existencia
por (empresa_id, codigo) antes de insertar; ejecutarlo dos veces no duplica.

El catálogo aquí es un subconjunto operativo del PCGE: cubre todas las cuentas
referenciadas en la tabla de mapeo de la Fase 0 más la estructura de cada
elemento (clase). Cada empresa recibe su propia copia y puede desactivar (no
eliminar) las cuentas que no use. Para ampliar el catálogo basta agregar filas
a CATALOGO_PCGE — la jerarquía (padre) y el nivel (mayor/detalle) se derivan
automáticamente del código, no se mantienen a mano.

Derivaciones automáticas:
  - nivel    : una cuenta es 'detalle' (imputable) si es hoja — ninguna otra
               cuenta del catálogo la tiene como prefijo; si no, es 'mayor'.
  - padre    : el prefijo propio más largo presente en el catálogo.
  - naturaleza: se deriva del tipo, salvo override explícito (ej. la
               depreciación acumulada 39 es activo de naturaleza acreedora).
"""
from __future__ import annotations

import uuid
from sqlalchemy import text

# (codigo, nombre, tipo, naturaleza_override)
#   tipo: activo | pasivo | patrimonio | ingreso | gasto
#   naturaleza_override: None → se deriva del tipo (activo/gasto=deudora, resto=acreedora)
CATALOGO_PCGE: list[tuple[str, str, str, str | None]] = [
    # ── Elemento 1 — Activo disponible y exigible ────────────────────────────
    ("10", "Efectivo y equivalentes de efectivo", "activo", None),
    ("101", "Caja", "activo", None),
    ("104", "Cuentas corrientes en instituciones financieras", "activo", None),
    ("12", "Cuentas por cobrar comerciales - terceros", "activo", None),
    ("121", "Facturas, boletas y otros comprobantes por cobrar", "activo", None),
    ("16", "Cuentas por cobrar diversas - terceros", "activo", None),
    ("169", "Otras cuentas por cobrar diversas", "activo", None),
    # ── Elemento 2 — Activo realizable (existencias) ─────────────────────────
    ("20", "Mercaderías", "activo", None),
    ("201", "Mercaderías manufacturadas", "activo", None),
    ("25", "Materiales auxiliares, suministros y repuestos", "activo", None),
    ("252", "Suministros", "activo", None),
    # ── Elemento 3 — Activo inmovilizado ─────────────────────────────────────
    ("33", "Inmuebles, maquinaria y equipo", "activo", None),
    ("333", "Maquinarias y equipos de explotación", "activo", None),
    ("335", "Muebles y enseres", "activo", None),
    ("336", "Equipos diversos", "activo", None),
    ("39", "Depreciación, amortización y agotamiento acumulados", "activo", "acreedora"),
    ("391", "Depreciación acumulada", "activo", "acreedora"),
    # ── Elemento 4 — Pasivo ──────────────────────────────────────────────────
    ("40", "Tributos, contraprestaciones y aportes al sistema de pensiones y de salud por pagar", "pasivo", None),
    ("401", "Gobierno central", "pasivo", None),
    ("4011", "Impuesto general a las ventas", "pasivo", None),
    ("40111", "IGV - Cuenta propia", "pasivo", None),
    ("4017", "Impuesto a la renta", "pasivo", None),
    ("40171", "Renta de tercera categoría", "pasivo", None),
    ("40173", "Renta de quinta categoría", "pasivo", None),
    ("403", "Instituciones públicas", "pasivo", None),
    ("4031", "EsSalud", "pasivo", None),
    ("4032", "ONP", "pasivo", None),
    ("41", "Remuneraciones y participaciones por pagar", "pasivo", None),
    ("411", "Remuneraciones por pagar", "pasivo", None),
    ("42", "Cuentas por pagar comerciales - terceros", "pasivo", None),
    ("421", "Facturas, boletas y otros comprobantes por pagar", "pasivo", None),
    ("46", "Cuentas por pagar diversas - terceros", "pasivo", None),
    ("469", "Otras cuentas por pagar diversas", "pasivo", None),
    # ── Elemento 5 — Patrimonio ──────────────────────────────────────────────
    ("50", "Capital", "patrimonio", None),
    ("501", "Capital social", "patrimonio", None),
    ("59", "Resultados acumulados", "patrimonio", None),
    ("591", "Utilidades no distribuidas", "patrimonio", None),
    ("592", "Pérdidas acumuladas", "patrimonio", "deudora"),
    # ── Elemento 6 — Gastos por naturaleza ───────────────────────────────────
    ("60", "Compras", "gasto", None),
    ("601", "Mercaderías", "gasto", None),
    ("61", "Variación de existencias", "gasto", None),
    ("611", "Mercaderías", "gasto", None),
    ("62", "Gastos de personal, directores y gerentes", "gasto", None),
    ("621", "Remuneraciones", "gasto", None),
    ("627", "Seguridad, previsión social y otras contribuciones", "gasto", None),
    ("63", "Gastos de servicios prestados por terceros", "gasto", None),
    ("635", "Alquileres", "gasto", None),
    ("636", "Servicios básicos", "gasto", None),
    ("639", "Otros servicios prestados por terceros", "gasto", None),
    ("64", "Gastos por tributos", "gasto", None),
    ("641", "Gobierno central", "gasto", None),
    ("65", "Otros gastos de gestión", "gasto", None),
    ("659", "Otros gastos de gestión", "gasto", None),
    ("68", "Valuación y deterioro de activos y provisiones", "gasto", None),
    ("681", "Depreciación", "gasto", None),
    ("6814", "Depreciación de inmuebles, maquinaria y equipo - costo", "gasto", None),
    ("69", "Costo de ventas", "gasto", None),
    ("691", "Mercaderías", "gasto", None),
    # ── Elemento 7 — Ingresos ────────────────────────────────────────────────
    ("70", "Ventas", "ingreso", None),
    ("701", "Mercaderías", "ingreso", None),
    ("7011", "Mercaderías - terceros", "ingreso", None),
    ("75", "Otros ingresos de gestión", "ingreso", None),
    ("759", "Otros ingresos de gestión", "ingreso", None),
]


def _naturaleza(tipo: str, override: str | None) -> str:
    if override:
        return override
    return "deudora" if tipo in ("activo", "gasto") else "acreedora"


def _derivar_nivel_y_padre(codigos: list[str]) -> dict[str, tuple[str, str | None]]:
    """Para cada código devuelve (nivel, codigo_padre).

    - nivel 'detalle' si es hoja (nadie lo tiene como prefijo propio), si no 'mayor'.
    - padre = prefijo propio más largo presente en el catálogo (o None).
    """
    conjunto = set(codigos)
    resultado: dict[str, tuple[str, str | None]] = {}
    for c in codigos:
        es_hoja = not any(o != c and o.startswith(c) for o in conjunto)
        nivel = "detalle" if es_hoja else "mayor"
        padre = None
        for largo in range(len(c) - 1, 0, -1):
            posible = c[:largo]
            if posible in conjunto:
                padre = posible
                break
        resultado[c] = (nivel, padre)
    return resultado


def sembrar_pcge(conn) -> None:
    """Siembra el catálogo PCGE en TODAS las empresas que aún no lo tengan
    (idempotente por empresa_id + codigo). Resuelve la jerarquía padre/hijo."""
    codigos = [row[0] for row in CATALOGO_PCGE]
    meta = _derivar_nivel_y_padre(codigos)

    empresas = conn.execute(text("SELECT id::text FROM empresa")).fetchall()
    for (empresa_id,) in empresas:
        # 1) Insertar cuentas faltantes (sin padre todavía)
        for codigo, nombre, tipo, override in CATALOGO_PCGE:
            nivel, _padre = meta[codigo]
            conn.execute(
                text(
                    """
                    INSERT INTO cuenta_contable
                        (id, empresa_id, codigo, nombre, tipo, naturaleza, nivel, activo, created_at)
                    SELECT :id, :eid, :cod, :nom, :tipo, :nat, :niv, true, now()
                    WHERE NOT EXISTS (
                        SELECT 1 FROM cuenta_contable
                         WHERE empresa_id = :eid AND codigo = :cod
                    )
                    """
                ),
                {
                    "id": str(uuid.uuid4()), "eid": empresa_id, "cod": codigo,
                    "nom": nombre, "tipo": tipo, "nat": _naturaleza(tipo, override),
                    "niv": nivel,
                },
            )
        # 2) Resolver cuenta_padre_id por código (idempotente)
        for codigo in codigos:
            _nivel, padre = meta[codigo]
            if padre is None:
                continue
            conn.execute(
                text(
                    """
                    UPDATE cuenta_contable hijo
                       SET cuenta_padre_id = padre.id
                      FROM cuenta_contable padre
                     WHERE hijo.empresa_id = :eid AND hijo.codigo = :cod
                       AND padre.empresa_id = :eid AND padre.codigo = :padre_cod
                       AND (hijo.cuenta_padre_id IS NULL OR hijo.cuenta_padre_id <> padre.id)
                    """
                ),
                {"eid": empresa_id, "cod": codigo, "padre_cod": padre},
            )
