"""
Portal Cliente — endpoints de solo lectura para empresas externas (HU-22).
Aislamiento de datos: todos los queries filtran por empresa_id Y cliente_id
leídos EN VIVO desde la BD (no del JWT) para resistir JWTs obsoletos.
"""
from __future__ import annotations

from datetime import datetime, date
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from passlib.context import CryptContext
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token

router = APIRouter(prefix="/portal-cliente", tags=["Portal Cliente"])

_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")


# ── Dependencia de seguridad ──────────────────────────────────────────────────

def _requires_client(
    payload: dict  = Depends(verificar_token),
    db:     Session = Depends(get_db),
) -> dict:
    """
    Valida que el token pertenezca a un ClienteExterno activo y re-lee
    empresa_id / cliente_id desde la BD para neutralizar JWTs obsoletos
    (p.ej. generados antes de que el seed migrara al usuario de empresa).
    """
    rol = (payload.get("rol") or "").lower().replace(" ", "")
    if rol != "clienteexterno":
        raise HTTPException(status_code=403, detail="Acceso exclusivo del portal cliente.")

    usuario_id = payload.get("id")
    if not usuario_id:
        raise HTTPException(status_code=403, detail="Token malformado — sin usuario_id.")

    row = db.execute(text("""
        SELECT u.empresa_id::text AS empresa_id,
               pa.cliente_id::text AS cliente_id
        FROM   usuario       u
        JOIN   portal_acceso pa ON pa.usuario_id = u.id
        WHERE  u.id::text = :uid
          AND  u.activo   = true
    """), {"uid": str(usuario_id)}).fetchone()

    if not row:
        raise HTTPException(
            status_code=403,
            detail="Acceso denegado: usuario inactivo o sin portal_acceso configurado.",
        )

    # Sobrescribir los claims del JWT con los valores ACTUALES de la BD
    payload["empresa_id"] = row[0]
    payload["cliente_id"] = row[1]

    print(f"[portal] uid={usuario_id} empresa_id={row[0]} cliente_id={row[1]}")
    return payload


# ── Helpers ───────────────────────────────────────────────────────────────────

def _ctx(payload: dict) -> tuple[str, str]:
    return str(payload["empresa_id"]), str(payload["cliente_id"])


# ── 1. Dashboard KPIs ─────────────────────────────────────────────────────────

