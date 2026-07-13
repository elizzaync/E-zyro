"""
Servicio: reporte operativo consolidado por proyecto (HU-54).

Junta horas hombre (registro_asistencia) y materiales consumidos
(movimiento_inventario vía requerimiento) agrupados por proyecto, para
auditorías internas. Pensado para no saturar el servidor con rangos de
fecha amplios: los materiales se agregan 100% en SQL (GROUP BY); las horas
hombre se traen en una sola consulta (no una por empleado/día, que es como
ya lo hace mi_resumen_semanal para un único empleado) y se concilian en un
solo paso en Python.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta

from sqlalchemy import cast, Date, func
from sqlalchemy.orm import Session

from ..models.movimiento_inventario import MovimientoInventario
from ..models.proyecto import Proyecto
from ..models.registro_asistencia import RegistroAsistencia
from ..models.requerimiento import Requerimiento


def _materiales_por_proyecto(
    db: Session, empresa_id: str, desde: date, hasta: date, proyecto_id: str | None,
) -> dict[str, dict]:
    q = (
        db.query(
            Requerimiento.proyecto_id,
            func.sum(MovimientoInventario.cantidad).label("cantidad"),
            func.sum(MovimientoInventario.valor_total).label("valor"),
        )
        .join(Requerimiento, Requerimiento.id == MovimientoInventario.referencia_id)
        .filter(
            MovimientoInventario.empresa_id == empresa_id,
            MovimientoInventario.referencia_tipo == "requerimiento",
            MovimientoInventario.tipo == "salida",
            MovimientoInventario.fecha >= datetime.combine(desde, datetime.min.time()),
            MovimientoInventario.fecha < datetime.combine(hasta + timedelta(days=1), datetime.min.time()),
        )
    )
    if proyecto_id:
        q = q.filter(Requerimiento.proyecto_id == proyecto_id)
    q = q.group_by(Requerimiento.proyecto_id)

    return {
        str(pid): {"cantidad": int(cant or 0), "valor": float(valor or 0)}
        for pid, cant, valor in q.all()
    }


def _horas_hombre_por_proyecto(
    db: Session, empresa_id: str, desde: date, hasta: date, proyecto_id: str | None,
) -> dict[str, float]:
    """Trae en una sola consulta todos los eventos entrada/salida del rango
    (con proyecto asignado) y los concilia en un unico paso en Python — evita
    1 query por empleado/dia. Un check-in sin su salida pareada (turno abierto
    al cierre del rango) no suma horas; simplificacion aceptable para un
    reporte de rango cerrado."""
    q = db.query(RegistroAsistencia).filter(
        RegistroAsistencia.empresa_id == empresa_id,
        RegistroAsistencia.proyecto_id.isnot(None),
        RegistroAsistencia.tipo.in_(("entrada", "salida")),
        cast(RegistroAsistencia.fecha_hora, Date) >= desde,
        cast(RegistroAsistencia.fecha_hora, Date) <= hasta,
    )
    if proyecto_id:
        q = q.filter(RegistroAsistencia.proyecto_id == proyecto_id)
    regs = q.order_by(
        RegistroAsistencia.proyecto_id,
        RegistroAsistencia.empleado_id,
        RegistroAsistencia.fecha_hora,
    ).all()

    minutos: dict[str, int] = defaultdict(int)
    pendiente: dict[tuple, datetime] = {}
    for r in regs:
        clave = (r.proyecto_id, r.empleado_id, r.fecha_hora.date())
        if r.tipo == "entrada":
            pendiente[clave] = r.fecha_hora
        elif r.tipo == "salida" and clave in pendiente:
            ini = pendiente.pop(clave)
            minutos[r.proyecto_id] += max(int((r.fecha_hora - ini).total_seconds() // 60), 0)

    return {pid: round(m / 60, 1) for pid, m in minutos.items()}


def reporte_operativo_por_proyecto(
    db: Session, empresa_id: str, desde: date, hasta: date, proyecto_id: str | None = None,
) -> list[dict]:
    materiales = _materiales_por_proyecto(db, empresa_id, desde, hasta, proyecto_id)
    horas = _horas_hombre_por_proyecto(db, empresa_id, desde, hasta, proyecto_id)

    proyecto_ids = set(materiales) | set(horas)
    if proyecto_id:
        proyecto_ids &= {proyecto_id}
    if not proyecto_ids:
        return []

    nombres = {
        str(p.id): p.nombre_proyecto
        for p in db.query(Proyecto.id, Proyecto.nombre_proyecto)
        .filter(Proyecto.id.in_(proyecto_ids), Proyecto.empresa_id == empresa_id)
        .all()
    }

    filas = [
        {
            "proyecto_id": pid,
            "nombre_proyecto": nombres.get(pid, "(proyecto eliminado)"),
            "horas_hombre": horas.get(pid, 0.0),
            "materiales_cantidad": materiales.get(pid, {}).get("cantidad", 0),
            "materiales_valor": materiales.get(pid, {}).get("valor", 0.0),
        }
        for pid in proyecto_ids
    ]
    filas.sort(key=lambda f: f["nombre_proyecto"])
    return filas
