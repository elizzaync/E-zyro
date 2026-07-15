"""
Router: /programacion-campo — cuadrilla diaria por proyecto.

Soporte para HU-54 (horas hombre por proyecto): el fichaje de asistencia no
lleva proyecto (y no debe — es control horario, no asignación). Quién trabajó
en qué proyecto cada día lo decide Operaciones acá, aparte del fichaje; el
empleado solo confirma con un tap desde el celular.
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_no_tecnico
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.programacion_campo import ProgramacionCampo, ProgramacionEmpleado
from ..models.proyecto import Proyecto
from ..models.usuario import Usuario

router = APIRouter(prefix="/programacion-campo", tags=["programacion-campo"])


class ProgramacionIn(BaseModel):
    proyecto_id: str
    fecha: date
    tipo: str = "servicio"
    descripcion: Optional[str] = None
    empleado_ids: List[str] = []


def _to_out(pc: ProgramacionCampo, db: Session) -> dict:
    filas = (
        db.query(ProgramacionEmpleado, Empleado, Usuario)
        .join(Empleado, Empleado.id == ProgramacionEmpleado.empleado_id)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(ProgramacionEmpleado.programacion_id == pc.id)
        .all()
    )
    proyecto = db.query(Proyecto.nombre_proyecto).filter(Proyecto.id == pc.proyecto_id).first()
    return {
        "id": str(pc.id),
        "proyecto_id": str(pc.proyecto_id),
        "nombre_proyecto": proyecto.nombre_proyecto if proyecto else "",
        "fecha": pc.fecha.isoformat(),
        "tipo": pc.tipo,
        "descripcion": pc.descripcion,
        "empleados": [
            {
                "programacion_empleado_id": str(pe.id),
                "empleado_id": str(pe.empleado_id),
                "nombre": f"{u.nombre} {u.apellido}".strip(),
                "confirmado_movil": pe.confirmacion_movil,
            }
            for pe, e, u in filas
        ],
    }


@router.post("", status_code=201)
def crear_programacion(
    body: ProgramacionIn,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Crea/edita la cuadrilla de un dia para un proyecto. Si ya existe una
    fila para (fecha, proyecto_id, tipo) la actualiza (upsert) en vez de
    duplicar — mismo criterio que /servicio/{id}/configurar con ProyectoMiembro."""
    exigir_no_tecnico(payload, "Técnico no puede asignar la cuadrilla de campo")
    empresa_id = payload["empresa_id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id == body.proyecto_id, Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    registrado_por = db.query(Empleado).filter(
        Empleado.usuario_id == payload["id"], Empleado.empresa_id == empresa_id,
    ).first()
    if not registrado_por:
        raise HTTPException(
            status_code=422,
            detail="Tu usuario no tiene ficha de empleado; no se puede registrar la programación.",
        )

    empleado_ids = list(dict.fromkeys(body.empleado_ids))  # dedup, conserva orden
    if empleado_ids:
        count = db.query(Empleado.id).filter(
            Empleado.id.in_(empleado_ids), Empleado.empresa_id == empresa_id,
        ).count()
        if count != len(empleado_ids):
            raise HTTPException(
                status_code=422,
                detail="Uno o más empleados no existen o no pertenecen a esta empresa.",
            )

    pc = db.query(ProgramacionCampo).filter(
        ProgramacionCampo.empresa_id == empresa_id,
        ProgramacionCampo.proyecto_id == body.proyecto_id,
        ProgramacionCampo.fecha == body.fecha,
        ProgramacionCampo.tipo == body.tipo,
    ).first()

    if pc:
        pc.descripcion = body.descripcion
        pc.cantidad_personas = len(empleado_ids)
        db.query(ProgramacionEmpleado).filter(
            ProgramacionEmpleado.programacion_id == pc.id,
            ProgramacionEmpleado.empleado_id.notin_(empleado_ids) if empleado_ids else True,
        ).delete(synchronize_session=False)
    else:
        pc = ProgramacionCampo(
            id=str(_uuid.uuid4()),
            proyecto_id=body.proyecto_id,
            empresa_id=empresa_id,
            tipo=body.tipo,
            descripcion=body.descripcion,
            fecha=body.fecha,
            cantidad_personas=len(empleado_ids),
            registrado_por=registrado_por.id,
        )
        db.add(pc)
        db.flush()

    existentes = {
        str(pe.empleado_id)
        for pe in db.query(ProgramacionEmpleado).filter(ProgramacionEmpleado.programacion_id == pc.id)
    }
    nuevos = [eid for eid in empleado_ids if eid not in existentes]
    for eid in nuevos:
        db.add(ProgramacionEmpleado(id=str(_uuid.uuid4()), programacion_id=pc.id, empleado_id=eid))
    db.commit()
    db.refresh(pc)

    if nuevos:
        try:
            from ..services.fcm_service import notificar_usuario
            usuarios = db.query(Empleado.usuario_id).filter(Empleado.id.in_(nuevos)).all()
            for (usuario_id,) in usuarios:
                if usuario_id:
                    notificar_usuario(
                        db, empresa_id=empresa_id, usuario_id=usuario_id,
                        titulo="Nueva asignación de campo",
                        mensaje=f"Hoy trabajas en '{proyecto.nombre_proyecto}' ({body.fecha.isoformat()}).",
                        tipo="programacion", categoria="operaciones",
                        referencia_id=str(pc.id), referencia_tabla="programacion_campo",
                    )
            db.commit()
        except Exception:
            db.rollback()

    return _to_out(pc, db)


