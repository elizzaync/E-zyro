"""
Router: /presupuesto — presupuesto anual por cuenta/grupo PCGE.

Presupuesta códigos PCGE (detalle '6311' o grupo '63') por año; la ejecución
se calcula en vivo contra el libro mayor (sin cierre de ejercicio, para que un
año cerrado siga mostrando su ejecución real). RBAC: contabilidad ver/configurar.
"""
from __future__ import annotations

from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.contabilidad import CuentaContable
from ..models.presupuesto import PresupuestoAnual
from ..services.reportes_financieros_service import _saldos_por_cuenta

router = APIRouter(prefix="/presupuesto", tags=["presupuesto"])

CERO = Decimal("0.00")


class LineaIn(BaseModel):
    cuenta_codigo: str
    monto_anual: Decimal
    notas: Optional[str] = None


class PresupuestoIn(BaseModel):
    lineas: List[LineaIn]


class LineaOut(BaseModel):
    cuenta_codigo: str
    nombre: str
    monto_anual: Decimal
    ejecutado: Decimal
    disponible: Decimal
    ejecucion_pct: Optional[Decimal] = None
    notas: Optional[str] = None


class PresupuestoOut(BaseModel):
    anio: int
    lineas: List[LineaOut]
    total_presupuestado: Decimal
    total_ejecutado: Decimal


def _nombre_cuenta(db: Session, empresa_id: str, codigo: str) -> str:
    c = db.query(CuentaContable.nombre).filter(
        CuentaContable.empresa_id == empresa_id,
        CuentaContable.codigo == codigo).first()
    if c:
        return c.nombre
    # Grupo (prefijo): usa el nombre de la primera cuenta que cuelga de él.
    hijo = (
        db.query(CuentaContable.nombre)
        .filter(CuentaContable.empresa_id == empresa_id,
                CuentaContable.codigo.like(f"{codigo}%"))
        .order_by(CuentaContable.codigo).first()
    )
    return f"Grupo {codigo}" + (f" ({hijo.nombre}…)" if hijo else "")


@router.get("/{anio}", response_model=PresupuestoOut)
def obtener_presupuesto(
    anio: int,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    empresa_id = payload["empresa_id"]
    lineas_bd = (
        db.query(PresupuestoAnual)
        .filter(PresupuestoAnual.empresa_id == empresa_id,
                PresupuestoAnual.anio == anio)
        .order_by(PresupuestoAnual.cuenta_codigo)
        .all()
    )

    # Ejecución del año por cuenta de detalle (sin el asiento de cierre).
    from datetime import date as _date
    saldos = _saldos_por_cuenta(
        db, empresa_id,
        desde=_date(anio, 1, 1), hasta=_date(anio, 12, 31),
        excluir_origenes=("cierre_ejercicio",),
    )

    def ejecutado_de(prefijo: str) -> Decimal:
        total = CERO
        for codigo, _n, tipo, _nat, td, tc in saldos:
            if not codigo.startswith(prefijo):
                continue
            td, tc = Decimal(str(td)), Decimal(str(tc))
            # Ingresos acumulan en haber; gastos y demás, en debe.
            total += (tc - td) if tipo == "ingreso" else (td - tc)
        return total.quantize(Decimal("0.01"))

    out, tot_pres, tot_ejec = [], CERO, CERO
    for l in lineas_bd:
        monto = Decimal(str(l.monto_anual))
        ejec = ejecutado_de(l.cuenta_codigo)
        tot_pres += monto
        tot_ejec += ejec
        out.append(LineaOut(
            cuenta_codigo=l.cuenta_codigo,
            nombre=_nombre_cuenta(db, empresa_id, l.cuenta_codigo),
            monto_anual=monto, ejecutado=ejec,
            disponible=(monto - ejec).quantize(Decimal("0.01")),
            ejecucion_pct=((ejec / monto * 100).quantize(Decimal("0.01"))
                           if monto > CERO else None),
            notas=l.notas,
        ))
    return PresupuestoOut(anio=anio, lineas=out,
                          total_presupuestado=tot_pres, total_ejecutado=tot_ejec)


@router.put("/{anio}", response_model=PresupuestoOut)
def guardar_presupuesto(
    anio: int, body: PresupuestoIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Reemplaza el presupuesto del año (upsert completo, simple y auditable)."""
    exigir_permiso(db, payload, "contabilidad", "configurar")
    empresa_id = payload["empresa_id"]

    vistos = set()
    for l in body.lineas:
        codigo = l.cuenta_codigo.strip()
        if not codigo:
            raise HTTPException(status_code=422, detail="Hay una línea sin código de cuenta.")
        if codigo in vistos:
            raise HTTPException(status_code=422, detail=f"Código repetido: {codigo}.")
        vistos.add(codigo)
        if l.monto_anual < 0:
            raise HTTPException(status_code=422, detail=f"Monto negativo en {codigo}.")
        existe = db.query(CuentaContable.id).filter(
            CuentaContable.empresa_id == empresa_id,
            CuentaContable.codigo.like(f"{codigo}%")).first()
        if not existe:
            raise HTTPException(status_code=422,
                                detail=f"Ninguna cuenta del plan empieza con '{codigo}'.")

    db.query(PresupuestoAnual).filter(
        PresupuestoAnual.empresa_id == empresa_id,
        PresupuestoAnual.anio == anio).delete()
    for l in body.lineas:
        db.add(PresupuestoAnual(
            empresa_id=empresa_id, anio=anio,
            cuenta_codigo=l.cuenta_codigo.strip(),
            monto_anual=l.monto_anual, notas=l.notas,
        ))
    db.commit()
    return obtener_presupuesto(anio, payload, db)
