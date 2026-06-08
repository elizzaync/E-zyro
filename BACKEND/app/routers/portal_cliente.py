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