@router.get("")
def listar_programacion(
    fecha: Optional[date] = None,
    proyecto_id: Optional[str] = None,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Para Operaciones: revisar/editar el plan de un día o proyecto."""
    exigir_no_tecnico(payload, "Técnico no puede ver la programación de campo")
    empresa_id = payload["empresa_id"]
    q = db.query(ProgramacionCampo).filter(ProgramacionCampo.empresa_id == empresa_id)
    if fecha:
        q = q.filter(ProgramacionCampo.fecha == fecha)
    if proyecto_id:
        q = q.filter(ProgramacionCampo.proyecto_id == proyecto_id)
    filas = q.order_by(ProgramacionCampo.fecha.desc()).all()
    return [_to_out(pc, db) for pc in filas]


@router.get("/mia")
def mi_programacion(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Asignaciones del empleado logueado desde hoy en adelante — base del
    widget 'Hoy trabajas en...' del inicio."""
    empresa_id = payload["empresa_id"]
    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == payload["id"], Empleado.empresa_id == empresa_id,
    ).first()
    if not empleado:
        return []

    filas = (
        db.query(ProgramacionEmpleado, ProgramacionCampo, Proyecto)
        .join(ProgramacionCampo, ProgramacionCampo.id == ProgramacionEmpleado.programacion_id)
        .join(Proyecto, Proyecto.id == ProgramacionCampo.proyecto_id)
        .filter(
            ProgramacionEmpleado.empleado_id == empleado.id,
            ProgramacionCampo.empresa_id == empresa_id,
            ProgramacionCampo.fecha >= date.today(),
        )
        .order_by(ProgramacionCampo.fecha.asc())
        .all()
    )
    return [
        {
            "programacion_empleado_id": str(pe.id),
            "proyecto_id": str(pc.proyecto_id),
            "nombre_proyecto": p.nombre_proyecto,
            "fecha": pc.fecha.isoformat(),
            "tipo": pc.tipo,
            "confirmado_movil": pe.confirmacion_movil,
        }
        for pe, pc, p in filas
    ]


@router.post("/{programacion_empleado_id}/confirmar")
def confirmar_programacion(
    programacion_empleado_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """El empleado confirma su asignación del día — un tap, sin fichaje."""
    empresa_id = payload["empresa_id"]
    empleado = db.query(Empleado).filter(
        Empleado.usuario_id == payload["id"], Empleado.empresa_id == empresa_id,
    ).first()
    if not empleado:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    pe = (
        db.query(ProgramacionEmpleado)
        .join(ProgramacionCampo, ProgramacionCampo.id == ProgramacionEmpleado.programacion_id)
        .filter(
            ProgramacionEmpleado.id == programacion_empleado_id,
            ProgramacionEmpleado.empleado_id == empleado.id,
            ProgramacionCampo.empresa_id == empresa_id,
        )
        .first()
    )
    if not pe:
        raise HTTPException(status_code=404, detail="Asignación no encontrada")

    pe.confirmacion_movil = True
    pe.fecha_confirmacion = datetime.utcnow()
    db.commit()
    return {"ok": True}
