"""
Router: /evaluaciones — Punto 3.2 (RR.HH.).
Flujo completo:
  Plantillas → Asignar a empleado (estado asignada) → Empleado completa (completada)
  O manualmente: borrador → enviada → completada (flujo libre).
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
from ..models.evaluacion import (
    CriterioEvaluacion, Evaluacion, DetalleEvaluacion,
    PlantillaEvaluacion, PlantillaEvaluacionCriterio,
)
from ..models.notificacion import Notificacion
from ..schemas.evaluacion import (
    CriterioIn, CriterioOut, DetalleIn, DetalleOut,
    EvaluacionIn, EvaluacionOut, EstadoUpdate,
    PlantillaIn, PlantillaOut, PlantillaItemOut,
    AsignarPlantillaIn, CompletarPropiaIn,
)
from pydantic import BaseModel as _BaseModel

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


def _tipo_label(tipo: str) -> str:
    return {
        "rrhh": "Conocimiento", "jefe_directo": "Jefe Directo",
        "companero": "Compañerismo", "psicologico": "Psicológica",
    }.get(tipo, tipo)


# ── Criterios ────────────────────────────────────────────────────────────────
@router.get("/criterios", response_model=List[CriterioOut])
def listar_criterios(
    tipo: Optional[str] = Query(None, description="rrhh|jefe_directo|companero"),
    incluir_inactivos: bool = Query(False),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(CriterioEvaluacion).filter(
        CriterioEvaluacion.empresa_id == payload["empresa_id"])
    if tipo:
        qry = qry.filter(CriterioEvaluacion.tipo == tipo)
    if not incluir_inactivos:
        qry = qry.filter(CriterioEvaluacion.activo == True)  # noqa: E712
    return [
        CriterioOut(id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
                    peso=float(c.peso), tipo=c.tipo, activo=bool(c.activo))
        for c in qry.order_by(CriterioEvaluacion.nombre).all()
    ]


@router.post("/criterios", response_model=CriterioOut, status_code=201)
def crear_criterio(body: CriterioIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "crear")
    c = CriterioEvaluacion(
        id=str(_uuid.uuid4()), empresa_id=payload["empresa_id"],
        nombre=body.nombre, descripcion=body.descripcion, peso=body.peso,
        tipo=body.tipo, activo=True,
    )
    db.add(c)
    db.commit()
    return CriterioOut(id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
                       peso=float(c.peso), tipo=c.tipo, activo=True)


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
    c.tipo = body.tipo
    db.commit()
    return CriterioOut(id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
                       peso=float(c.peso), tipo=c.tipo, activo=bool(c.activo))


@router.delete("/criterios/{crit_id}", status_code=204)
def eliminar_criterio(crit_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "eliminar")
    c = db.query(CriterioEvaluacion).filter(
        CriterioEvaluacion.id == crit_id,
        CriterioEvaluacion.empresa_id == payload["empresa_id"]).first()
    if not c:
        raise HTTPException(status_code=404, detail="Criterio no encontrado")
    c.activo = False
    db.commit()


# ── Plantillas ────────────────────────────────────────────────────────────────
def _plantilla_items_out(db: Session, plantilla_id: str) -> List[PlantillaItemOut]:
    rows = (
        db.query(PlantillaEvaluacionCriterio, CriterioEvaluacion)
        .join(CriterioEvaluacion, CriterioEvaluacion.id == PlantillaEvaluacionCriterio.criterio_id)
        .filter(PlantillaEvaluacionCriterio.plantilla_id == plantilla_id)
        .order_by(PlantillaEvaluacionCriterio.orden)
        .all()
    )
    return [
        PlantillaItemOut(
            id=str(pc.id), criterio_id=str(pc.criterio_id),
            criterio_nombre=c.nombre, criterio_descripcion=c.descripcion,
            peso=float(pc.peso) if pc.peso is not None else float(c.peso),
            orden=int(pc.orden),
        )
        for pc, c in rows
    ]


def _plantilla_out(db: Session, p: PlantillaEvaluacion) -> PlantillaOut:
    return PlantillaOut(
        id=str(p.id), nombre=p.nombre, descripcion=p.descripcion,
        tipo=p.tipo, activo=bool(p.activo),
        items=_plantilla_items_out(db, str(p.id)),
        created_at=str(p.created_at)[:10] if p.created_at else None,
    )


@router.get("/plantillas", response_model=List[PlantillaOut])
def listar_plantillas(
    tipo: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(PlantillaEvaluacion).filter(
        PlantillaEvaluacion.empresa_id == payload["empresa_id"],
        PlantillaEvaluacion.activo == True,  # noqa: E712
    )
    if tipo:
        qry = qry.filter(PlantillaEvaluacion.tipo == tipo)
    rows = qry.order_by(PlantillaEvaluacion.nombre).all()
    return [_plantilla_out(db, p) for p in rows]


@router.get("/plantillas/{plantilla_id}", response_model=PlantillaOut)
def detalle_plantilla(plantilla_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    p = db.query(PlantillaEvaluacion).filter(
        PlantillaEvaluacion.id == plantilla_id,
        PlantillaEvaluacion.empresa_id == payload["empresa_id"]).first()
    if not p:
        raise HTTPException(status_code=404, detail="Plantilla no encontrada")
    return _plantilla_out(db, p)


@router.post("/plantillas", response_model=PlantillaOut, status_code=201)
def crear_plantilla(body: PlantillaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "crear")
    empresa_id = payload["empresa_id"]
    p = PlantillaEvaluacion(
        id=str(_uuid.uuid4()), empresa_id=empresa_id,
        nombre=body.nombre.strip(), descripcion=(body.descripcion or "").strip() or None,
        tipo=body.tipo, activo=True,
    )
    db.add(p)
    db.flush()
    for i, item in enumerate(body.items):
        c = db.query(CriterioEvaluacion).filter(
            CriterioEvaluacion.id == item.criterio_id,
            CriterioEvaluacion.empresa_id == empresa_id,
        ).first()
        if not c:
            db.rollback()
            raise HTTPException(status_code=404, detail=f"Criterio {item.criterio_id} no encontrado")
        db.add(PlantillaEvaluacionCriterio(
            id=str(_uuid.uuid4()), plantilla_id=p.id, criterio_id=item.criterio_id,
            peso=item.peso, orden=item.orden if item.orden >= 0 else i,
        ))
    db.commit()
    return _plantilla_out(db, p)


@router.put("/plantillas/{plantilla_id}", response_model=PlantillaOut)
def editar_plantilla(plantilla_id: str, body: PlantillaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "editar")
    empresa_id = payload["empresa_id"]
    p = db.query(PlantillaEvaluacion).filter(
        PlantillaEvaluacion.id == plantilla_id,
        PlantillaEvaluacion.empresa_id == empresa_id).first()
    if not p:
        raise HTTPException(status_code=404, detail="Plantilla no encontrada")
    p.nombre = body.nombre.strip()
    p.descripcion = (body.descripcion or "").strip() or None
    p.tipo = body.tipo
    from datetime import datetime
    p.updated_at = datetime.utcnow()
    # Reemplaza criterios completos
    db.query(PlantillaEvaluacionCriterio).filter(
        PlantillaEvaluacionCriterio.plantilla_id == p.id).delete()
    for i, item in enumerate(body.items):
        c = db.query(CriterioEvaluacion).filter(
            CriterioEvaluacion.id == item.criterio_id,
            CriterioEvaluacion.empresa_id == empresa_id,
        ).first()
        if not c:
            db.rollback()
            raise HTTPException(status_code=404, detail=f"Criterio {item.criterio_id} no encontrado")
        db.add(PlantillaEvaluacionCriterio(
            id=str(_uuid.uuid4()), plantilla_id=p.id, criterio_id=item.criterio_id,
            peso=item.peso, orden=item.orden if item.orden >= 0 else i,
        ))
    db.commit()
    return _plantilla_out(db, p)


@router.delete("/plantillas/{plantilla_id}", status_code=204)
def eliminar_plantilla(plantilla_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "eliminar")
    p = db.query(PlantillaEvaluacion).filter(
        PlantillaEvaluacion.id == plantilla_id,
        PlantillaEvaluacion.empresa_id == payload["empresa_id"]).first()
    if not p:
        raise HTTPException(status_code=404, detail="Plantilla no encontrada")
    p.activo = False
    from datetime import datetime
    p.updated_at = datetime.utcnow()
    db.commit()


@router.post("/plantillas/{plantilla_id}/asignar", response_model=List[EvaluacionOut], status_code=201)
def asignar_plantilla(
    plantilla_id: str, body: AsignarPlantillaIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Asigna una plantilla a uno o varios empleados.
    Crea una Evaluacion por empleado en estado 'asignada' y notifica al empleado."""
    exigir_permiso(db, payload, "evaluacion", "crear")
    empresa_id = payload["empresa_id"]

    plantilla = db.query(PlantillaEvaluacion).filter(
        PlantillaEvaluacion.id == plantilla_id,
        PlantillaEvaluacion.empresa_id == empresa_id,
        PlantillaEvaluacion.activo == True,  # noqa: E712
    ).first()
    if not plantilla:
        raise HTTPException(status_code=404, detail="Plantilla no encontrada")

    items_plantilla = (
        db.query(PlantillaEvaluacionCriterio, CriterioEvaluacion)
        .join(CriterioEvaluacion, CriterioEvaluacion.id == PlantillaEvaluacionCriterio.criterio_id)
        .filter(PlantillaEvaluacionCriterio.plantilla_id == plantilla_id)
        .order_by(PlantillaEvaluacionCriterio.orden)
        .all()
    )
    if not items_plantilla:
        raise HTTPException(status_code=422, detail="La plantilla no tiene criterios definidos")

    evaluador = _empleado_actual(db, payload)
    if not evaluador:
        raise HTTPException(status_code=400, detail="El usuario no tiene ficha de empleado")

    fecha_obj = _parse_date(body.fecha) or date.today()
    resultados: List[EvaluacionOut] = []

    for emp_id in list(set(body.empleado_ids)):
        emp = db.query(Empleado).filter(
            Empleado.id == emp_id, Empleado.empresa_id == empresa_id).first()
        if not emp:
            continue

        ev = Evaluacion(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            empleado_id=emp_id, evaluador_id=str(evaluador.id),
            plantilla_id=plantilla_id, tipo=plantilla.tipo,
            periodo=body.periodo, estado="asignada", fecha=fecha_obj,
        )
        db.add(ev)
        db.flush()

        for pc, c in items_plantilla:
            db.add(DetalleEvaluacion(
                id=str(_uuid.uuid4()), evaluacion_id=ev.id,
                criterio_id=str(c.id), puntaje=0, comentario=None,
            ))

        if emp.usuario_id:
            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                usuario_id=str(emp.usuario_id),
                tipo="evaluacion", categoria="Evaluación Asignada",
                titulo="Nueva evaluación pendiente",
                mensaje=f"Tienes una evaluación '{plantilla.nombre}' pendiente de completar — Período {body.periodo}.",
                leido=False,
            ))

        resultados.append(_eval_out(db, ev, con_detalles=True))

    db.commit()
    return resultados


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
            # Para evaluaciones asignadas el puntaje 0 es placeholder; no computa promedio
            if int(d.puntaje) > 0:
                suma_pond += d.puntaje * peso
                suma_peso += peso
    promedio = round(suma_pond / suma_peso, 2) if suma_peso > 0 else None

    plantilla_nombre: Optional[str] = None
    if ev.plantilla_id:
        pl = db.query(PlantillaEvaluacion).filter(PlantillaEvaluacion.id == ev.plantilla_id).first()
        if pl:
            plantilla_nombre = pl.nombre

    return EvaluacionOut(
        id=str(ev.id), empleado_id=str(ev.empleado_id),
        empleado_nombre=_nombre_empleado(db, str(ev.empleado_id)),
        evaluador_id=str(ev.evaluador_id),
        evaluador_nombre=_nombre_empleado(db, str(ev.evaluador_id)),
        tipo=getattr(ev, "tipo", "rrhh") or "rrhh",
        periodo=ev.periodo, estado=ev.estado,
        fecha=(str(ev.fecha) if ev.fecha else None),
        promedio=promedio, detalles=detalles_out,
        plantilla_id=str(ev.plantilla_id) if ev.plantilla_id else None,
        plantilla_nombre=plantilla_nombre,
        notas_evaluador=getattr(ev, "notas_evaluador", None),
    )


