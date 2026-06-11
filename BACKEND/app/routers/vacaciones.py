"""
Router: /vacaciones — Punto 3.3 (RR.HH.), control de vacaciones por ley (Perú).
Régimen parametrizable por empresa (General 30 d/año, REMYPE 15 d/año) con tope
de acumulación. Saldo derivado: devengo mensual desde fecha_ingreso menos los
días aprobados. Sin cálculo de pago vacacional.
Lecturas: empresa del token. Escrituras: RBAC dominio 'vacaciones'.
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.vacaciones import ConfigVacaciones, SolicitudVacaciones
from ..services.fcm_service import notificar_usuario
from ..schemas.vacaciones import (
    ConfigIn, ConfigOut, SaldoOut, SolicitudIn, SolicitudOut,
)

router = APIRouter(prefix="/vacaciones", tags=["vacaciones"])

# Días/año por régimen (Perú). 'otro' usa el valor explícito enviado.
REGIMEN_DIAS = {"general": 30, "remype": 15}
TOPE_DEFECTO = 30


def _parse_date(s: str) -> date:
    return date.fromisoformat(s[:10])


def _meses_servicio(ingreso: Optional[date], hoy: date) -> int:
    if not ingreso:
        return 0
    meses = (hoy.year - ingreso.year) * 12 + (hoy.month - ingreso.month)
    if hoy.day < ingreso.day:
        meses -= 1
    return max(0, meses)


def _get_config(db: Session, empresa_id: str) -> ConfigVacaciones:
    cfg = db.query(ConfigVacaciones).filter(ConfigVacaciones.empresa_id == empresa_id).first()
    if not cfg:
        cfg = ConfigVacaciones(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            regimen="general", dias_por_anio=REGIMEN_DIAS["general"], tope_acumulacion=TOPE_DEFECTO,
        )
        db.add(cfg)
        db.commit()
    return cfg


def _nombre(db: Session, empleado: Empleado) -> Optional[str]:
    row = db.query(Usuario.nombre, Usuario.apellido).filter(Usuario.id == empleado.usuario_id).first()
    return f"{row[0]} {row[1]}".strip() if row else None


def _gozado(db: Session, empresa_id: str, empleado_id: str) -> int:
    total = (
        db.query(func.coalesce(func.sum(SolicitudVacaciones.dias), 0))
        .filter(SolicitudVacaciones.empresa_id == empresa_id,
                SolicitudVacaciones.empleado_id == empleado_id,
                SolicitudVacaciones.estado == "aprobada")
        .scalar()
    )
    return int(total or 0)


def _saldo(db: Session, empresa_id: str, emp: Empleado, cfg: ConfigVacaciones) -> SaldoOut:
    hoy = date.today()
    meses = _meses_servicio(emp.fecha_ingreso, hoy)
    devengado = round(cfg.dias_por_anio * meses / 12.0, 2)
    gozado = _gozado(db, empresa_id, str(emp.id))
    disponible = min(devengado - gozado, float(cfg.tope_acumulacion))
    if disponible < 0:
        disponible = 0.0
    return SaldoOut(
        empleado_id=str(emp.id), empleado_nombre=_nombre(db, emp),
        fecha_ingreso=(str(emp.fecha_ingreso) if emp.fecha_ingreso else None),
        meses_servicio=meses, dias_por_anio=cfg.dias_por_anio,
        devengado=devengado, gozado=gozado, disponible=round(disponible, 2),
        tope_acumulacion=cfg.tope_acumulacion,
    )


def _empleado_actual(db: Session, payload: dict) -> Optional[Empleado]:
    return (
        db.query(Empleado)
        .filter(Empleado.usuario_id == payload.get("id"),
                Empleado.empresa_id == payload["empresa_id"])
        .first()
    )


# ── Configuración ────────────────────────────────────────────────────────────
@router.get("/config", response_model=ConfigOut)
def obtener_config(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    cfg = _get_config(db, payload["empresa_id"])
    return ConfigOut(regimen=cfg.regimen, dias_por_anio=cfg.dias_por_anio,
                     tope_acumulacion=cfg.tope_acumulacion)


@router.put("/config", response_model=ConfigOut)
def actualizar_config(body: ConfigIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "vacaciones", "configurar")
    cfg = _get_config(db, payload["empresa_id"])
    cfg.regimen = body.regimen
    # Días/año: explícito o derivado del régimen (general/remype). 'otro' exige valor.
    if body.dias_por_anio is not None:
        cfg.dias_por_anio = body.dias_por_anio
    elif body.regimen in REGIMEN_DIAS:
        cfg.dias_por_anio = REGIMEN_DIAS[body.regimen]
    elif body.regimen == "otro":
        raise HTTPException(status_code=422, detail="Régimen 'otro' requiere dias_por_anio")
    cfg.tope_acumulacion = body.tope_acumulacion if body.tope_acumulacion is not None else cfg.tope_acumulacion
    cfg.updated_at = datetime.utcnow()
    db.commit()
    return ConfigOut(regimen=cfg.regimen, dias_por_anio=cfg.dias_por_anio,
                     tope_acumulacion=cfg.tope_acumulacion)


# ── Saldos ───────────────────────────────────────────────────────────────────
@router.get("/saldos", response_model=List[SaldoOut])
def listar_saldos(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    cfg = _get_config(db, empresa_id)
    emps = (
        db.query(Empleado)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)  # noqa: E712
        .all()
    )
    saldos = [_saldo(db, empresa_id, e, cfg) for e in emps]
    saldos.sort(key=lambda s: (s.empleado_nombre or ""))
    return saldos


@router.get("/saldo/{empleado_id}", response_model=SaldoOut)
def saldo_empleado(empleado_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    return _saldo(db, empresa_id, emp, _get_config(db, empresa_id))


# ── Solicitudes ──────────────────────────────────────────────────────────────
def _sol_out(db: Session, s: SolicitudVacaciones) -> SolicitudOut:
    nombre = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == s.empleado_id).first()
    )
    return SolicitudOut(
        id=str(s.id), empleado_id=str(s.empleado_id),
        empleado_nombre=(f"{nombre[0]} {nombre[1]}".strip() if nombre else None),
        fecha_inicio=(str(s.fecha_inicio) if s.fecha_inicio else None),
        fecha_fin=(str(s.fecha_fin) if s.fecha_fin else None),
        dias=int(s.dias), estado=s.estado, motivo=s.motivo,
        fecha_resolucion=(s.fecha_resolucion.isoformat() if s.fecha_resolucion else None),
    )


@router.get("/solicitudes", response_model=List[SolicitudOut])
def listar_solicitudes(
    empleado_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(SolicitudVacaciones).filter(
        SolicitudVacaciones.empresa_id == payload["empresa_id"])
    if empleado_id:
        qry = qry.filter(SolicitudVacaciones.empleado_id == empleado_id)
    if estado:
        qry = qry.filter(SolicitudVacaciones.estado == estado)
    rows = qry.order_by(SolicitudVacaciones.created_at.desc()).limit(500).all()
    return [_sol_out(db, s) for s in rows]


@router.post("/solicitudes", response_model=SolicitudOut, status_code=201)
def crear_solicitud(body: SolicitudIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    self_emp = _empleado_actual(db, payload)
    # Auto-solicitud (propio): libre para cualquier empleado con ficha.
    # Solicitar por OTRO empleado: requiere permiso vacaciones:solicitar.
    if body.empleado_id and (not self_emp or body.empleado_id != str(self_emp.id)):
        exigir_permiso(db, payload, "vacaciones", "solicitar")
        emp = db.query(Empleado).filter(
            Empleado.id == body.empleado_id, Empleado.empresa_id == empresa_id).first()
    else:
        emp = self_emp
    if not emp:
        raise HTTPException(status_code=404, detail="Tu usuario no tiene ficha de empleado")
    ini = _parse_date(body.fecha_inicio)
    fin = _parse_date(body.fecha_fin)
    if fin < ini:
        raise HTTPException(status_code=422, detail="fecha_fin no puede ser anterior a fecha_inicio")
    dias = (fin - ini).days + 1
    s = SolicitudVacaciones(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, empleado_id=str(emp.id),
        fecha_inicio=ini, fecha_fin=fin, dias=dias, estado="pendiente",
        motivo=body.motivo, solicitado_por_id=payload.get("id"),
    )
    db.add(s)
    db.commit()
    return _sol_out(db, s)


# ── Autoservicio del empleado (token) ────────────────────────────────────────
@router.get("/mi-saldo", response_model=SaldoOut)
def mi_saldo(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    emp = _empleado_actual(db, payload)
    if not emp:
        raise HTTPException(status_code=404, detail="Tu usuario no tiene ficha de empleado")
    return _saldo(db, empresa_id, emp, _get_config(db, empresa_id))


@router.get("/mis-solicitudes", response_model=List[SolicitudOut])
def mis_solicitudes(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    emp = _empleado_actual(db, payload)
    if not emp:
        return []
    rows = (
        db.query(SolicitudVacaciones)
        .filter(SolicitudVacaciones.empresa_id == payload["empresa_id"],
                SolicitudVacaciones.empleado_id == str(emp.id))
        .order_by(SolicitudVacaciones.created_at.desc())
        .limit(200).all()
    )
    return [_sol_out(db, s) for s in rows]


def _resolver(db: Session, payload: dict, sol_id: str, nuevo_estado: str) -> SolicitudOut:
    empresa_id = payload["empresa_id"]
    s = db.query(SolicitudVacaciones).filter(
        SolicitudVacaciones.id == sol_id, SolicitudVacaciones.empresa_id == empresa_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if s.estado != "pendiente":
        raise HTTPException(status_code=409, detail=f"La solicitud ya está {s.estado}")
    if nuevo_estado == "aprobada":
        # Validar saldo disponible antes de aprobar
        emp = db.query(Empleado).filter(Empleado.id == s.empleado_id).first()
        cfg = _get_config(db, empresa_id)
        saldo = _saldo(db, empresa_id, emp, cfg)
        if s.dias > saldo.disponible:
            raise HTTPException(
                status_code=409,
                detail=f"Saldo insuficiente: solicita {s.dias} d, disponible {saldo.disponible} d")
    s.estado = nuevo_estado
    s.resuelto_por_id = payload.get("id")
    s.fecha_resolucion = datetime.utcnow()
    db.commit()

    # Notificar al solicitante el resultado de su solicitud.
    try:
        emp = db.query(Empleado).filter(Empleado.id == s.empleado_id).first()
        if emp and emp.usuario_id:
            if nuevo_estado == "aprobada":
                titulo = "Vacaciones aprobadas"
                mensaje = (f"Tu solicitud de {s.dias} día(s) "
                           f"({s.fecha_inicio.isoformat()} al {s.fecha_fin.isoformat()}) fue aprobada.")
            else:
                titulo = "Vacaciones rechazadas"
                mensaje = (f"Tu solicitud de {s.dias} día(s) "
                           f"({s.fecha_inicio.isoformat()} al {s.fecha_fin.isoformat()}) fue rechazada.")
            notificar_usuario(
                db, empresa_id=empresa_id, usuario_id=emp.usuario_id,
                titulo=titulo, mensaje=mensaje,
                tipo="recordatorio", categoria="vacaciones",
                referencia_tabla=f"vacaciones:{s.id}",
            )
            db.commit()
    except Exception:
        db.rollback()

    return _sol_out(db, s)


@router.post("/solicitudes/{sol_id}/aprobar", response_model=SolicitudOut)
def aprobar(sol_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "vacaciones", "aprobar")
    return _resolver(db, payload, sol_id, "aprobada")


@router.post("/solicitudes/{sol_id}/rechazar", response_model=SolicitudOut)
def rechazar(sol_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "vacaciones", "rechazar")
    return _resolver(db, payload, sol_id, "rechazada")
