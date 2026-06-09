"""
Router: /personal — Punto 3.1 (RR.HH.).
Expone el catálogo de empleados y un historial laboral consolidado por empleado
(datos, contratos, asistencia, solicitudes, EPP y evaluaciones), pensado para
alimentar el PDF de historial de personal. Lecturas: empresa del token.
"""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.contrato import Contrato
from ..models.registro_asistencia import RegistroAsistencia
from ..models.solicitud_laboral import SolicitudLaboral
from ..models.epp import EppEntrega, EppEntregaDetalle
from ..models.evaluacion import Evaluacion, DetalleEvaluacion
from ..schemas.personal import (
    EmpleadoOut, HistorialPersonal, ContratoItem, AsistenciaResumen,
    MarcacionItem, SolicitudItem, EppEntregaItem, EvaluacionResumen,
)

router = APIRouter(prefix="/personal", tags=["personal"])

_ULTIMAS_MARCACIONES = 15


def _nombre(u: Optional[Usuario]) -> Optional[str]:
    if not u:
        return None
    return f"{u.nombre} {u.apellido}".strip()


def _emp_out(e: Empleado, u: Optional[Usuario]) -> EmpleadoOut:
    return EmpleadoOut(
        id=str(e.id), usuario_id=str(e.usuario_id), nombre=_nombre(u),
        codigo=e.codigo, cargo=e.cargo, area=e.area, tipo=e.tipo,
        fecha_ingreso=(str(e.fecha_ingreso) if e.fecha_ingreso else None),
        fecha_fin_contrato=(str(e.fecha_fin_contrato) if e.fecha_fin_contrato else None),
        activo=bool(e.activo), foto_url=(u.foto_url if u else None),
    )


@router.get("", response_model=List[EmpleadoOut])
def listar(
    q: Optional[str] = Query(None, description="busca por nombre/cargo/código"),
    solo_activos: bool = Query(True),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    qry = (
        db.query(Empleado, Usuario)
        .outerjoin(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id)
    )
    if solo_activos:
        qry = qry.filter(Empleado.activo == True)  # noqa: E712
    if q:
        term = f"%{q.strip().lower()}%"
        qry = qry.filter(func.lower(
            func.coalesce(Usuario.nombre, "") + " " + func.coalesce(Usuario.apellido, "")
            + " " + func.coalesce(Empleado.cargo, "") + " " + func.coalesce(Empleado.codigo, "")
        ).like(term))
    rows = qry.order_by(Usuario.nombre).limit(500).all()
    return [_emp_out(e, u) for e, u in rows]


@router.get("/{empleado_id}/historial", response_model=HistorialPersonal)
def historial(empleado_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    e = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not e:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    u = db.query(Usuario).filter(Usuario.id == e.usuario_id).first()

    # ── Contratos ───────────────────────────────────────────────────────────
    contratos = (
        db.query(Contrato)
        .filter(Contrato.empleado_id == empleado_id, Contrato.empresa_id == empresa_id)
        .order_by(Contrato.fecha_inicio.desc())
        .all()
    )
    contratos_out = [
        ContratoItem(
            tipo=c.tipo,
            fecha_inicio=(str(c.fecha_inicio) if c.fecha_inicio else None),
            fecha_fin=(str(c.fecha_fin) if c.fecha_fin else None),
            estado=c.estado,
        ) for c in contratos
    ]

    # ── Asistencia (resumen por estado + últimas N) ──────────────────────────
    conteos = dict(
        db.query(RegistroAsistencia.estado, func.count(RegistroAsistencia.id))
        .filter(RegistroAsistencia.empleado_id == empleado_id,
                RegistroAsistencia.empresa_id == empresa_id)
        .group_by(RegistroAsistencia.estado).all()
    )
    asistencia = AsistenciaResumen(
        total=int(sum(conteos.values())),
        validados=int(conteos.get("validado", 0)),
        pendientes=int(conteos.get("pendiente", 0)),
        rechazados=int(conteos.get("rechazado", 0)),
    )
    ultimas = (
        db.query(RegistroAsistencia)
        .filter(RegistroAsistencia.empleado_id == empleado_id,
                RegistroAsistencia.empresa_id == empresa_id)
        .order_by(RegistroAsistencia.fecha_hora.desc())
        .limit(_ULTIMAS_MARCACIONES).all()
    )
    marcaciones = [
        MarcacionItem(
            tipo=m.tipo,
            fecha_hora=(m.fecha_hora.isoformat() if m.fecha_hora else None),
            estado=m.estado,
        ) for m in ultimas
    ]

    # ── Solicitudes laborales (permisos/vacaciones/etc.) ─────────────────────
    sols = (
        db.query(SolicitudLaboral)
        .filter(SolicitudLaboral.empleado_id == empleado_id,
                SolicitudLaboral.empresa_id == empresa_id)
        .order_by(SolicitudLaboral.created_at.desc())
        .limit(50).all()
    )
    solicitudes = [
        SolicitudItem(
            tipo=s.tipo, estado=s.estado,
            fecha_inicio=(str(s.fecha_inicio) if s.fecha_inicio else None),
            fecha_fin=(str(s.fecha_fin) if s.fecha_fin else None),
            url_pdf=s.url_pdf,
        ) for s in sols
    ]

    # ── EPP entregado ─────────────────────────────────────────────────────────
    entregas = (
        db.query(EppEntrega)
        .filter(EppEntrega.empleado_id == empleado_id, EppEntrega.empresa_id == empresa_id)
        .order_by(EppEntrega.fecha.desc())
        .limit(50).all()
    )
    epp_out = []
    for en in entregas:
        n_items = (
            db.query(func.coalesce(func.sum(EppEntregaDetalle.cantidad), 0))
            .filter(EppEntregaDetalle.entrega_id == en.id).scalar()
        )
        epp_out.append(EppEntregaItem(
            fecha=(str(en.fecha) if en.fecha else None), estado=en.estado,
            items=int(n_items or 0), pdf_url=en.pdf_url,
        ))

    # ── Evaluaciones (resumen) ────────────────────────────────────────────────
    total_eval = (
        db.query(func.count(Evaluacion.id))
        .filter(Evaluacion.empleado_id == empleado_id, Evaluacion.empresa_id == empresa_id)
        .scalar()
    )
    promedio = (
        db.query(func.avg(DetalleEvaluacion.puntaje))
        .join(Evaluacion, Evaluacion.id == DetalleEvaluacion.evaluacion_id)
        .filter(Evaluacion.empleado_id == empleado_id, Evaluacion.empresa_id == empresa_id)
        .scalar()
    )
    ultimo_periodo = (
        db.query(Evaluacion.periodo)
        .filter(Evaluacion.empleado_id == empleado_id, Evaluacion.empresa_id == empresa_id)
        .order_by(Evaluacion.fecha.desc())
        .limit(1).scalar()
    )
    evaluaciones = EvaluacionResumen(
        total=int(total_eval or 0),
        promedio_general=(round(float(promedio), 2) if promedio is not None else None),
        ultimo_periodo=ultimo_periodo,
    )

    return HistorialPersonal(
        empleado=_emp_out(e, u), contratos=contratos_out, asistencia=asistencia,
        marcaciones=marcaciones, solicitudes=solicitudes, epp=epp_out,
        evaluaciones=evaluaciones,
    )
