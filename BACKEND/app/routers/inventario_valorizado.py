"""
Router: /logistica/inventario — valuación de inventario (Fase 5).

Endpoints de costeo que conviven con el flujo de logística existente sin
modificarlo: registran movimientos valorizados (ingreso/salida) que generan su
asiento automático, y exponen el kardex valorizado y el costo promedio vigente.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..services import costeo_inventario_service as costeo

router = APIRouter(prefix="/logistica/inventario", tags=["inventario-valorizado"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


class IngresoIn(BaseModel):
    material_id: str
    almacen_id: str
    cantidad: int
    costo_unitario: Decimal
    motivo: Optional[str] = None
    referencia_id: Optional[str] = None
    referencia_tipo: Optional[str] = None

    @field_validator("cantidad")
    @classmethod
    def _cant_pos(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("la cantidad debe ser mayor que 0")
        return v


class SalidaIn(BaseModel):
    material_id: str
    almacen_id: str
    cantidad: int
    motivo: Optional[str] = None
    referencia_id: Optional[str] = None
    referencia_tipo: Optional[str] = None

    @field_validator("cantidad")
    @classmethod
    def _cant_pos(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("la cantidad debe ser mayor que 0")
        return v


class MovimientoValorizadoOut(BaseModel):
    id: str
    material_id: str
    almacen_id: Optional[str] = None
    tipo: str
    cantidad: int
    costo_unitario: Optional[Decimal] = None
    valor_total: Optional[Decimal] = None
    asiento_id: Optional[str] = None


class CostoPromedioOut(BaseModel):
    material_id: str
    almacen_id: str
    cantidad_actual: Decimal
    costo_promedio_actual: Decimal
    valor_actual: Decimal


class KardexFilaOut(BaseModel):
    material_id: str
    almacen_id: Optional[str] = None
    saldo_valorizado: Decimal


def _mov_out(m) -> MovimientoValorizadoOut:
    return MovimientoValorizadoOut(
        id=str(m.id), material_id=str(m.material_id),
        almacen_id=(str(m.almacen_id) if m.almacen_id else None),
        tipo=m.tipo, cantidad=m.cantidad, costo_unitario=m.costo_unitario,
        valor_total=m.valor_total, asiento_id=(str(m.asiento_id) if m.asiento_id else None),
    )


@router.post("/ingresos", response_model=MovimientoValorizadoOut, status_code=201)
def registrar_ingreso(
    body: IngresoIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "inventario_valorizado", "registrar_movimiento")
    m = costeo.procesar_ingreso(
        db, payload["empresa_id"], body.material_id, body.almacen_id,
        cantidad=body.cantidad, costo_unitario=body.costo_unitario,
        fecha=datetime.utcnow(), responsable_id=_empleado_id(db, payload),
        motivo=body.motivo, referencia_id=body.referencia_id,
        referencia_tipo=body.referencia_tipo, creado_por_id=_empleado_id(db, payload),
    )
    return _mov_out(m)


@router.post("/salidas", response_model=MovimientoValorizadoOut, status_code=201)
def registrar_salida(
    body: SalidaIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "inventario_valorizado", "registrar_movimiento")
    m = costeo.procesar_salida(
        db, payload["empresa_id"], body.material_id, body.almacen_id,
        cantidad=body.cantidad, fecha=datetime.utcnow(),
        responsable_id=_empleado_id(db, payload), motivo=body.motivo,
        referencia_id=body.referencia_id, referencia_tipo=body.referencia_tipo,
        creado_por_id=_empleado_id(db, payload),
    )
    return _mov_out(m)


@router.get("/valorizacion", response_model=List[KardexFilaOut])
def valorizacion(
    almacen: Optional[str] = Query(None),
    material: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "inventario_valorizado", "ver")
    return [KardexFilaOut(**f) for f in costeo.kardex_valorizado(db, payload["empresa_id"], almacen, material)]


@router.get("/costo-promedio/{material_id}", response_model=CostoPromedioOut)
def costo_promedio(
    material_id: str,
    almacen_id: str = Query(...),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "inventario_valorizado", "ver")
    return CostoPromedioOut(**costeo.costo_promedio(db, payload["empresa_id"], material_id, almacen_id))
