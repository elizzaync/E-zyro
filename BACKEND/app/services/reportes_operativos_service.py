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
from ..models.programacion_campo import ProgramacionCampo, ProgramacionEmpleado
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


def _minutos_trabajados_por_empleado_dia(
    db: Session, empresa_id: str, desde: date, hasta: date,
) -> dict[tuple[str, date], int]:
    """Trae en una sola consulta todos los eventos entrada/salida del rango
    (de TODOS los empleados) y los concilia en un unico paso en Python — evita
    1 query por empleado/dia. Un check-in sin su salida pareada (turno abierto
    al cierre del rango) no suma minutos; simplificacion aceptable para un
    reporte de rango cerrado."""
    regs = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id == empresa_id,
            RegistroAsistencia.tipo.in_(("entrada", "salida")),
            cast(RegistroAsistencia.fecha_hora, Date) >= desde,
            cast(RegistroAsistencia.fecha_hora, Date) <= hasta,
        )
        .order_by(RegistroAsistencia.empleado_id, RegistroAsistencia.fecha_hora)
        .all()
    )

    minutos: dict[tuple[str, date], int] = defaultdict(int)
    pendiente: dict[tuple[str, date], datetime] = {}
    for r in regs:
        clave = (str(r.empleado_id), r.fecha_hora.date())
        if r.tipo == "entrada":
            pendiente[clave] = r.fecha_hora
        elif r.tipo == "salida" and clave in pendiente:
            ini = pendiente.pop(clave)
            minutos[clave] += max(int((r.fecha_hora - ini).total_seconds() // 60), 0)
    return minutos


def _horas_hombre_por_proyecto(
    db: Session, empresa_id: str, desde: date, hasta: date, proyecto_id: str | None,
) -> dict[str, float]:
    """Atribuye las horas trabajadas de cada dia al proyecto que Operaciones
    asigno ese dia (programacion_campo/programacion_empleado) — el fichaje no
    lleva proyecto a proposito (asistencia = control horario, no asignacion;
    ver HU-54). Si un empleado quedo asignado a mas de un proyecto el mismo
    dia, se reparte el total del dia por igual entre ellos."""
    minutos_dia = _minutos_trabajados_por_empleado_dia(db, empresa_id, desde, hasta)
    if not minutos_dia:
        return {}

    q = (
        db.query(ProgramacionEmpleado.empleado_id, ProgramacionCampo.proyecto_id, ProgramacionCampo.fecha)
        .join(ProgramacionCampo, ProgramacionCampo.id == ProgramacionEmpleado.programacion_id)
        .filter(
            ProgramacionCampo.empresa_id == empresa_id,
            ProgramacionCampo.fecha >= desde,
            ProgramacionCampo.fecha <= hasta,
        )
    )
    if proyecto_id:
        q = q.filter(ProgramacionCampo.proyecto_id == proyecto_id)

    # normalizar a str: columnas UUID nativas en Postgres vuelven como uuid.UUID
    # via psycopg2 aunque el modelo las declare String(36) (mismo gotcha de
    # siempre en este proyecto — ver memoria "Postgres con UUID nativos").
    asignaciones: dict[tuple[str, date], list[str]] = defaultdict(list)
    for emp_id, pid, fecha in q.all():
        asignaciones[(str(emp_id), fecha)].append(str(pid))

    minutos_proyecto: dict[str, float] = defaultdict(float)
    for (emp_id, fecha), proyectos_dia in asignaciones.items():
        total_min = minutos_dia.get((emp_id, fecha))
        if not total_min:
            continue
        reparto = total_min / len(proyectos_dia)
        for pid in proyectos_dia:
            minutos_proyecto[pid] += reparto

    return {pid: round(m / 60, 1) for pid, m in minutos_proyecto.items()}


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