@router.get("/dashboard")
def portal_dashboard(
    payload: dict = Depends(_requires_client),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)
    hoy = date.today()
    mes_inicio = hoy.replace(day=1)

    # Proyectos activos
    activos = db.execute(text("""
        SELECT COUNT(*) FROM proyecto
        WHERE empresa_id = :eid AND cliente_id = :cid
          AND estado NOT IN ('completado','cancelado')
    """), {"eid": empresa_id, "cid": cliente_id}).scalar() or 0

    # Servicios completados este mes
    completados_mes = db.execute(text("""
        SELECT COUNT(*) FROM proyecto_servicio ps
        JOIN proyecto p ON p.id = ps.proyecto_id
        WHERE p.empresa_id = :eid AND p.cliente_id = :cid
          AND ps.estado = 'completado'
          AND ps.fecha_fin >= :inicio
    """), {"eid": empresa_id, "cid": cliente_id, "inicio": mes_inicio}).scalar() or 0

    # Próximos mantenimientos (próximos 30 días, no completados)
    proximos_rows = db.execute(text("""
        SELECT ps.id, ps.nombre, ps.fecha_programada, ps.estado, p.nombre_proyecto
        FROM proyecto_servicio ps
        JOIN proyecto p ON p.id = ps.proyecto_id
        WHERE p.empresa_id = :eid AND p.cliente_id = :cid
          AND ps.fecha_programada >= CURRENT_DATE
          AND ps.fecha_programada <= CURRENT_DATE + INTERVAL '30 days'
          AND ps.estado NOT IN ('completado','cancelado')
        ORDER BY ps.fecha_programada ASC
        LIMIT 10
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()

    proximos = [
        {
            "id":              str(r[0]),
            "nombre":          r[1],
            "fecha_programada": r[2].isoformat() if r[2] else None,
            "estado":          r[3],
            "proyecto":        r[4],
        }
        for r in proximos_rows
    ]

    return {
        "proyectos_activos":       int(activos),
        "completados_este_mes":    int(completados_mes),
        "proximos_mantenimientos": proximos,
    }


# ── 2. Lista de proyectos con % de avance ─────────────────────────────────────

@router.get("/proyectos")
def portal_proyectos(
    payload: dict = Depends(_requires_client),
    db: Session = Depends(get_db),
) -> list[dict[str, Any]]:
    empresa_id, cliente_id = _ctx(payload)

    rows = db.execute(text("""
        SELECT
            p.id,
            p.nombre_proyecto,
            p.estado,
            p.fecha_inicio,
            p.fecha_fin_estimada,
            COUNT(ps.id)                                                AS total_servicios,
            COUNT(ps.id) FILTER (WHERE LOWER(ps.estado) = 'completado') AS completados
        FROM proyecto p
        LEFT JOIN proyecto_servicio ps ON ps.proyecto_id = p.id
        WHERE p.empresa_id = :eid AND p.cliente_id = :cid
        GROUP BY p.id, p.nombre_proyecto, p.estado, p.fecha_inicio, p.fecha_fin_estimada
        ORDER BY p.created_at DESC
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()

    result = []
    for r in rows:
        total = int(r[5]) if r[5] else 0
        comp  = int(r[6]) if r[6] else 0
        pct   = round(comp / total * 100) if total > 0 else 0
        result.append({
            "id":                 str(r[0]),
            "nombre_proyecto":    r[1],
            "estado":             r[2],
            "fecha_inicio":       r[3].isoformat() if r[3] else None,
            "fecha_fin_estimada": r[4].isoformat() if r[4] else None,
            "total_servicios":    total,
            "servicios_completados": comp,
            "avance_pct":         pct,
        })
    return result


# ── 3. Detalle de un proyecto ─────────────────────────────────────────────────

@router.get("/proyecto/{proyecto_id}/detalles")
def portal_proyecto_detalle(
    proyecto_id: str,
    payload: dict  = Depends(_requires_client),
    db: Session    = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)

    proy = db.execute(text("""
        SELECT id, nombre_proyecto, estado, fecha_inicio, fecha_fin_estimada
        FROM proyecto
        WHERE id = :pid AND empresa_id = :eid AND cliente_id = :cid
    """), {"pid": proyecto_id, "eid": empresa_id, "cid": cliente_id}).fetchone()

    if not proy:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado.")

    # Servicios — cada uno con su % de avance y su equipo de trabajo propio
    servicios_rows = db.execute(text("""
        SELECT id, nombre, estado, fecha_programada, fecha_inicio, fecha_fin,
               lider_id, responsable_id, descripcion
        FROM proyecto_servicio
        WHERE proyecto_id = :pid
        ORDER BY orden ASC, COALESCE(fecha_programada, fecha_inicio), nombre
    """), {"pid": proyecto_id}).fetchall()

    # Avance por servicio: % de procedimientos (pasos fijos) completados
    prog_rows = db.execute(text("""
        SELECT pr.proyecto_servicio_id::text,
               COUNT(*)                                               AS total,
               COUNT(*) FILTER (WHERE LOWER(pr.estado) = 'completado') AS completos
        FROM procedimiento pr
        JOIN proyecto_servicio ps ON ps.id = pr.proyecto_servicio_id
        WHERE ps.proyecto_id = :pid
        GROUP BY pr.proyecto_servicio_id
    """), {"pid": proyecto_id}).fetchall()
    progreso_map = {
        r[0]: (round(r[2] / r[1] * 100) if r[1] else 0) for r in prog_rows
    }

    # Cronograma de actividades por servicio (solo lectura para el cliente)
    tareas_rows = db.execute(text("""
        SELECT t.proyecto_servicio_id::text,
               t.id::text, t.nombre, t.estado,
               t.fecha_inicio_tarea, t.fecha_limite,
               t.responsable_id::text, t.orden
        FROM tarea t
        JOIN proyecto_servicio ps ON ps.id = t.proyecto_servicio_id
        WHERE ps.proyecto_id = :pid
        ORDER BY t.orden ASC, t.fecha_inicio_tarea ASC NULLS LAST
    """), {"pid": proyecto_id}).fetchall()

    resp_por_svc: dict[str, list[str]] = {}
    for t in tareas_rows:
        if t[6] and t[6] not in resp_por_svc.setdefault(t[0], []):
            resp_por_svc[t[0]].append(t[6])

    # Pasos fijos (procedimientos) por servicio — alimentan el avance
    pasos_rows = db.execute(text("""
        SELECT pr.proyecto_servicio_id::text,
               pr.nombre, pr.estado, pr.orden
        FROM procedimiento pr
        JOIN proyecto_servicio ps ON ps.id = pr.proyecto_servicio_id
        WHERE ps.proyecto_id = :pid
        ORDER BY pr.orden ASC
    """), {"pid": proyecto_id}).fetchall()
    pasos_por_svc: dict[str, list[dict[str, Any]]] = {}
    for p in pasos_rows:
        pasos_por_svc.setdefault(p[0], []).append({
            "nombre": p[1] or "",
            "estado": (p[2] or "pendiente").lower(),
            "orden":  p[3] or 0,
        })

    # Datos de persona (nombre/cargo/foto) de todos los involucrados, en batch
    emp_ids: set[str] = set()
    for s in servicios_rows:
        if s[6]: emp_ids.add(str(s[6]))
        if s[7]: emp_ids.add(str(s[7]))
    for ids in resp_por_svc.values():
        emp_ids.update(ids)

    persona_map: dict[str, dict[str, Any]] = {}
    if emp_ids:
        persona_rows = db.execute(text("""
            SELECT e.id::text,
                   u.nombre,
                   COALESCE(u.apellido, '')        AS apellido,
                   e.cargo,
                   u.foto_url,
                   u.email,
                   u.telefono,
                   emp.razon_social                AS empresa
            FROM empleado e
            JOIN usuario u   ON u.id   = e.usuario_id
            LEFT JOIN empresa emp ON emp.id = u.empresa_id
            WHERE e.id::text = ANY(:ids)
        """), {"ids": list(emp_ids)}).fetchall()
        persona_map = {
            r[0]: {
                "id":       r[0],
                "nombre":   r[1] or "Sin nombre",
                "apellido": r[2] or "",
                "cargo":    r[3] or "Técnico",
                "foto_url": r[4],
                "email":    r[5],
                "telefono": r[6],
                "empresa":  r[7] or "",
            }
            for r in persona_rows
        }

    def _equipo_de(svc_row) -> list[dict[str, Any]]:
        """Solo asignados explícitos a ESTE servicio (nunca el creador del proyecto)."""
        out: list[dict[str, Any]] = []
        vistos: set[str] = set()

        def _push(emp_id, rol: str):
            eid = str(emp_id) if emp_id else None
            if not eid or eid in vistos:
                return
            p = persona_map.get(eid)
            if not p:
                return
            vistos.add(eid)
            out.append({**p, "rol": rol})

        _push(svc_row[6], "Líder del Servicio")
        _push(svc_row[7], "Técnico Líder")
        for eid in resp_por_svc.get(str(svc_row[0]), []):
            _push(eid, "Técnico")
        return out

    # Cronograma serializado por servicio (nombre del responsable resuelto)
    crono_por_svc: dict[str, list[dict[str, Any]]] = {}
    for t in tareas_rows:
        persona = persona_map.get(t[6]) if t[6] else None
        resp_nombre = f"{persona['nombre']} {persona['apellido']}".strip() if persona else None
        crono_por_svc.setdefault(t[0], []).append({
            "id":           t[1],
            "nombre":       t[2] or "",
            "estado":       (t[3] or "pendiente").lower(),
            "fecha_inicio": t[4].isoformat() if t[4] else None,
            "fecha_fin":    t[5].isoformat() if t[5] else None,
            "responsable":  resp_nombre,
        })

    servicios = []
    for s in servicios_rows:
        sid       = str(s[0])
        estado    = s[2] or "Pendiente"
        progreso  = 100 if estado.lower() == "completado" else progreso_map.get(sid, 0)
        servicios.append({
            "id":               sid,
            "nombre":           s[1],
            "descripcion":      s[8],
            "estado":           estado,
            "fecha_programada": s[3].isoformat() if s[3] else None,
            "fecha_inicio":     s[4].isoformat() if s[4] else None,
            "fecha_fin":        s[5].isoformat() if s[5] else None,
            "progreso":         progreso,
            "equipo":           _equipo_de(s),
            "cronograma":       crono_por_svc.get(sid, []),
            "pasos":            pasos_por_svc.get(sid, []),
        })

    # Avance del proyecto: promedio dinámico del avance real de sus servicios
    avance_proyecto = round(sum(x["progreso"] for x in servicios) / len(servicios)) if servicios else 0

    # Personal asignado (proyecto_miembro → empleado → usuario)
    personal_rows = db.execute(text("""
        SELECT DISTINCT
            e.id,
            u.nombre || ' ' || u.apellido AS nombre_completo,
            e.cargo,
            pm.rol_proyecto
        FROM proyecto_miembro pm
        JOIN empleado e ON e.id = pm.empleado_id
        JOIN usuario  u ON u.id = e.usuario_id
        WHERE pm.proyecto_id = :pid AND pm.activo = true
        ORDER BY nombre_completo
    """), {"pid": proyecto_id}).fetchall()

    personal = [
        {
            "id":           str(p[0]),
            "nombre":       p[1],
            "cargo":        p[2],
            "rol_proyecto": p[3],
        }
        for p in personal_rows
    ]

    # Equipos intervenidos (de la tabla equipo_intervenido ligada al cliente)
    equipos_rows = db.execute(text("""
        SELECT id, nombre, codigo, marca, modelo, estado
        FROM equipo_intervenido
        WHERE proyecto_id = :pid AND empresa_id = :eid AND cliente_id = :cid
        ORDER BY nombre
    """), {"pid": proyecto_id, "eid": empresa_id, "cid": cliente_id}).fetchall()

    equipos = [
        {
            "id":     str(eq[0]),
            "nombre": eq[1],
            "codigo": eq[2],
            "marca":  eq[3],
            "modelo": eq[4],
            "estado": eq[5],
        }
        for eq in equipos_rows
    ]

    return {
        "proyecto": {
            "id":                 str(proy[0]),
            "nombre_proyecto":    proy[1],
            "estado":             proy[2],
            "fecha_inicio":       proy[3].isoformat() if proy[3] else None,
            "fecha_fin_estimada": proy[4].isoformat() if proy[4] else None,
            "avance_pct":         avance_proyecto,
        },
        "servicios":  servicios,
        "personal":   personal,
        "equipos":    equipos,
    }


# ── 4. Documentos (informes PDF en Cloudinary) ───────────────────────────────

@router.get("/documentos")
def portal_documentos(
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> list[dict[str, Any]]:
    empresa_id, cliente_id = _ctx(payload)

    docs: list[dict[str, Any]] = []

    # ── Informes de ámbito cliente (los internos quedan fuera del portal) ─────
    rows = db.execute(text("""
        SELECT
            iser.id,
            iser.tipo,
            iser.titulo,
            iser.url,
            iser.fecha,
            iser.created_at,
            p.nombre_proyecto,
            ps.nombre AS servicio_nombre
        FROM informe_servicio iser
        JOIN proyecto_servicio ps ON ps.id = iser.servicio_id
        JOIN proyecto           p  ON p.id  = ps.proyecto_id
        WHERE iser.empresa_id = :eid AND p.cliente_id = :cid
          AND iser.ambito = 'cliente'
        ORDER BY iser.fecha DESC NULLS LAST, iser.created_at DESC
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()
    for r in rows:
        docs.append({
            "id":         str(r[0]),
            "tipo":       r[1],
            "titulo":     r[2],
            "url":        r[3],
            "fecha":      r[4].isoformat() if r[4] else None,
            "created_at": r[5].isoformat() if r[5] else None,
            "proyecto":   r[6],
            "servicio":   r[7],
        })

    # ── Cartas de garantía del cliente (descargables) ─────────────────────────
    gar_rows = db.execute(text("""
        SELECT
            cg.id,
            cg.documento_pdf_url,
            cg.vigencia_garantia,
            cg.created_at,
            p.nombre_proyecto,
            ps.nombre AS servicio_nombre
        FROM carta_garantia cg
        JOIN proyecto_servicio ps ON ps.id = cg.servicio_id
        JOIN proyecto           p  ON p.id  = ps.proyecto_id
        WHERE cg.empresa_id::text = :eid AND p.cliente_id::text = :cid
          AND cg.documento_pdf_url IS NOT NULL
        ORDER BY cg.created_at DESC
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()
    for r in gar_rows:
        servicio_nombre = r[5] or ""
        docs.append({
            "id":         str(r[0]),
            "tipo":       "garantia",
            "titulo":     f"Carta de garantía — {servicio_nombre}".strip(" —"),
            "url":        r[1],
            "fecha":      r[2].isoformat() if r[2] else (r[3].isoformat() if r[3] else None),
            "created_at": r[3].isoformat() if r[3] else None,
            "proyecto":   r[4],
            "servicio":   servicio_nombre or None,
        })

    docs.sort(key=lambda d: d.get("created_at") or "", reverse=True)
    return docs


# ── 5. KPIs de equipos intervenidos ──────────────────────────────────────────

# Estado efectivo: si el equipo sigue ligado a este servicio, usa el valor
# en vivo de equipo_intervenido; si fue re-asignado, usa el estado congelado
# en historial_mantenimiento.
_ESTADO_EFECTIVO = """
    CASE
        WHEN ei.proyecto_servicio_id = hm.servicio_id
        THEN COALESCE(ei.estado_intervencion, hm.estado)
        ELSE hm.estado
    END
"""

_HM_BASE_FROM = """
    FROM historial_mantenimiento hm
    JOIN equipo_intervenido ei ON ei.id = hm.equipo_id
    LEFT JOIN proyecto_servicio ps ON ps.id = hm.servicio_id
    LEFT JOIN proyecto          p  ON p.id  = ps.proyecto_id
    WHERE hm.empresa_id::text = :eid
      AND (
        ei.cliente_id::text = :cid
        OR (p.id IS NOT NULL AND p.cliente_id::text = :cid)
      )
"""

# Base WHERE para queries directas sobre equipo_intervenido (equipos sin
# historial_mantenimiento — p.ej. antes de ser asignados a un servicio).
_EI_BASE_WHERE = """
    FROM equipo_intervenido ei
    LEFT JOIN proyecto p ON p.id = ei.proyecto_id
    WHERE ei.empresa_id::text = :eid AND ei.activo = true
      AND (
        ei.cliente_id::text = :cid
        OR (ei.proyecto_id IS NOT NULL AND p.cliente_id::text = :cid)
      )
"""


@router.get("/dashboard/kpis")
def portal_kpis(
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)
    print(f"[portal_kpis] empresa_id={empresa_id} cliente_id={cliente_id}")

    params = {"eid": empresa_id, "cid": cliente_id}

    total = db.execute(text(f"SELECT COUNT(*) {_EI_BASE_WHERE}"), params).scalar() or 0

    completados = db.execute(text(f"""
        SELECT COUNT(*) {_EI_BASE_WHERE}
          AND COALESCE(ei.estado_intervencion, 'pendiente') = 'completado'
    """), params).scalar() or 0

    en_proceso = db.execute(text(f"""
        SELECT COUNT(*) {_EI_BASE_WHERE}
          AND COALESCE(ei.estado_intervencion, 'pendiente') = 'en_proceso'
    """), params).scalar() or 0

    proximos = db.execute(text(f"""
        SELECT COUNT(*) {_EI_BASE_WHERE}
          AND ei.proximo_mantenimiento BETWEEN CURRENT_DATE
                                          AND CURRENT_DATE + INTERVAL '30 days'
    """), params).scalar() or 0

    print(f"[portal_kpis] total={total} completados={completados} en_proceso={en_proceso} proximos={proximos}")

    return {
        "total_equipos":              int(total),
        "mantenimientos_completados": int(completados),
        "en_proceso":                 int(en_proceso),
        "proximos_30_dias":           int(proximos),
    }


# ── 5b. Analytics ejecutivo (Dashboard) ──────────────────────────────────────
# Sirve TODO el dashboard en una respuesta. Política: SOLO datos reales — sin
# deltas/sparklines (requieren snapshot_kpi_diario, inexistente) ni SLA/tiempo
# de respuesta (requieren tabla `correctivo`, inexistente en prod). Cada sección
# se calcula a partir de columnas verificadas como pobladas contra producción.

# Servicios del cliente: ps -> proyecto -> cliente. Estados en BD están
# capitalizados ('Completado'/'En_Proceso'/'Pendiente'): se normalizan con lower().
_PS_BASE_FROM = """
    FROM proyecto_servicio ps
    JOIN proyecto p ON p.id = ps.proyecto_id
    WHERE ps.empresa_id::text = :eid AND p.cliente_id::text = :cid
"""


@router.get("/analytics/ejecutivo")
def portal_analytics_ejecutivo(
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)
    params = {"eid": empresa_id, "cid": cliente_id}

    # ── Resumen de equipos (parque) ──────────────────────────────────────────
    total_eq = db.execute(text(f"SELECT COUNT(*) {_EI_BASE_WHERE}"), params).scalar() or 0

    parque_rows = db.execute(text(f"""
        SELECT COALESCE(ei.estado_intervencion, 'pendiente') AS est, COUNT(*)
        {_EI_BASE_WHERE}
        GROUP BY 1
    """), params).fetchall()
    parque = {r[0]: int(r[1]) for r in parque_rows}

    # Ventanas de próximo mantenimiento (criticidad)
    vent = db.execute(text(f"""
        SELECT
          COUNT(*) FILTER (WHERE ei.proximo_mantenimiento < CURRENT_DATE)                                   AS vencidos,
          COUNT(*) FILTER (WHERE ei.proximo_mantenimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + 30)        AS en_30d,
          COUNT(*) FILTER (WHERE ei.proximo_mantenimiento >  CURRENT_DATE + 30
                             AND ei.proximo_mantenimiento <= CURRENT_DATE + 90)                              AS en_90d,
          COUNT(*) FILTER (WHERE ei.proximo_mantenimiento >  CURRENT_DATE + 90)                              AS mas_90d,
          COUNT(*) FILTER (WHERE ei.proximo_mantenimiento IS NULL)                                           AS sin_fecha
        {_EI_BASE_WHERE}
    """), params).fetchone()

    # ── Distribución por sede (ubicación) ────────────────────────────────────
    sede_rows = db.execute(text(f"""
        SELECT COALESCE(u.nombre, 'Sin asignar') AS sede, u.region, COUNT(*) AS n
        FROM equipo_intervenido ei
        LEFT JOIN proyecto  p ON p.id = ei.proyecto_id
        LEFT JOIN ubicacion u ON u.id = ei.ubicacion_id
        WHERE ei.empresa_id::text = :eid AND ei.activo = true
          AND (ei.cliente_id::text = :cid
               OR (ei.proyecto_id IS NOT NULL AND p.cliente_id::text = :cid))
        GROUP BY u.nombre, u.region
        ORDER BY n DESC
    """), params).fetchall()

    # ── Servicios ────────────────────────────────────────────────────────────
    serv_rows = db.execute(text(f"""
        SELECT LOWER(COALESCE(ps.estado, 'pendiente')) AS est, COUNT(*) {_PS_BASE_FROM}
        GROUP BY 1
    """), params).fetchall()
    serv = {r[0]: int(r[1]) for r in serv_rows}
    serv_total = sum(serv.values())

    # Conformidades: 'En Espera' o NULL = pendiente
    conf_pend = db.execute(text(f"""
        SELECT COUNT(*) {_PS_BASE_FROM}
          AND (ps.nro_conformidad IS NULL OR TRIM(ps.nro_conformidad) = ''
               OR LOWER(ps.nro_conformidad) LIKE 'en espera%')
    """), params).scalar() or 0

    # ── Línea 12 meses: programados (fecha_programada) vs completados (fecha_fin) ─
    linea_rows = db.execute(text(f"""
        WITH meses AS (
          SELECT to_char(date_trunc('month', CURRENT_DATE) - (n || ' month')::interval, 'YYYY-MM') AS mes
          FROM generate_series(11, 0, -1) AS n
        )
        SELECT m.mes,
          (SELECT COUNT(*) {_PS_BASE_FROM}
             AND to_char(ps.fecha_programada, 'YYYY-MM') = m.mes)                       AS programados,
          (SELECT COUNT(*) {_PS_BASE_FROM}
             AND LOWER(ps.estado) = 'completado'
             AND to_char(ps.fecha_fin, 'YYYY-MM') = m.mes)                              AS completados
        FROM meses m
        ORDER BY m.mes
    """), params).fetchall()

    # ── Garantías por vencer (vigencia en ±, vía servicio del cliente) ───────
    gar_rows = db.execute(text("""
        SELECT cg.razon_social, cg.vigencia_garantia,
               (cg.documento_pdf_url IS NOT NULL) AS tiene_pdf
        FROM carta_garantia cg
        JOIN proyecto_servicio ps ON ps.id = cg.servicio_id
        JOIN proyecto p ON p.id = ps.proyecto_id
        WHERE cg.empresa_id::text = :eid AND p.cliente_id::text = :cid
          AND cg.vigencia_garantia IS NOT NULL
        ORDER BY cg.vigencia_garantia ASC
        LIMIT 50
    """), params).fetchall()

    # ── Inspecciones (heatmap por día de fecha_inicio) ───────────────────────
    insp_rows = db.execute(text("""
        SELECT to_char(hi.fecha_inicio, 'YYYY-MM-DD') AS dia, COUNT(*)
        FROM historial_inspeccion hi
        JOIN equipo_intervenido ei ON ei.id = hi.equipo_intervenido_id
        LEFT JOIN proyecto p ON p.id = ei.proyecto_id
        WHERE hi.empresa_id::text = :eid AND hi.fecha_inicio IS NOT NULL
          AND (ei.cliente_id::text = :cid
               OR (ei.proyecto_id IS NOT NULL AND p.cliente_id::text = :cid))
        GROUP BY 1 ORDER BY 1 DESC LIMIT 120
    """), params).fetchall()

    # ── ITSE (distribución por estado) ───────────────────────────────────────
    itse_rows = db.execute(text("""
        SELECT LOWER(COALESCE(estado, 'borrador')) AS est, COUNT(*)
        FROM inspeccion_itse
        WHERE empresa_id::text = :eid AND cliente_id::text = :cid
        GROUP BY 1
    """), params).fetchall()

    hoy = date.today()
    garantias = [
        {
            "razon_social": r[0],
            "vigencia":     r[1].isoformat() if r[1] else None,
            "vencida":      bool(r[1] and r[1] < hoy),
            "tiene_pdf":    bool(r[2]),
        }
        for r in gar_rows
    ]
    # Vigentes aún (no vencidas) = "por vencer / activas"
    gar_por_vencer = sum(1 for g in garantias if g["vigencia"] and not g["vencida"])

    return {
        "generado": datetime.utcnow().isoformat() + "Z",
        "nota": "Solo datos reales; sin deltas/tendencias ni SLA (requieren histórico y módulo correctivo no disponibles).",
        "resumen": {
            "total_equipos":            int(total_eq),
            "equipos_completados":      parque.get("completado", 0),
            "equipos_en_proceso":       parque.get("en_proceso", 0),
            "equipos_pendientes":       parque.get("pendiente", 0),
            "equipos_criticos":         int(vent[0] or 0),          # vencidos
            "proximos_30d":             int(vent[1] or 0),
            "proximos_90d":             int(vent[1] or 0) + int(vent[2] or 0),
            "servicios_total":          serv_total,
            "servicios_completados":    serv.get("completado", 0),
            "servicios_en_proceso":     serv.get("en_proceso", 0),
            "conformidades_pendientes": int(conf_pend),
            "garantias_por_vencer":     gar_por_vencer,
        },
        "parque_intervencion": [
            {"estado": k, "cantidad": v} for k, v in sorted(parque.items())
        ],
        "mantenimientos_ventana": {
            "vencidos":  int(vent[0] or 0),
            "en_30d":    int(vent[1] or 0),
            "en_90d":    int(vent[2] or 0),
            "mas_90d":   int(vent[3] or 0),
            "sin_fecha": int(vent[4] or 0),
        },
        "por_sede": [
            {"sede": r[0], "region": r[1], "cantidad": int(r[2])} for r in sede_rows
        ],
        "servicios_estado": [
            {"estado": k, "cantidad": v} for k, v in sorted(serv.items())
        ],
        "linea_12_meses": [
            {"mes": r[0], "programados": int(r[1]), "completados": int(r[2])}
            for r in linea_rows
        ],
        "garantias": garantias,
        "inspecciones_calendario": [
            {"fecha": r[0], "cantidad": int(r[1])} for r in insp_rows
        ],
        "itse": [
            {"estado": r[0], "cantidad": int(r[1])} for r in itse_rows
        ],
    }


# ── 6. Historial de mantenimientos (tabla detallada) ─────────────────────────
# Cada fila = un evento (equipo × servicio). La clave `id` es
# historial_mantenimiento.id, no equipo_intervenido.id, para que
# el Portal pueda acceder al contexto histórico exacto vía /mantenimiento/{id}.

@router.get("/equipos/historial")
def portal_equipos_historial(
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> list[dict[str, Any]]:
    empresa_id, cliente_id = _ctx(payload)

    rows = db.execute(text("""
        SELECT
            ei.id,
            ei.nombre,
            ei.codigo,
            ei.marca,
            ei.modelo,
            ei.ubicacion_referencia,
            ei.estado,
            COALESCE(ei.estado_intervencion, 'pendiente')  AS estado_intervencion,
            ei.ultimo_mantenimiento,
            ei.proximo_mantenimiento,
            ei.frecuencia_meses,
            p.nombre_proyecto,
            ps.nombre           AS servicio_nombre,
            ps.estado           AS servicio_estado
        FROM equipo_intervenido ei
        LEFT JOIN proyecto_servicio ps ON ps.id = ei.proyecto_servicio_id
        LEFT JOIN proyecto p ON p.id = COALESCE(ps.proyecto_id, ei.proyecto_id)
        WHERE ei.empresa_id::text = :eid AND ei.activo = true
          AND (
            ei.cliente_id::text = :cid
            OR (p.id IS NOT NULL AND p.cliente_id::text = :cid)
          )
        ORDER BY ei.created_at DESC
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()

    print(f"[portal_historial] empresa={empresa_id[:8]} cliente={cliente_id[:8]} rows={len(rows)}")

    return [
        {
            "id":                    str(r[0]),
            "nombre":                r[1],
            "codigo":                r[2],
            "marca":                 r[3],
            "modelo":                r[4],
            "ubicacion":             r[5],
            "estado":                r[6],
            "estado_intervencion":   r[7],
            "ultimo_mantenimiento":  r[8].isoformat() if r[8] else None,
            "proximo_mantenimiento": r[9].isoformat() if r[9] else None,
            "frecuencia_meses":      r[10],
            "proyecto":              r[11],
            "servicio":              r[12],
            "servicio_estado":       r[13],
        }
        for r in rows
    ]


# ── 7. Detalle de un evento de mantenimiento ─────────────────────────────────
# El parámetro :hm_id es historial_mantenimiento.id (NO equipo_intervenido.id).
# El contexto del servicio (personal, herramientas, etc.) proviene del servicio
# registrado en historial_mantenimiento.servicio_id, no del servicio actual del
# equipo (que puede haber cambiado). Esto preserva el historial correcto.

@router.get("/mantenimiento/{hm_id}/detalles")
def portal_mantenimiento_detalles(
    hm_id:   str,
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)

    # ── Paso 1: resolver equipo_id + servicio_id ─────────────────────────────
    # Primero intenta como historial_mantenimiento.id (compatibilidad futura).
    # Si no existe, lo trata como equipo_intervenido.id (ruta normal actual).
    hm_row = db.execute(text("""
        SELECT
            hm.equipo_id::text   AS equipo_id,
            hm.servicio_id::text AS servicio_id,
            hm.estado            AS hm_estado
        FROM historial_mantenimiento hm
        JOIN equipo_intervenido ei ON ei.id = hm.equipo_id
        LEFT JOIN proyecto_servicio ps ON ps.id = hm.servicio_id
        LEFT JOIN proyecto          p  ON p.id  = ps.proyecto_id
        WHERE hm.id::text = :hmid AND hm.empresa_id::text = :eid
          AND (
            ei.cliente_id::text = :cid
            OR (p.id IS NOT NULL AND p.cliente_id::text = :cid)
          )
    """), {"hmid": hm_id, "eid": empresa_id, "cid": cliente_id}).fetchone()

    if hm_row:
        ei_id_str = hm_row[0]
        ps_id_str = hm_row[1]
        hm_estado = hm_row[2]
    else:
        # Fallback: hm_id es equipo_intervenido.id (equipos sin servicio asignado)
        ei_row = db.execute(text("""
            SELECT
                ei.id::text,
                ei.proyecto_servicio_id::text,
                COALESCE(ei.estado_intervencion, 'pendiente')
            FROM equipo_intervenido ei
            LEFT JOIN proyecto p ON p.id = ei.proyecto_id
            WHERE ei.id::text = :eiid AND ei.empresa_id::text = :eid
              AND (
                ei.cliente_id::text = :cid
                OR (ei.proyecto_id IS NOT NULL AND p.cliente_id::text = :cid)
              )
        """), {"eiid": hm_id, "eid": empresa_id, "cid": cliente_id}).fetchone()

        if not ei_row:
            raise HTTPException(status_code=404, detail="Registro no encontrado.")

        ei_id_str = ei_row[0]
        ps_id_str = ei_row[1]
        hm_estado = ei_row[2]

    print(f"[portal_detalle] id={hm_id[:8]} ei={ei_id_str[:8]} ps={ps_id_str[:8] if ps_id_str else None}")

    # ── Paso 2: equipo + servicio histórico + proyecto ────────────────────────
    row = db.execute(text("""
        SELECT
            ei.id,
            ei.nombre,
            ei.codigo,
            ei.marca,
            ei.modelo,
            ei.ubicacion_referencia,
            ei.estado,
            CASE
                WHEN ei.proyecto_servicio_id = ps.id
                THEN COALESCE(ei.estado_intervencion, :hm_estado)
                ELSE :hm_estado
            END                      AS estado_intervencion,
            ei.ultimo_mantenimiento,
            ei.proximo_mantenimiento,
            ei.frecuencia_meses,
            ei.observaciones,
            ps.proyecto_id,
            -- Proyecto
            p.nombre_proyecto,
            p.orden_trabajo,
            p.fecha_inicio           AS proj_inicio,
            p.fecha_fin_estimada     AS proj_fin_est,
            -- Servicio
            ps.nombre                AS serv_nombre,
            ps.estado                AS serv_estado,
            ps.fecha_programada,
            ps.fecha_inicio          AS serv_inicio,
            ps.fecha_fin             AS serv_fin,
            ps.zona_ejecucion,
            ps.alcance,
            ps.lider_id,
            ps.responsable_id
        FROM equipo_intervenido ei
        LEFT JOIN proyecto_servicio ps ON ps.id::text = :psid
        LEFT JOIN proyecto          p  ON p.id  = ps.proyecto_id
        WHERE ei.id::text = :eiid AND ei.empresa_id::text = :eid
    """), {
        "eiid":     ei_id_str,
        "psid":     ps_id_str,
        "eid":      empresa_id,
        "hm_estado": hm_estado,
    }).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Equipo no encontrado.")

    (
        ei_id_db, nombre, codigo, marca, modelo,
        ubicacion, estado, estado_interv,
        ult_mant, prox_mant, frec, obs,
        proyecto_id, nombre_proyecto, orden_trabajo, proj_inicio, proj_fin_est,
        serv_nombre, serv_estado, serv_fecha_prog, serv_inicio, serv_fin,
        zona_ejecucion, alcance, lider_id, responsable_id,
    ) = row

    ps_id = ps_id_str

    # ── Personal técnico: líderes del servicio + miembros del proyecto ────────
    personal: list[dict] = []
    seen_ids: set = set()

    if ps_id:
        # Líderes definidos directamente en el servicio
        for sql, rol_label in [
            ("SELECT e.id, u.nombre, u.apellido, e.cargo FROM proyecto_servicio ps "
             "JOIN empleado e ON e.id = ps.lider_id "
             "JOIN usuario  u ON u.id = e.usuario_id "
             "WHERE ps.id = :psid AND ps.lider_id IS NOT NULL",
             "Líder del Servicio"),
            ("SELECT e.id, u.nombre, u.apellido, e.cargo FROM proyecto_servicio ps "
             "JOIN empleado e ON e.id = ps.responsable_id "
             "JOIN usuario  u ON u.id = e.usuario_id "
             "WHERE ps.id = :psid AND ps.responsable_id IS NOT NULL",
             "Técnico Responsable"),
        ]:
            r = db.execute(text(sql), {"psid": str(ps_id)}).fetchone()
            if r and str(r[0]) not in seen_ids:
                seen_ids.add(str(r[0]))
                personal.append({
                    "nombre": f"{r[1]} {r[2]}".strip(),
                    "cargo":  r[3] or "—",
                    "rol":    rol_label,
                })

    if proyecto_id:
        # Miembros activos del proyecto
        mbr_rows = db.execute(text("""
            SELECT DISTINCT
                e.id,
                u.nombre || ' ' || u.apellido AS nombre_completo,
                e.cargo,
                COALESCE(pm.rol_proyecto, 'Técnico') AS rol_proy
            FROM proyecto_miembro pm
            JOIN empleado e ON e.id = pm.empleado_id
            JOIN usuario  u ON u.id = e.usuario_id
            WHERE pm.proyecto_id = :pid AND pm.activo = true
            ORDER BY nombre_completo
        """), {"pid": str(proyecto_id)}).fetchall()

        for r in mbr_rows:
            if str(r[0]) not in seen_ids:
                seen_ids.add(str(r[0]))
                personal.append({"nombre": r[1], "cargo": r[2] or "—", "rol": r[3]})

    # ── Herramientas / Equipos utilizados (préstamos del servicio) ────────────
    herramientas: list[dict] = []
    if ps_id:
        hrows = db.execute(text("""
            SELECT
                eq.id,
                eq.nombre,
                COALESCE(eq.codigo, '')          AS codigo,
                COALESCE(eq.marca,  '')          AS marca,
                COALESCE(eq.modelo, '')          AS modelo,
                eq.clase,
                COALESCE(pi2.cantidad_entregada,
                         pi2.cantidad_solicitada, 1) AS cantidad,
                cal.fecha_proxima                AS cal_fecha_prox,
                cal.empresa_responsable          AS cal_empresa,
                cal.observacion                  AS cal_obs
            FROM prestamo pr
            JOIN prestamo_item pi2 ON pi2.prestamo_id   = pr.id
            JOIN equipo        eq  ON eq.id             = pi2.equipo_id
            LEFT JOIN LATERAL (
                SELECT fecha_proxima, empresa_responsable, observacion
                FROM   calibracion
                WHERE  equipo_id = eq.id
                ORDER  BY created_at DESC
                LIMIT  1
            ) cal ON true
            WHERE pr.proyecto_servicio_id = :psid
              AND pr.estado IN ('entregado', 'devuelto', 'confirmado')
            ORDER BY eq.clase, eq.nombre
        """), {"psid": str(ps_id)}).fetchall()

        today = date.today()
        for h in hrows:
            cal_prox  = h[7]
            cal_emp   = h[8] or ""
            cal_obs   = h[9] or ""
            especificacion = None

            if cal_prox:
                dias = (cal_prox - today).days
                sufijo = f" — {cal_emp}" if cal_emp else ""
                if dias < 0:
                    especificacion = f"⚠ Calibración vencida ({cal_prox.strftime('%d/%m/%Y')}){sufijo}"
                elif dias <= 30:
                    especificacion = f"⏳ Próxima a vencer ({cal_prox.strftime('%d/%m/%Y')}){sufijo}"
                else:
                    especificacion = f"✓ Calibrado vigente hasta {cal_prox.strftime('%d/%m/%Y')}{sufijo}"
            elif cal_obs:
                especificacion = cal_obs

            herramientas.append({
                "nombre":         h[1],
                "codigo":         h[2],
                "marca":          h[3],
                "modelo":         h[4],
                "tipo":           h[5],
                "cantidad":       int(h[6]) if h[6] else 1,
                "especificacion": especificacion,
            })

    # ── Documentos: informes + cartas de garantía ─────────────────────────────
    documentos: list[dict] = []
    if ps_id:
        inf_rows = db.execute(text("""
            SELECT tipo, titulo, url, fecha
            FROM   informe_servicio
            WHERE  servicio_id = :psid AND empresa_id = :eid
              AND  url IS NOT NULL
            ORDER BY fecha DESC NULLS LAST, created_at DESC
        """), {"psid": str(ps_id), "eid": empresa_id}).fetchall()

        for d in inf_rows:
            titulo = d[1] or ("Pre-Informe de Servicio" if d[0] == "pre" else "Informe Final de Servicio")
            documentos.append({
                "tipo":   d[0],
                "titulo": titulo,
                "url":    d[2],
                "fecha":  d[3].isoformat() if d[3] else None,
            })

        gar_rows = db.execute(text("""
            SELECT documento_pdf_url, created_at::date AS fecha
            FROM   carta_garantia
            WHERE  servicio_id = :psid AND empresa_id = :eid
              AND  documento_pdf_url IS NOT NULL
            ORDER BY created_at DESC
        """), {"psid": str(ps_id), "eid": empresa_id}).fetchall()

        for g in gar_rows:
            documentos.append({
                "tipo":   "garantia",
                "titulo": "Carta de Garantía",
                "url":    g[0],
                "fecha":  g[1].isoformat() if g[1] else None,
            })

    # ── Historial de ciclos de mantenimiento completados ─────────────────────
    hist_rows = db.execute(text("""
        SELECT
            hi.id,
            hi.fecha_inicio,
            hi.fecha_fin,
            hi.proxima_fecha_mantenimiento,
            hi.observaciones,
            ps2.nombre         AS serv_nombre,
            ps2.estado         AS serv_estado,
            ps2.fecha_inicio   AS serv_fi,
            ps2.fecha_fin      AS serv_ff,
            p2.nombre_proyecto,
            p2.orden_trabajo
        FROM historial_inspeccion hi
        LEFT JOIN proyecto_servicio ps2 ON ps2.id = hi.proyecto_servicio_id
        LEFT JOIN proyecto          p2  ON p2.id  = ps2.proyecto_id
        WHERE hi.equipo_intervenido_id = :eiid
          AND hi.empresa_id            = :eid
          AND hi.estado                = 'completado'
        ORDER BY hi.fecha_fin DESC NULLS LAST, hi.created_at DESC
        LIMIT 20
    """), {"eiid": str(ei_id_db), "eid": empresa_id}).fetchall()

    historial: list[dict] = []
    for h in hist_rows:
        fi = h[7]   # serv fecha_inicio
        ff = h[8]   # serv fecha_fin
        duracion_dias = None
        if fi and ff:
            try:
                d_fi = fi.date() if hasattr(fi, "date") else fi
                d_ff = ff.date() if hasattr(ff, "date") else ff
                duracion_dias = (d_ff - d_fi).days
            except Exception:
                pass
        historial.append({
            "id":             str(h[0]),
            "fecha_inicio":   h[1].isoformat() if h[1] else None,
            "fecha_fin":      h[2].isoformat() if h[2] else None,
            "proxima_fecha":  h[3].isoformat() if h[3] else None,
            "observaciones":  h[4] or None,
            "servicio":       h[5] or "—",
            "serv_estado":    h[6] or None,
            "duracion_dias":  duracion_dias,
            "proyecto":       h[9] or "—",
            "orden_trabajo":  h[10] or None,
        })

    # ── Duración del servicio actual ─────────────────────────────────────────
    duracion_actual = None
    if serv_inicio and serv_fin:
        try:
            d_i = serv_inicio.date() if hasattr(serv_inicio, "date") else serv_inicio
            d_f = serv_fin.date()    if hasattr(serv_fin,    "date") else serv_fin
            duracion_actual = (d_f - d_i).days
        except Exception:
            pass

    return {
        "equipo": {
            "id":                    str(ei_id_db),
            "nombre":                nombre,
            "codigo":                codigo,
            "marca":                 marca,
            "modelo":                modelo,
            "ubicacion":             ubicacion,
            "estado":                estado,
            "estado_intervencion":   estado_interv,
            "ultimo_mantenimiento":  ult_mant.isoformat() if ult_mant else None,
            "proximo_mantenimiento": prox_mant.isoformat() if prox_mant else None,
            "frecuencia_meses":      frec,
            "observaciones":         obs,
        },
        "proyecto": {
            "nombre":        nombre_proyecto,
            "orden_trabajo": orden_trabajo,
            "fecha_inicio":  proj_inicio.isoformat() if proj_inicio else None,
            "fecha_fin_est": proj_fin_est.isoformat() if proj_fin_est else None,
        },
        "servicio": {
            "nombre":           serv_nombre,
            "estado":           serv_estado,
            "fecha_programada": serv_fecha_prog.isoformat() if serv_fecha_prog else None,
            "fecha_inicio":     serv_inicio.isoformat() if serv_inicio else None,
            "fecha_fin":        serv_fin.isoformat() if serv_fin else None,
            "zona_ejecucion":   zona_ejecucion,
            "alcance":          alcance,
            "duracion_dias":    duracion_actual,
        },
        "personal":     personal,
        "herramientas": herramientas,
        "documentos":   documentos,
        "historial":    historial,
    }


# ── 8. Cambio de contraseña ──────────────────────────────────────────────────
# Necesario porque los usuarios portal nacen con contraseña temporal y su email
# es sintético (@portal.e-zyro): la recuperación por correo no les sirve.

class CambioPasswordBody(BaseModel):
    password_actual: str
    password_nueva: str


@router.post("/cambiar-password")
def portal_cambiar_password(
    body: CambioPasswordBody,
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    if len(body.password_nueva) < 8:
        raise HTTPException(
            status_code=422,
            detail="La nueva contraseña debe tener al menos 8 caracteres.",
        )
    if body.password_nueva == body.password_actual:
        raise HTTPException(
            status_code=422,
            detail="La nueva contraseña debe ser distinta de la actual.",
        )

    usuario_id = str(payload.get("id"))
    row = db.execute(text(
        "SELECT password_hash FROM usuario WHERE id::text = :uid AND activo = true"
    ), {"uid": usuario_id}).fetchone()
    if not row or not _pwd.verify(body.password_actual, row[0]):
        raise HTTPException(status_code=401, detail="La contraseña actual no es correcta.")

    db.execute(text(
        "UPDATE usuario SET password_hash = :pwd, debe_cambiar_password = false "
        "WHERE id::text = :uid"
    ), {"pwd": _pwd.hash(body.password_nueva), "uid": usuario_id})
    db.commit()
    return {"ok": True}


# ── 9. Perfil del usuario portal ─────────────────────────────────────────────

@router.get("/perfil")
def portal_perfil(
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, _cliente_id = _ctx(payload)
    usuario_id = payload.get("id")

    row = db.execute(text("""
        SELECT
            u.id, u.nombre, u.apellido, u.email,
            COALESCE(u.telefono, '')    AS telefono,
            COALESCE(u.foto_url, '')    AS foto_url,
            u.created_at,
            e.razon_social, e.ruc,
            COALESCE(e.email_contacto, '') AS empresa_email,
            COALESCE(u.debe_cambiar_password, false) AS debe_cambiar_password
        FROM usuario u
        JOIN empresa e ON e.id = u.empresa_id
        WHERE u.id = :uid AND u.empresa_id = :eid
    """), {"uid": usuario_id, "eid": empresa_id}).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")

    meses = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
             "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
    fecha_txt = ""
    if row[6]:
        dt = row[6]
        fecha_txt = f"{dt.day} de {meses[dt.month]}, {dt.year}"

    return {
        "id":            str(row[0]),
        "nombre":        row[1] or "",
        "apellido":      row[2] or "",
        "correo":        row[3] or "",
        "telefono":      row[4],
        "fotoUrl":       row[5],
        "fechaCreacion": fecha_txt,
        "empresa":       row[7] or "",
        "ruc":           row[8] or "",
        "rol":           payload.get("rol", "ClienteExterno"),
        "empresaEmail":  row[9],
        "debeCambiarPassword": bool(row[10]),
    }
