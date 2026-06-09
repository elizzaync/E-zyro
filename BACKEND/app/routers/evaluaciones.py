"""
Router: /evaluaciones — Punto 3.2 (RR.HH.).
Criterios de evaluación + evaluaciones de desempeño por empleado, con detalle
de puntajes (1-10) y flujo borrador → enviada → completada.
Lecturas: empresa del token. Escrituras: RBAC dominio 'evaluacion'.
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.evaluacion import CriterioEvaluacion, Evaluacion, DetalleEvaluacion
from ..schemas.evaluacion import (
    CriterioIn, CriterioOut, DetalleIn, DetalleOut,
    EvaluacionIn, EvaluacionOut, EstadoUpdate,
)

router = APIRouter(prefix="/evaluaciones", tags=["evaluaciones"])


def _parse_date(s: Optional[str]) -> Optional[date]:
    return date.fromisoformat(s[:10]) if s else None


def _empleado_actual(db: Session, payload: dict) -> Optional[Empleado]:
    """Empleado vinculado al usuario del token (evaluador)."""
    return (
        db.query(Empleado)
        .filter(Empleado.usuario_id == payload.get("id"),
                Empleado.empresa_id == payload["empresa_id"])
        .first()
    )


def _nombre_empleado(db: Session, empleado_id: str) -> Optional[str]:
    row = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == empleado_id)
        .first()
    )
    return f"{row[0]} {row[1]}".strip() if row else None


# ── Criterios ────────────────────────────────────────────────────────────────
@router.get("/criterios", response_model=List[CriterioOut])
def listar_criterios(
    incluir_inactivos: bool = Query(False),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(CriterioEvaluacion).filter(
        CriterioEvaluacion.empresa_id == payload["empresa_id"])
    if not incluir_inactivos:
        qry = qry.filter(CriterioEvaluacion.activo == True)  # noqa: E712
    return [
        CriterioOut(id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
                    peso=float(c.peso), activo=bool(c.activo))
        for c in qry.order_by(CriterioEvaluacion.nombre).all()
    ]


@router.post("/criterios", response_model=CriterioOut, status_code=201)
def crear_criterio(body: CriterioIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "crear")
    c = CriterioEvaluacion(
        id=str(_uuid.uuid4()), empresa_id=payload["empresa_id"],
        nombre=body.nombre, descripcion=body.descripcion, peso=body.peso, activo=True,
    )
    db.add(c)
    db.commit()
    return CriterioOut(id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
                       peso=float(c.peso), activo=True)


@router.put("/criterios/{crit_id}", response_model=CriterioOut)
def editar_criterio(crit_id: str, body: CriterioIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "editar")
    c = db.query(CriterioEvaluacion).filter(
        CriterioEvaluacion.id == crit_id,
        CriterioEvaluacion.empresa_id == payload["empresa_id"]).first()
    if not c:
        raise HTTPException(status_code=404, detail="Criterio no encontrado")
    c.nombre = body.nombre
    c.descripcion = body.descripcion
    c.peso = body.peso
    db.commit()
    return CriterioOut(id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
                       peso=float(c.peso), activo=bool(c.activo))


@router.delete("/criterios/{crit_id}", status_code=204)
def eliminar_criterio(crit_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "eliminar")
    c = db.query(CriterioEvaluacion).filter(
        CriterioEvaluacion.id == crit_id,
        CriterioEvaluacion.empresa_id == payload["empresa_id"]).first()
    if not c:
        raise HTTPException(status_code=404, detail="Criterio no encontrado")
    # Baja lógica: el criterio puede estar referenciado por evaluaciones pasadas.
    c.activo = False
    db.commit()


# ── Evaluaciones ─────────────────────────────────────────────────────────────
def _eval_out(db: Session, ev: Evaluacion, con_detalles: bool = True) -> EvaluacionOut:
    detalles_out: List[DetalleOut] = []
    suma_pond = 0.0
    suma_peso = 0.0
    if con_detalles:
        rows = (
            db.query(DetalleEvaluacion, CriterioEvaluacion.nombre, CriterioEvaluacion.peso)
            .outerjoin(CriterioEvaluacion, CriterioEvaluacion.id == DetalleEvaluacion.criterio_id)
            .filter(DetalleEvaluacion.evaluacion_id == ev.id)
            .all()
        )
        for d, cnombre, cpeso in rows:
            peso = float(cpeso) if cpeso is not None else 1.0
            detalles_out.append(DetalleOut(
                id=str(d.id), criterio_id=str(d.criterio_id), criterio_nombre=cnombre,
                peso=peso, puntaje=int(d.puntaje), comentario=d.comentario,
            ))
            suma_pond += d.puntaje * peso
            suma_peso += peso
    promedio = round(suma_pond / suma_peso, 2) if suma_peso > 0 else None
    return EvaluacionOut(
        id=str(ev.id), empleado_id=str(ev.empleado_id),
        empleado_nombre=_nombre_empleado(db, str(ev.empleado_id)),
        evaluador_id=str(ev.evaluador_id),
        evaluador_nombre=_nombre_empleado(db, str(ev.evaluador_id)),
        periodo=ev.periodo, estado=ev.estado,
        fecha=(str(ev.fecha) if ev.fecha else None),
        promedio=promedio, detalles=detalles_out,
    )


@router.get("", response_model=List[EvaluacionOut])
def listar(
    empleado_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(Evaluacion).filter(Evaluacion.empresa_id == payload["empresa_id"])
    if empleado_id:
        qry = qry.filter(Evaluacion.empleado_id == empleado_id)
    if estado:
        qry = qry.filter(Evaluacion.estado == estado)
    rows = qry.order_by(Evaluacion.fecha.desc()).limit(500).all()
    return [_eval_out(db, ev, con_detalles=False) for ev in rows]


@router.get("/{eval_id}", response_model=EvaluacionOut)
def detalle(eval_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    ev = db.query(Evaluacion).filter(
        Evaluacion.id == eval_id, Evaluacion.empresa_id == payload["empresa_id"]).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evaluación no encontrada")
    return _eval_out(db, ev, con_detalles=True)


@router.post("", response_model=EvaluacionOut, status_code=201)
def crear(body: EvaluacionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "crear")
    empresa_id = payload["empresa_id"]
    evaluador = _empleado_actual(db, payload)
    if not evaluador:
        raise HTTPException(status_code=400, detail="El usuario no tiene ficha de empleado (evaluador)")
    emp = db.query(Empleado).filter(
        Empleado.id == body.empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado evaluado no encontrado")
    ev = Evaluacion(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, empleado_id=body.empleado_id,
        evaluador_id=str(evaluador.id), periodo=body.periodo, estado="borrador",
        fecha=_parse_date(body.fecha) or date.today(),
    )
    db.add(ev)
    db.flush()
    for d in body.detalles:
        db.add(DetalleEvaluacion(
            id=str(_uuid.uuid4()), evaluacion_id=ev.id, criterio_id=d.criterio_id,
            puntaje=d.puntaje, comentario=d.comentario,
        ))
    db.commit()
    return _eval_out(db, ev)


@router.put("/{eval_id}", response_model=EvaluacionOut)
def editar(eval_id: str, body: EvaluacionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "editar")
    empresa_id = payload["empresa_id"]
    ev = db.query(Evaluacion).filter(
        Evaluacion.id == eval_id, Evaluacion.empresa_id == empresa_id).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evaluación no encontrada")
    if ev.estado != "borrador":
        raise HTTPException(status_code=409, detail="Solo se puede editar una evaluación en borrador")
    ev.periodo = body.periodo
    if body.fecha:
        ev.fecha = _parse_date(body.fecha)
    # Reemplaza el detalle completo
    db.query(DetalleEvaluacion).filter(DetalleEvaluacion.evaluacion_id == ev.id).delete()
    for d in body.detalles:
        db.add(DetalleEvaluacion(
            id=str(_uuid.uuid4()), evaluacion_id=ev.id, criterio_id=d.criterio_id,
            puntaje=d.puntaje, comentario=d.comentario,
        ))
    db.commit()
    return _eval_out(db, ev)


@router.post("/{eval_id}/estado", response_model=EvaluacionOut)
def cambiar_estado(eval_id: str, body: EstadoUpdate, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    ev = db.query(Evaluacion).filter(
        Evaluacion.id == eval_id, Evaluacion.empresa_id == empresa_id).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evaluación no encontrada")
    # Transiciones permitidas: borrador→enviada, enviada→completada
    if body.estado == "enviada":
        exigir_permiso(db, payload, "evaluacion", "enviar")
        if ev.estado != "borrador":
            raise HTTPException(status_code=409, detail="Solo se envía desde borrador")
    else:  # completada
        exigir_permiso(db, payload, "evaluacion", "completar")
        if ev.estado != "enviada":
            raise HTTPException(status_code=409, detail="Solo se completa desde enviada")
    ev.estado = body.estado
    db.commit()
    return _eval_out(db, ev)


@router.delete("/{eval_id}", status_code=204)
def eliminar(eval_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "eliminar")
    empresa_id = payload["empresa_id"]
    ev = db.query(Evaluacion).filter(
        Evaluacion.id == eval_id, Evaluacion.empresa_id == empresa_id).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evaluación no encontrada")
    db.query(DetalleEvaluacion).filter(DetalleEvaluacion.evaluacion_id == ev.id).delete()
    db.delete(ev)
    db.commit()
