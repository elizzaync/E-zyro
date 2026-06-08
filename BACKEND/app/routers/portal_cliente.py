"""
Portal Cliente — endpoints de solo lectura para empresas externas (HU-22).
Aislamiento de datos: todos los queries filtran por empresa_id Y cliente_id
del token JWT, que se inyecta en el login si el rol es ClienteExterno.
"""
from __future__ import annotations

from datetime import datetime, date
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token

router = APIRouter(prefix="/portal-cliente", tags=["Portal Cliente"])


# ── Dependencia de seguridad ──────────────────────────────────────────────────

def _requires_client(payload: dict = Depends(verificar_token)) -> dict:
    """Bloquea todo acceso que no provenga de un usuario ClienteExterno."""
    rol = (payload.get("rol") or "").lower().replace(" ", "")
    if rol != "clienteexterno":
        raise HTTPException(status_code=403, detail="Acceso exclusivo del portal cliente.")
    if not payload.get("cliente_id"):
        raise HTTPException(status_code=403, detail="Token sin cliente_id — contacte soporte.")
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
            COUNT(ps.id) FILTER (WHERE ps.estado = 'completado')        AS completados
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

    # Servicios
    servicios_rows = db.execute(text("""
        SELECT id, nombre, estado, fecha_programada, fecha_inicio, fecha_fin
        FROM proyecto_servicio
        WHERE proyecto_id = :pid
        ORDER BY COALESCE(fecha_programada, fecha_inicio), nombre
    """), {"pid": proyecto_id}).fetchall()

    total = len(servicios_rows)
    comp  = sum(1 for s in servicios_rows if s[2] == "completado")

    servicios = [
        {
            "id":               str(s[0]),
            "nombre":           s[1],
            "estado":           s[2],
            "fecha_programada": s[3].isoformat() if s[3] else None,
            "fecha_inicio":     s[4].isoformat() if s[4] else None,
            "fecha_fin":        s[5].isoformat() if s[5] else None,
        }
        for s in servicios_rows
    ]

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
            "avance_pct":         round(comp / total * 100) if total > 0 else 0,
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
        ORDER BY iser.fecha DESC NULLS LAST, iser.created_at DESC
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()

    return [
        {
            "id":              str(r[0]),
            "tipo":            r[1],
            "titulo":          r[2],
            "url":             r[3],
            "fecha":           r[4].isoformat() if r[4] else None,
            "created_at":      r[5].isoformat() if r[5] else None,
            "proyecto":        r[6],
            "servicio":        r[7],
        }
        for r in rows
    ]


# ── 5. KPIs de equipos intervenidos ──────────────────────────────────────────

@router.get("/dashboard/kpis")
def portal_kpis(
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)

    total = db.execute(text("""
        SELECT COUNT(*) FROM equipo_intervenido
        WHERE empresa_id = :eid AND cliente_id = :cid AND activo = true
    """), {"eid": empresa_id, "cid": cliente_id}).scalar() or 0

    completados = db.execute(text("""
        SELECT COUNT(*) FROM equipo_intervenido
        WHERE empresa_id = :eid AND cliente_id = :cid
          AND estado_intervencion = 'completado'
    """), {"eid": empresa_id, "cid": cliente_id}).scalar() or 0

    en_proceso = db.execute(text("""
        SELECT COUNT(*) FROM equipo_intervenido
        WHERE empresa_id = :eid AND cliente_id = :cid
          AND estado_intervencion = 'en_proceso'
    """), {"eid": empresa_id, "cid": cliente_id}).scalar() or 0

    proximos = db.execute(text("""
        SELECT COUNT(*) FROM equipo_intervenido
        WHERE empresa_id = :eid AND cliente_id = :cid
          AND proximo_mantenimiento BETWEEN CURRENT_DATE
                                        AND CURRENT_DATE + INTERVAL '30 days'
          AND activo = true
    """), {"eid": empresa_id, "cid": cliente_id}).scalar() or 0

    return {
        "total_equipos":              int(total),
        "mantenimientos_completados": int(completados),
        "en_proceso":                 int(en_proceso),
        "proximos_30_dias":           int(proximos),
    }