@router.get("", response_model=List[EvaluacionOut])
def listar(
    empleado_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    tipo: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(Evaluacion).filter(Evaluacion.empresa_id == payload["empresa_id"])
    if empleado_id:
        qry = qry.filter(Evaluacion.empleado_id == empleado_id)
    if estado:
        qry = qry.filter(Evaluacion.estado == estado)
    if tipo:
        qry = qry.filter(Evaluacion.tipo == tipo)
    rows = qry.order_by(Evaluacion.fecha.desc()).limit(500).all()
    return [_eval_out(db, ev, con_detalles=False) for ev in rows]


# ── Autoservicio del empleado: evaluaciones que le asignaron ─────────────────
# (definido ANTES de /{eval_id} para que rutas estáticas no se confundan con id)
@router.get("/mias", response_model=List[EvaluacionOut])
def mias(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    emp = _empleado_actual(db, payload)
    if not emp:
        return []
    rows = (
        db.query(Evaluacion)
        .filter(Evaluacion.empresa_id == payload["empresa_id"],
                Evaluacion.empleado_id == str(emp.id),
                Evaluacion.estado != "borrador")
        .order_by(Evaluacion.fecha.desc())
        .limit(200).all()
    )
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
        evaluador_id=str(evaluador.id), tipo=body.tipo, periodo=body.periodo,
        estado="borrador", fecha=_parse_date(body.fecha) or date.today(),
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
    db.query(DetalleEvaluacion).filter(DetalleEvaluacion.evaluacion_id == ev.id).delete()
    for d in body.detalles:
        db.add(DetalleEvaluacion(
            id=str(_uuid.uuid4()), evaluacion_id=ev.id, criterio_id=d.criterio_id,
            puntaje=d.puntaje, comentario=d.comentario,
        ))
    db.commit()
    return _eval_out(db, ev)


@router.post("/{eval_id}/completar-propia", response_model=EvaluacionOut)
def completar_propia(eval_id: str, body: CompletarPropiaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """El empleado completa su propia evaluación (estado asignada → completada)."""
    empresa_id = payload["empresa_id"]
    emp = _empleado_actual(db, payload)
    if not emp:
        raise HTTPException(status_code=400, detail="El usuario no tiene ficha de empleado")

    ev = db.query(Evaluacion).filter(
        Evaluacion.id == eval_id, Evaluacion.empresa_id == empresa_id).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evaluación no encontrada")
    if str(ev.empleado_id) != str(emp.id):
        raise HTTPException(status_code=403, detail="Solo puedes completar tus propias evaluaciones")
    if ev.estado != "asignada":
        raise HTTPException(status_code=409, detail="Solo se puede completar una evaluación en estado 'asignada'")
    if not body.detalles:
        raise HTTPException(status_code=422, detail="Debes enviar al menos un puntaje")

    db.query(DetalleEvaluacion).filter(DetalleEvaluacion.evaluacion_id == ev.id).delete()
    for d in body.detalles:
        db.add(DetalleEvaluacion(
            id=str(_uuid.uuid4()), evaluacion_id=ev.id, criterio_id=d.criterio_id,
            puntaje=d.puntaje, comentario=d.comentario,
        ))
    ev.estado = "completada"
    if body.notas_evaluador:
        ev.notas_evaluador = body.notas_evaluador

    # Notificar al evaluador/RRHH
    evaluador_emp = db.query(Empleado).filter(Empleado.id == ev.evaluador_id).first()
    emp_nombre = _nombre_empleado(db, str(emp.id)) or "Un empleado"
    if evaluador_emp and evaluador_emp.usuario_id:
        db.add(Notificacion(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            usuario_id=str(evaluador_emp.usuario_id),
            tipo="evaluacion", categoria="Evaluación Completada",
            titulo="Evaluación completada",
            mensaje=f"{emp_nombre} completó la evaluación '{ev.plantilla_id and _nombre_plantilla(db, ev.plantilla_id) or _tipo_label(ev.tipo)}' — Período {ev.periodo}.",
            leido=False,
        ))
    db.commit()
    return _eval_out(db, ev)


def _nombre_plantilla(db: Session, plantilla_id: str) -> Optional[str]:
    p = db.query(PlantillaEvaluacion).filter(PlantillaEvaluacion.id == plantilla_id).first()
    return p.nombre if p else None


@router.post("/{eval_id}/estado", response_model=EvaluacionOut)
def cambiar_estado(eval_id: str, body: EstadoUpdate, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    ev = db.query(Evaluacion).filter(
        Evaluacion.id == eval_id, Evaluacion.empresa_id == empresa_id).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evaluación no encontrada")
    if body.estado == "enviada":
        exigir_permiso(db, payload, "evaluacion", "enviar")
        if ev.estado != "borrador":
            raise HTTPException(status_code=409, detail="Solo se envía desde borrador")
    elif body.estado == "completada":
        exigir_permiso(db, payload, "evaluacion", "completar")
        if ev.estado not in ("enviada", "asignada"):
            raise HTTPException(status_code=409, detail="Solo se completa desde enviada o asignada")
    ev.estado = body.estado
    db.commit()

    if body.estado == "completada":
        evaluador_emp = db.query(Empleado).filter(Empleado.id == ev.evaluador_id).first()
        emp_nombre = _nombre_empleado(db, str(ev.empleado_id)) or "Un empleado"
        if evaluador_emp and evaluador_emp.usuario_id:
            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                usuario_id=str(evaluador_emp.usuario_id),
                tipo="evaluacion", categoria="Evaluación Completada",
                titulo="Evaluación completada",
                mensaje=f"{emp_nombre} completó la evaluación de {_tipo_label(ev.tipo)} — Período {ev.periodo}.",
                leido=False,
            ))
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


# ── Lote: crear evaluaciones para múltiples empleados ────────────────────────
class LoteIn(_BaseModel):
    tipo:          str
    periodo:       str
    fecha:         Optional[str] = None
    empleado_ids:  List[str] = []
    todos:         bool = False
    criterio_ids:  List[str] = []


class LoteOut(_BaseModel):
    creadas: int
    evaluaciones: List[EvaluacionOut]


@router.post("/lote", response_model=LoteOut, status_code=201)
def crear_lote(body: LoteIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "evaluacion", "crear")
    empresa_id = payload["empresa_id"]
    evaluador  = _empleado_actual(db, payload)
    if not evaluador:
        raise HTTPException(400, "El usuario no tiene ficha de empleado")

    if body.todos:
        emps = db.query(Empleado).filter(
            Empleado.empresa_id == empresa_id,
            Empleado.activo == True,          # noqa: E712
            Empleado.id != str(evaluador.id),
        ).all()
        ids_objetivo = [str(e.id) for e in emps]
    else:
        ids_objetivo = list(set(body.empleado_ids))

    if not ids_objetivo:
        raise HTTPException(400, "Debes seleccionar al menos un empleado")

    fecha_obj = _parse_date(body.fecha) or date.today()

    criterios = []
    if body.criterio_ids:
        criterios = db.query(CriterioEvaluacion).filter(
            CriterioEvaluacion.id.in_(body.criterio_ids),
            CriterioEvaluacion.empresa_id == empresa_id,
        ).all()

    resultados: List[EvaluacionOut] = []
    for emp_id in ids_objetivo:
        emp = db.query(Empleado).filter(
            Empleado.id == emp_id, Empleado.empresa_id == empresa_id).first()
        if not emp:
            continue

        ev = Evaluacion(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            empleado_id=emp_id, evaluador_id=str(evaluador.id),
            tipo=body.tipo, periodo=body.periodo,
            estado="enviada", fecha=fecha_obj,
        )
        db.add(ev)
        db.flush()

        for c in criterios:
            db.add(DetalleEvaluacion(
                id=str(_uuid.uuid4()), evaluacion_id=ev.id,
                criterio_id=str(c.id), puntaje=1, comentario=None,
            ))

        if emp.usuario_id:
            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empresa_id,
                usuario_id=str(emp.usuario_id),
                tipo="evaluacion", categoria="Nueva Evaluación",
                titulo="Nueva evaluación asignada",
                mensaje=f"Tienes una evaluación de {_tipo_label(body.tipo)} pendiente — Período {body.periodo}.",
                leido=False,
            ))

        resultados.append(_eval_out(db, ev, con_detalles=True))

    db.commit()
    return LoteOut(creadas=len(resultados), evaluaciones=resultados)
