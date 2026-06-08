"""
Router: /caja-chica (Fase 5 del módulo de finanzas).

Caja chica operativa con contabilización automática de cada movimiento
(via caja_chica_service → registrar_asiento). RBAC por (modulo='caja_chica',
accion) y filtro por la empresa del token en cada consulta.
"""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.caja_chica import CajaChica, MovimientoCaja
from ..schemas.caja_chica import (
    CajaChicaCreate, CajaChicaOut, MovimientoCajaCreate, MovimientoCajaOut,
)
from ..services import caja_chica_service as cc

router = APIRouter(prefix="/caja-chica", tags=["caja-chica"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


def _caja_out(db: Session, empresa_id: str, c: CajaChica,
              nombres: dict[str, str] | None = None) -> CajaChicaOut:
    ingresos, egresos, n = cc._totales(db, c.id)
    nombres = nombres if nombres is not None else cc.nombres_empleado(db, empresa_id, [str(c.responsable_id)])
    return CajaChicaOut(
        id=str(c.id), nombre=c.nombre, descripcion=c.descripcion,
        responsable_id=str(c.responsable_id),
        responsable_nombre=nombres.get(str(c.responsable_id)),
        proyecto_id=(str(c.proyecto_id) if c.proyecto_id else None),
        monto_asignado_referencial=c.monto_asignado_referencial,
        fecha_apertura=c.fecha_apertura, fecha_cierre=c.fecha_cierre,
        estado=c.estado, total_ingresos=ingresos, total_egresos=egresos,
        saldo_actual=ingresos - egresos, n_movimientos=n,
    )


def _mov_out(m: MovimientoCaja, nombres: dict[str, str],
             asientos: dict[str, str]) -> MovimientoCajaOut:
    return MovimientoCajaOut(
        id=str(m.id), caja_id=str(m.caja_id), tipo=m.tipo, monto=m.monto,
        descripcion=m.descripcion, concepto=m.concepto,
        comprobante_url=m.comprobante_url,
        registrado_por=str(m.registrado_por) if m.registrado_por else "",
        registrado_por_nombre=nombres.get(str(m.registrado_por)),
        fecha=m.fecha, asiento_id=asientos.get(str(m.id)),
    )


# ── Cajas ────────────────────────────────────────────────────────────────────
@router.get("", response_model=List[CajaChicaOut])
def listar_cajas(
    estado: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "caja_chica", "ver")
    empresa_id = payload["empresa_id"]
    q = db.query(CajaChica).filter(CajaChica.empresa_id == empresa_id)
    if estado:
        q = q.filter(CajaChica.estado == estado)
    cajas = q.order_by(CajaChica.fecha_apertura.desc()).all()
    nombres = cc.nombres_empleado(db, empresa_id, [str(c.responsable_id) for c in cajas])
    return [_caja_out(db, empresa_id, c, nombres) for c in cajas]


@router.post("", response_model=CajaChicaOut, status_code=201)
def crear_caja(
    body: CajaChicaCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "caja_chica", "gestionar")
    # Por defecto, el responsable es el empleado que crea la caja.
    if not body.responsable_id:
        body.responsable_id = _empleado_id(db, payload)
    c = cc.crear_caja(db, payload["empresa_id"], body)
    return _caja_out(db, payload["empresa_id"], c)


@router.get("/{caja_id}", response_model=CajaChicaOut)
def obtener_caja(
    caja_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "caja_chica", "ver")
    c = cc.get_caja(db, payload["empresa_id"], caja_id)
    return _caja_out(db, payload["empresa_id"], c)


@router.post("/{caja_id}/cerrar", response_model=CajaChicaOut)
def cerrar_caja(
    caja_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "caja_chica", "gestionar")
    c = cc.cerrar_caja(db, payload["empresa_id"], caja_id)
    return _caja_out(db, payload["empresa_id"], c)


# ── Movimientos ──────────────────────────────────────────────────────────────
@router.get("/{caja_id}/movimientos", response_model=List[MovimientoCajaOut])
def listar_movimientos(
    caja_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "caja_chica", "ver")
    empresa_id = payload["empresa_id"]
    movs = cc.listar_movimientos(db, empresa_id, caja_id)
    nombres = cc.nombres_empleado(db, empresa_id, [str(m.registrado_por) for m in movs])
    asientos = cc.asientos_por_movimiento(db, empresa_id, [str(m.id) for m in movs])
    return [_mov_out(m, nombres, asientos) for m in movs]


@router.post("/{caja_id}/movimientos", response_model=MovimientoCajaOut, status_code=201)
def registrar_movimiento(
    caja_id: str,
    body: MovimientoCajaCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "caja_chica", "registrar_movimiento")
    empresa_id = payload["empresa_id"]
    m = cc.registrar_movimiento(db, empresa_id, caja_id, body, _empleado_id(db, payload))
    nombres = cc.nombres_empleado(db, empresa_id, [str(m.registrado_por)])
    asientos = cc.asientos_por_movimiento(db, empresa_id, [str(m.id)])
    return _mov_out(m, nombres, asientos)
