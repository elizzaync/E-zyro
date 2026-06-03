"""
Router: /analitica — Dashboards ejecutivos (solo lectura).
Agregaciones por dominio: operaciones, logística, personal, activos.
Gating: módulo 'reportes' acción 'ver' (admin/superadmin pasan automático).
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import tiene_permiso
from ..db.database import get_db

router = APIRouter(prefix="/analitica", tags=["analitica"])

_MESES = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun",
          "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]


def _puede_ver(db: Session, payload: dict) -> bool:
    return tiene_permiso(db, payload, "reportes", "ver")


def _rows(db: Session, sql: str, params: dict) -> List[tuple]:
    return list(db.execute(text(sql), params).fetchall())


def _lv(rows) -> List[Dict[str, Any]]:
    """Filas (label, value) → [{label, value}]."""
    return [{"label": str(r[0]) if r[0] is not None else "—", "value": int(r[1] or 0)} for r in rows]


def _mes_label(ym: str) -> str:
    """'2026-06' → 'Jun 26'."""
    try:
        y, m = ym.split("-")
        return f"{_MESES[int(m)]} {y[2:]}"
    except Exception:
        return ym


def _vacio() -> Dict[str, Any]:
    return {"sin_permiso": True}


# ════════════════════════════════════════════════════════════════════════════
# OPERACIONES Y SERVICIOS
# ════════════════════════════════════════════════════════════════════════════
@router.get("/operaciones")
def operaciones(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    if not _puede_ver(db, payload):
        return _vacio()
    e = payload["empresa_id"]
    p = {"e": e}

    proyectos_activos = db.execute(text(
        "SELECT COUNT(*) FROM proyecto WHERE empresa_id=:e AND estado='En_Proceso'"), p).scalar() or 0
    serv_total = db.execute(text(
        "SELECT COUNT(*) FROM proyecto_servicio WHERE empresa_id=:e"), p).scalar() or 0
    serv_comp = db.execute(text(
        "SELECT COUNT(*) FROM proyecto_servicio WHERE empresa_id=:e AND estado='Completado'"), p).scalar() or 0
    serv_pend = db.execute(text(
        "SELECT COUNT(*) FROM proyecto_servicio WHERE empresa_id=:e AND estado IN ('Pendiente','En_Proceso')"), p).scalar() or 0
    clientes = db.execute(text("SELECT COUNT(*) FROM cliente WHERE empresa_id=:e"), p).scalar() or 0
    tasa = round((serv_comp / serv_total) * 100) if serv_total else 0

    por_estado = _lv(_rows(db,
        "SELECT estado, COUNT(*) FROM proyecto_servicio WHERE empresa_id=:e GROUP BY estado ORDER BY 2 DESC", p))
    por_cliente = _lv(_rows(db, """
        SELECT c.razon_social, COUNT(ps.id)
        FROM proyecto_servicio ps
        JOIN proyecto p ON p.id = ps.proyecto_id
        JOIN cliente  c ON c.id = p.cliente_id
        WHERE ps.empresa_id=:e
        GROUP BY c.razon_social ORDER BY 2 DESC LIMIT 6""", p))
    tendencia_raw = _rows(db, """
        SELECT to_char(date_trunc('month', COALESCE(fecha_programada, created_at)), 'YYYY-MM') ym,
               COUNT(*) total,
               COUNT(*) FILTER (WHERE estado='Completado') comp
        FROM proyecto_servicio
        WHERE empresa_id=:e
          AND COALESCE(fecha_programada, created_at) >= (CURRENT_DATE - INTERVAL '6 months')
        GROUP BY 1 ORDER BY 1""", p)
    tendencia = [{"label": _mes_label(r[0]), "total": int(r[1] or 0), "completados": int(r[2] or 0)}
                 for r in tendencia_raw]

    return {
        "kpis": {
            "proyectos_activos": int(proyectos_activos),
            "servicios_total": int(serv_total),
            "servicios_completados": int(serv_comp),
            "servicios_pendientes": int(serv_pend),
            "clientes": int(clientes),
            "tasa_cumplimiento": tasa,
        },
        "servicios_por_estado": por_estado,
        "servicios_por_cliente": por_cliente,
        "tendencia_mensual": tendencia,
    }


# ════════════════════════════════════════════════════════════════════════════
# LOGÍSTICA E INVENTARIO
# ════════════════════════════════════════════════════════════════════════════
@router.get("/logistica")
def logistica(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    if not _puede_ver(db, payload):
        return _vacio()
    e = payload["empresa_id"]
    p = {"e": e}

    health = db.execute(text("""
        WITH sq AS (
          SELECT material_id, SUM(cantidad) total, MAX(cantidad_minima) minimo
          FROM stock WHERE empresa_id=:e GROUP BY material_id
        )
        SELECT
          COUNT(*) total_items,
          COUNT(*) FILTER (WHERE COALESCE(sq.total,0) > 0) con_stock,
          COUNT(*) FILTER (WHERE COALESCE(sq.total,0) <= 0) agotado,
          COUNT(*) FILTER (WHERE COALESCE(sq.total,0) > 0 AND COALESCE(sq.minimo,0) > 0
                           AND COALESCE(sq.total,0) <= COALESCE(sq.minimo,0)) bajo,
          COALESCE(SUM(COALESCE(sq.total,0)), 0) unidades
        FROM material m LEFT JOIN sq ON sq.material_id = m.id
        WHERE m.empresa_id=:e AND m.activo = true AND m.tipo='consumible'"""), p).fetchone()

    valor = db.execute(text("""
        SELECT COALESCE(SUM(s.cantidad * COALESCE(m.precio,0)), 0)
        FROM stock s JOIN material m ON m.id = s.material_id
        WHERE s.empresa_id=:e AND m.activo = true"""), p).scalar() or 0

    equipos = db.execute(text("SELECT COUNT(*) FROM equipo WHERE empresa_id=:e"), p).scalar() or 0

    top_categorias = _lv(_rows(db, """
        SELECT COALESCE(cm.nombre,'Sin categoría'), COUNT(*)
        FROM material m LEFT JOIN categoria_material cm ON cm.id = m.categoria_id
        WHERE m.empresa_id=:e AND m.activo = true AND m.tipo='consumible'
        GROUP BY 1 ORDER BY 2 DESC LIMIT 8""", p))

    clase_map = {"equipo": "Equipos", "herramienta": "Herramientas", "equipo_tecnologico": "Activos TI"}
    equipos_clase = [{"label": clase_map.get(r[0], r[0] or "—"), "value": int(r[1] or 0)}
                     for r in _rows(db, "SELECT clase, COUNT(*) FROM equipo WHERE empresa_id=:e GROUP BY clase ORDER BY 2 DESC", p)]

    top_stock = _lv(_rows(db, """
        WITH sq AS (SELECT material_id, SUM(cantidad) total FROM stock WHERE empresa_id=:e GROUP BY material_id)
        SELECT m.nombre, COALESCE(sq.total,0)
        FROM material m LEFT JOIN sq ON sq.material_id = m.id
        WHERE m.empresa_id=:e AND m.activo = true AND m.tipo='consumible' AND COALESCE(sq.total,0) > 0
        ORDER BY 2 DESC LIMIT 8""", p))

    return {
        "kpis": {
            "items": int(health[0] or 0),
            "con_stock": int(health[1] or 0),
            "agotado": int(health[2] or 0),
            "bajo": int(health[3] or 0),
            "unidades": int(health[4] or 0),
            "equipos": int(equipos),
            "valor": round(float(valor), 2),
        },
        "stock_health": [
            {"label": "Con stock", "value": int(health[1] or 0)},
            {"label": "Bajo mínimo", "value": int(health[3] or 0)},
            {"label": "Agotado", "value": int(health[2] or 0)},
        ],
        "top_categorias": top_categorias,
        "equipos_por_clase": equipos_clase,
        "top_stock": top_stock,
    }


# ════════════════════════════════════════════════════════════════════════════
# PERSONAL Y ASISTENCIA
# ════════════════════════════════════════════════════════════════════════════
def _es_uuid(s: str) -> bool:
    return isinstance(s, str) and len(s) == 36 and s.count("-") == 4


@router.get("/personal")
def personal(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    if not _puede_ver(db, payload):
        return _vacio()
    e = payload["empresa_id"]
    p = {"e": e}

    empleados = db.execute(text("SELECT COUNT(*) FROM empleado WHERE empresa_id=:e AND activo = true"), p).scalar() or 0

    # Asistencias del mes (días distintos con entrada) y promedio de registros/día
    asis_mes = db.execute(text("""
        SELECT COUNT(*) FROM registro_asistencia
        WHERE empresa_id=:e AND tipo='entrada'
          AND date_trunc('month', fecha_hora) = date_trunc('month', CURRENT_DATE)"""), p).scalar() or 0
    asis_total = db.execute(text("SELECT COUNT(*) FROM registro_asistencia WHERE empresa_id=:e"), p).scalar() or 0

    # Por área (limpiando valores UUID → 'Sin asignar')
    area_rows = _rows(db, """
        SELECT COALESCE(NULLIF(TRIM(area),''),'Sin asignar') a, COUNT(*)
        FROM empleado WHERE empresa_id=:e AND activo = true GROUP BY 1""", p)
    area_bucket: Dict[str, int] = {}
    for a, c in area_rows:
        key = "Sin asignar" if (a is None or _es_uuid(a)) else a
        area_bucket[key] = area_bucket.get(key, 0) + int(c or 0)
    por_area = sorted(
        [{"label": k, "value": v} for k, v in area_bucket.items()],
        key=lambda x: -x["value"])[:8]

    # Asistencia diaria (entradas) últimos 30 días
    diaria = [{"label": f"{r[0].day:02d}/{_MESES[r[0].month]}", "value": int(r[1] or 0)}
              for r in _rows(db, """
        SELECT fecha_hora::date d, COUNT(*)
        FROM registro_asistencia
        WHERE empresa_id=:e AND tipo='entrada' AND fecha_hora >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP BY 1 ORDER BY 1""", p)]

    # Top empleados por días asistidos este mes
    top = _lv(_rows(db, """
        SELECT TRIM(COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellido,'')) nom,
               COUNT(DISTINCT ra.fecha_hora::date)
        FROM registro_asistencia ra
        JOIN empleado e ON e.id = ra.empleado_id
        JOIN usuario  u ON u.id = e.usuario_id
        WHERE ra.empresa_id=:e AND ra.tipo='entrada'
          AND date_trunc('month', ra.fecha_hora) = date_trunc('month', CURRENT_DATE)
        GROUP BY nom ORDER BY 2 DESC LIMIT 8""", p))

    return {
        "kpis": {
            "empleados": int(empleados),
            "asistencias_mes": int(asis_mes),
            "asistencias_total": int(asis_total),
            "areas": len([k for k in area_bucket if k != "Sin asignar"]),
        },
        "por_area": por_area,
        "asistencia_diaria": diaria,
        "top_asistencia": top,
    }


# ════════════════════════════════════════════════════════════════════════════
# ACTIVOS Y MANTENIMIENTO
# ════════════════════════════════════════════════════════════════════════════
@router.get("/activos")
def activos(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    if not _puede_ver(db, payload):
        return _vacio()
    e = payload["empresa_id"]
    p = {"e": e}

    # ── Activos propios (tabla equipo): herramientas/equipos/activos TI ────────
    equipos = db.execute(text("SELECT COUNT(*) FROM equipo WHERE empresa_id=:e"), p).scalar() or 0
    operativos = db.execute(text("SELECT COUNT(*) FROM equipo WHERE empresa_id=:e AND estado='operativo'"), p).scalar() or 0
    mant = db.execute(text("SELECT COUNT(*) FROM equipo WHERE empresa_id=:e AND estado='en_mantenimiento'"), p).scalar() or 0
    fuera = db.execute(text("SELECT COUNT(*) FROM equipo WHERE empresa_id=:e AND estado IN ('fuera_de_servicio','baja')"), p).scalar() or 0
    # ── Servicio a clientes (tablas independientes) ────────────────────────────
    intervenidos = db.execute(text("SELECT COUNT(*) FROM equipo_intervenido WHERE empresa_id=:e"), p).scalar() or 0
    itse = db.execute(text("SELECT COUNT(*) FROM inspeccion_itse WHERE empresa_id=:e"), p).scalar() or 0
    epp_entregas = db.execute(text("SELECT COUNT(*) FROM epp_entrega WHERE empresa_id=:e"), p).scalar() or 0

    estado_map = {"operativo": "Operativo", "en_mantenimiento": "Mantenimiento",
                  "fuera_de_servicio": "Fuera de servicio", "baja": "Baja"}
    por_estado = [{"label": estado_map.get(r[0], r[0] or "—"), "value": int(r[1] or 0)}
                  for r in _rows(db, "SELECT estado, COUNT(*) FROM equipo WHERE empresa_id=:e GROUP BY estado ORDER BY 2 DESC", p)]

    clase_map = {"equipo": "Equipos", "herramienta": "Herramientas", "equipo_tecnologico": "Activos TI"}
    por_clase = [{"label": clase_map.get(r[0], r[0] or "—"), "value": int(r[1] or 0)}
                 for r in _rows(db, "SELECT clase, COUNT(*) FROM equipo WHERE empresa_id=:e GROUP BY clase ORDER BY 2 DESC", p)]

    # Equipos intervenidos clasificados por tipo (derivado del nombre)
    intervenidos_tipo = _lv(_rows(db, """
        SELECT CASE
            WHEN lower(nombre) LIKE '%ups%' THEN 'UPS'
            WHEN lower(nombre) LIKE '%trafo%' OR lower(nombre) LIKE '%transformador%' THEN 'Transformadores'
            WHEN lower(nombre) LIKE 'pt%' OR lower(nombre) LIKE '%pozo%' THEN 'Pozos a tierra'
            WHEN lower(nombre) LIKE 'td%' OR lower(nombre) LIKE 'tg%' OR lower(nombre) LIKE '%tablero%' THEN 'Tableros'
            ELSE 'Otros' END AS tipo,
          COUNT(*)
        FROM equipo_intervenido WHERE empresa_id=:e GROUP BY 1 ORDER BY 2 DESC""", p))

    itse_mes = [{"label": _mes_label(r[0]), "value": int(r[1] or 0)}
                for r in _rows(db, """
        SELECT to_char(date_trunc('month', fecha), 'YYYY-MM'), COUNT(*)
        FROM inspeccion_itse WHERE empresa_id=:e AND fecha IS NOT NULL
        GROUP BY 1 ORDER BY 1 LIMIT 12""", p)]

    return {
        "kpis": {
            "equipos": int(equipos),
            "operativos": int(operativos),
            "mantenimiento": int(mant),
            "fuera_servicio": int(fuera),
            "intervenidos": int(intervenidos),
            "itse": int(itse),
            "epp_entregas": int(epp_entregas),
        },
        "equipos_por_estado": por_estado,
        "equipos_por_clase": por_clase,
        "intervenidos_por_tipo": intervenidos_tipo,
        "itse_por_mes": itse_mes,
    }
