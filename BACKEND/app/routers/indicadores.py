"""
Router: /indicadores — Punto 3.4 (RR.HH.), indicadores de desempeño.
Agrega por empleado: promedio de evaluaciones completadas, asistencia y
puntualidad, y saldo de vacaciones; más un resumen a nivel empresa (incluye la
calificación promedio de clientes). Solo lectura, gate dashboard:ver.
"""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.evaluacion import Evaluacion, DetalleEvaluacion, CalificacionCliente
from ..models.registro_asistencia import RegistroAsistencia
from ..routers.vacaciones import _get_config, _saldo
from ..schemas.indicadores import IndicadorEmpleado, ResumenEmpresa

router = APIRouter(prefix="/indicadores", tags=["indicadores"])


def _score_global(promedio_eval: Optional[float], puntualidad: Optional[float]) -> Optional[float]:
    """Mezcla evaluación (1-10 → 0-100) y puntualidad (%). Pondera lo disponible."""
    partes = []
    if promedio_eval is not None:
        partes.append(promedio_eval * 10.0)
    if puntualidad is not None:
        partes.append(puntualidad)
    if not partes:
        return None
    return round(sum(partes) / len(partes), 1)


def _indicadores_por_empleado(db: Session, empresa_id: str) -> List[IndicadorEmpleado]:
    cfg = _get_config(db, empresa_id)
    emps = (
        db.query(Empleado)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)  # noqa: E712
        .all()
    )

    # Promedio de evaluaciones COMPLETADAS por empleado
    eval_rows = dict(
        (str(eid), (float(avg), int(cnt)))
        for eid, avg, cnt in (
            db.query(Evaluacion.empleado_id,
                     func.avg(DetalleEvaluacion.puntaje),
                     func.count(func.distinct(Evaluacion.id)))
            .join(DetalleEvaluacion, DetalleEvaluacion.evaluacion_id == Evaluacion.id)
            .filter(Evaluacion.empresa_id == empresa_id, Evaluacion.estado == "completada")
            .group_by(Evaluacion.empleado_id)
            .all()
        )
    )

    # Asistencia: total y validados por empleado
    asis_total = dict(
        (str(eid), int(n)) for eid, n in (
            db.query(RegistroAsistencia.empleado_id, func.count(RegistroAsistencia.id))
            .filter(RegistroAsistencia.empresa_id == empresa_id)
            .group_by(RegistroAsistencia.empleado_id).all()
        )
    )
    asis_valid = dict(
        (str(eid), int(n)) for eid, n in (
            db.query(RegistroAsistencia.empleado_id, func.count(RegistroAsistencia.id))
            .filter(RegistroAsistencia.empresa_id == empresa_id,
                    RegistroAsistencia.estado == "validado")
            .group_by(RegistroAsistencia.empleado_id).all()
        )
    )

    out: List[IndicadorEmpleado] = []
    for e in emps:
        eid = str(e.id)
        prom_eval, n_eval = eval_rows.get(eid, (None, 0))
        prom_eval = round(prom_eval, 2) if prom_eval is not None else None
        total = asis_total.get(eid, 0)
        valid = asis_valid.get(eid, 0)
        puntualidad = round(valid / total * 100, 1) if total > 0 else None
        saldo = _saldo(db, empresa_id, e, cfg)
        nombre = db.query(Usuario.nombre, Usuario.apellido).filter(Usuario.id == e.usuario_id).first()
        out.append(IndicadorEmpleado(
            empleado_id=eid,
            empleado_nombre=(f"{nombre[0]} {nombre[1]}".strip() if nombre else None),
            cargo=e.cargo,
            evaluaciones_total=n_eval,
            promedio_evaluaciones=prom_eval,
            asistencia_total=total,
            asistencia_validados=valid,
            puntualidad_pct=puntualidad,
            vacaciones_disponible=saldo.disponible,
            vacaciones_gozado=saldo.gozado,
            score_global=_score_global(prom_eval, puntualidad),
        ))
    out.sort(key=lambda i: (i.score_global if i.score_global is not None else -1), reverse=True)
    return out


@router.get("/desempeno", response_model=List[IndicadorEmpleado])
def desempeno(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "dashboard", "ver")
    return _indicadores_por_empleado(db, payload["empresa_id"])


@router.get("/resumen", response_model=ResumenEmpresa)
def resumen(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "dashboard", "ver")
    empresa_id = payload["empresa_id"]
    indicadores = _indicadores_por_empleado(db, empresa_id)

    evals = [i.promedio_evaluaciones for i in indicadores if i.promedio_evaluaciones is not None]
    punts = [i.puntualidad_pct for i in indicadores if i.puntualidad_pct is not None]
    calif = (
        db.query(func.avg(CalificacionCliente.puntaje))
        .filter(CalificacionCliente.empresa_id == empresa_id).scalar()
    )

    return ResumenEmpresa(
        empleados=len(indicadores),
        promedio_evaluaciones=(round(sum(evals) / len(evals), 2) if evals else None),
        puntualidad_promedio=(round(sum(punts) / len(punts), 1) if punts else None),
        calificacion_cliente=(round(float(calif), 2) if calif is not None else None),
        top=indicadores[:5],
    )