# ── 6. Historial de equipos intervenidos (tabla detallada) ───────────────────

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
            ei.estado_intervencion,
            ei.ultimo_mantenimiento,
            ei.proximo_mantenimiento,
            ei.frecuencia_meses,
            p.nombre_proyecto,
            ps.nombre  AS servicio_nombre,
            ps.estado  AS servicio_estado
        FROM equipo_intervenido ei
        LEFT JOIN proyecto         p  ON p.id  = ei.proyecto_id
        LEFT JOIN proyecto_servicio ps ON ps.id = ei.proyecto_servicio_id
        WHERE ei.empresa_id = :eid AND ei.cliente_id = :cid
        ORDER BY ei.created_at DESC
    """), {"eid": empresa_id, "cid": cliente_id}).fetchall()

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


# ── 7. Detalle de un equipo intervenido ──────────────────────────────────────

@router.get("/mantenimiento/{ei_id}/detalles")
def portal_mantenimiento_detalles(
    ei_id:   str,
    payload: dict = Depends(_requires_client),
    db: Session   = Depends(get_db),
) -> dict[str, Any]:
    empresa_id, cliente_id = _ctx(payload)

    # Verificar pertenencia — datos de la intervención + servicio + proyecto
    row = db.execute(text("""
        SELECT
            ei.id, ei.nombre, ei.codigo, ei.marca, ei.modelo,
            ei.ubicacion_referencia, ei.estado, ei.estado_intervencion,
            ei.ultimo_mantenimiento, ei.proximo_mantenimiento, ei.frecuencia_meses,
            ei.observaciones,
            ei.proyecto_id, ei.proyecto_servicio_id,
            p.nombre_proyecto,
            ps.nombre        AS serv_nombre,
            ps.estado        AS serv_estado,
            ps.fecha_programada,
            ps.fecha_inicio  AS serv_inicio,
            ps.fecha_fin     AS serv_fin
        FROM equipo_intervenido ei
        LEFT JOIN proyecto          p  ON p.id  = ei.proyecto_id
        LEFT JOIN proyecto_servicio ps ON ps.id = ei.proyecto_servicio_id
        WHERE ei.id = :eiid AND ei.empresa_id = :eid AND ei.cliente_id = :cid
    """), {"eiid": ei_id, "eid": empresa_id, "cid": cliente_id}).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Equipo no encontrado.")

    (ei_id_db, nombre, codigo, marca, modelo, ubicacion, estado, estado_interv,
     ult_mant, prox_mant, frec, obs,
     proyecto_id, ps_id,
     nombre_proyecto, serv_nombre, serv_estado, serv_fecha_prog,
     serv_inicio, serv_fin) = row

    # Personal técnico del proyecto
    personal: list[dict] = []
    if proyecto_id:
        prows = db.execute(text("""
            SELECT DISTINCT
                u.nombre || ' ' || u.apellido AS nombre_completo,
                e.cargo,
                pm.rol_proyecto
            FROM proyecto_miembro pm
            JOIN empleado e ON e.id = pm.empleado_id
            JOIN usuario  u ON u.id = e.usuario_id
            WHERE pm.proyecto_id = :pid AND pm.activo = true
            ORDER BY nombre_completo
        """), {"pid": str(proyecto_id)}).fetchall()
        personal = [{"nombre": p[0], "cargo": p[1], "rol_proyecto": p[2]} for p in prows]

    # Herramientas/equipos usados (préstamos del servicio)
    herramientas: list[dict] = []
    if ps_id:
        hrows = db.execute(text("""
            SELECT eq.nombre, eq.codigo, eq.clase, pi2.cantidad_entregada
            FROM prestamo pr
            JOIN prestamo_item pi2 ON pi2.prestamo_id = pr.id
            JOIN equipo eq         ON eq.id = pi2.equipo_id
            WHERE pr.proyecto_servicio_id = :psid
              AND pr.estado IN ('entregado','devuelto','confirmado')
            ORDER BY eq.clase, eq.nombre
        """), {"psid": str(ps_id)}).fetchall()
        herramientas = [
            {"nombre": h[0], "codigo": h[1], "tipo": h[2], "cantidad": h[3]}
            for h in hrows
        ]

    # Documentos descargables
    documentos: list[dict] = []
    if ps_id:
        drows = db.execute(text("""
            SELECT tipo, titulo, url, fecha FROM informe_servicio
            WHERE servicio_id = :psid AND empresa_id = :eid AND url IS NOT NULL
            ORDER BY fecha DESC NULLS LAST
        """), {"psid": str(ps_id), "eid": empresa_id}).fetchall()
        documentos = [
            {
                "tipo":   d[0],
                "titulo": d[1],
                "url":    d[2],
                "fecha":  d[3].isoformat() if d[3] else None,
            }
            for d in drows
        ]

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
        "servicio": {
            "nombre":           serv_nombre,
            "estado":           serv_estado,
            "fecha_programada": serv_fecha_prog.isoformat() if serv_fecha_prog else None,
            "fecha_inicio":     serv_inicio.isoformat() if serv_inicio else None,
            "fecha_fin":        serv_fin.isoformat() if serv_fin else None,
        },
        "proyecto":     nombre_proyecto,
        "personal":     personal,
        "herramientas": herramientas,
        "documentos":   documentos,
    }
