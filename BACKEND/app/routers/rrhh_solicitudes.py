"""
HU-30 Fase 2 — Bandeja de Solicitudes Laborales

Endpoints:
  GET /rrhh/solicitudes                 lista con JOIN empleado+usuario
  PUT /rrhh/solicitudes/{id}/evaluar    aprueba o rechaza (admin / jefe RRHH)
"""
from __future__ import annotations

import uuid as _uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token
from app.core.permisos import exigir_no_tecnico
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.empleado import Empleado
from app.models.usuario import Usuario
from app.services.fcm_service import notificar_usuario

router = APIRouter(tags=["RRHH · Solicitudes"])

_ESTADOS_VALIDOS = {"aprobada", "rechazada"}

# Tipos que pertenecen al módulo de Asistencia, NO a la bandeja de solicitudes
_TIPOS_ASISTENCIA = {"justificacion_tardanza", "permanencia_extra"}


# ── Schemas ───────────────────────────────────────────────────────────────────

class EvaluarIn(BaseModel):
    estado: str
    observacion: str

    @field_validator("estado")
    @classmethod
    def _validar_estado(cls, v: str) -> str:
        if v not in _ESTADOS_VALIDOS:
            raise ValueError("estado debe ser 'aprobada' o 'rechazada'")
        return v

    @field_validator("observacion")
    @classmethod
    def _validar_observacion(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("La observación es obligatoria")
        return v.strip()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _sol_dict(sol: SolicitudLaboral, emp: Empleado, usr: Usuario) -> dict:
    nombre = f"{usr.nombre} {usr.apellido}".strip()
    iniciales = (
        (usr.nombre[0] if usr.nombre else "") +
        (usr.apellido[0] if usr.apellido else "")
    ).upper() or "?"
    dias = None
    if sol.fecha_inicio and sol.fecha_fin:
        dias = (sol.fecha_fin - sol.fecha_inicio).days + 1
    return {
        "id": sol.id,
        "tipo": sol.tipo,
        "estado": sol.estado,
        "descripcion": sol.descripcion or "",
        "fecha_inicio": sol.fecha_inicio.isoformat() if sol.fecha_inicio else None,
        "fecha_fin": sol.fecha_fin.isoformat() if sol.fecha_fin else None,
        "dias": dias,
        "url_pdf": sol.url_pdf or None,
        "observacion": sol.observacion or None,
        "aprobado_por": sol.aprobado_por or None,
        "fecha_aprobacion": sol.fecha_aprobacion.isoformat() if sol.fecha_aprobacion else None,
        "created_at": sol.created_at.isoformat() if sol.created_at else None,
        "empleado": {
            "id": emp.id,
            "nombreCompleto": nombre,
            "cargo": emp.cargo,
            "area": emp.area or "",
            "iniciales": iniciales,
            "fotoUrl": usr.foto_url or "",
        },
    }


# ── 1. GET /rrhh/solicitudes ──────────────────────────────────────────────────

@router.get("/rrhh/solicitudes")
def listar_solicitudes(
    categoria: Optional[str] = Query(None, description="'vacaciones' | 'permisos'"),
    estado: Optional[str] = Query(None, description="pendiente | aprobada | rechazada"),
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    q = (
        db.query(SolicitudLaboral, Empleado, Usuario)
        .join(Empleado, Empleado.id == SolicitudLaboral.empleado_id)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(
            SolicitudLaboral.empresa_id == empresa_id,
            ~SolicitudLaboral.tipo.in_(list(_TIPOS_ASISTENCIA)),
        )
    )

    if categoria == "vacaciones":
        q = q.filter(SolicitudLaboral.tipo.ilike("vacaciones"))
    elif categoria == "permisos":
        q = q.filter(~SolicitudLaboral.tipo.ilike("vacaciones"))

    if estado and estado in {"pendiente", "aprobada", "rechazada"}:
        q = q.filter(SolicitudLaboral.estado == estado)

    rows = q.order_by(SolicitudLaboral.created_at.desc()).all()

    return {
        "solicitudes": [_sol_dict(sol, emp, usr) for sol, emp, usr in rows]
    }


# ── 2. PUT /rrhh/solicitudes/{id}/evaluar ────────────────────────────────────

@router.put("/rrhh/solicitudes/{sol_id}/evaluar")
def evaluar_solicitud(
    sol_id: str,
    body: EvaluarIn,
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_no_tecnico(payload, "Solo el personal de RRHH puede evaluar solicitudes")
    empresa_id = payload["empresa_id"]
    evaluador_id = payload["id"]

    sol = db.query(SolicitudLaboral).filter(
        SolicitudLaboral.id == sol_id,
        SolicitudLaboral.empresa_id == empresa_id,
    ).first()
    if not sol:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")

    if sol.estado != "pendiente":
        raise HTTPException(
            status_code=409,
            detail=f"La solicitud ya fue evaluada (estado actual: {sol.estado})",
        )

    sol.estado = body.estado
    sol.observacion = body.observacion
    sol.aprobado_por = evaluador_id
    sol.fecha_aprobacion = datetime.utcnow()
    sol.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(sol)

    # Notificar al empleado solicitante
    emp = db.query(Empleado).filter(Empleado.id == sol.empleado_id).first()
    if emp:
        accion = "aprobada" if sol.estado == "aprobada" else "rechazada"
        tipo_label = sol.tipo.replace("_", " ").capitalize()
        titulo = f"Solicitud {accion}"
        mensaje = (
            f"Tu solicitud de {tipo_label} fue {accion}. "
            f"Observación: {sol.observacion}"
        )
        notificar_usuario(
            db=db,
            empresa_id=empresa_id,
            usuario_id=emp.usuario_id,
            titulo=titulo,
            mensaje=mensaje,
            tipo="warning",
            categoria="rrhh",
            referencia_id=sol.id,
            referencia_tabla="solicitud_laboral",
        )
        db.commit()

    return {
        "id": sol.id,
        "estado": sol.estado,
        "observacion": sol.observacion,
        "fecha_aprobacion": sol.fecha_aprobacion.isoformat(),
        "mensaje": f"Solicitud {sol.estado} correctamente",
    }
