"""
Resumen de asistencia por periodo para la planilla (Fase 2).

Compone la lógica de asistencia que YA existe (no la reconstruye):
  - `routers.asistencia._resumen_dia`     → estado y minutos de tardanza por día,
                                             respetando el turno y su tolerancia.
  - `routers.rrhh_asistencia._dias_laborables` → días laborables del periodo.
  - `SolicitudLaboral` (permisos aprobados) → días justificados (no descuentan).

Devuelve, por empleado, los insumos que el cálculo de planilla convierte en
conceptos de descuento: faltas injustificadas, minutos de tardanza y la jornada
(para prorratear la tardanza). Las importaciones de los routers son perezosas
para evitar ciclos de importación al cargar el módulo.
"""
from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy.orm import Session


def resumen_asistencia_periodo(
    db: Session, empresa_id: str, inicio: date, fin: date
) -> dict[str, dict]:
    """Por empleado activo en [inicio, fin]:
        {faltas, tardanzas, minutos_tardanza, dias_justificados, minutos_jornada}

    - falta        = día laborable, no justificado, sin marca de entrada.
    - tardanza     = llegó tarde (más allá de la tolerancia del turno).
    - justificado  = cubierto por un permiso (SolicitudLaboral) aprobado.
    """
    from app.routers.asistencia import _resumen_dia
    from app.routers.rrhh_asistencia import _dias_laborables
    from app.models.solicitud_laboral import SolicitudLaboral

    dias = _dias_laborables(inicio, fin)
    dias_set = set(dias)

    # Días justificados por empleado (permisos aprobados que solapan el periodo).
    justificados: dict[str, set] = {}
    solis = (
        db.query(SolicitudLaboral)
        .filter(
            SolicitudLaboral.empresa_id == empresa_id,
            SolicitudLaboral.estado == "aprobada",
            SolicitudLaboral.fecha_inicio <= fin,
            SolicitudLaboral.fecha_fin >= inicio,
        )
        .all()
    )
    for s in solis:
        cur = max(s.fecha_inicio, inicio)
        end = min(s.fecha_fin, fin)
        while cur <= end:
            if cur in dias_set:
                justificados.setdefault(str(s.empleado_id), set()).add(cur)
            cur += timedelta(days=1)

    acc: dict[str, dict] = {}
    for dia in dias:
        resumen = _resumen_dia(db, empresa_id, dia)
        for it in resumen.get("items", []):
            emp = str(it["empleado_id"])
            a = acc.setdefault(emp, {
                "faltas": 0, "tardanzas": 0, "minutos_tardanza": 0,
                "dias_justificados": 0, "minutos_jornada": 0,
            })
            # Jornada del turno (minutos requeridos) — para prorratear la tardanza.
            mj = int(it.get("minutos_requeridos") or 0)
            if mj > 0:
                a["minutos_jornada"] = mj

            if dia in justificados.get(emp, set()):
                a["dias_justificados"] += 1
                continue

            if it.get("estado") == "ausente":
                a["faltas"] += 1
            elif it.get("llego_tarde"):
                a["tardanzas"] += 1
                a["minutos_tardanza"] += int(it.get("minutos_tarde") or 0)

    return acc
