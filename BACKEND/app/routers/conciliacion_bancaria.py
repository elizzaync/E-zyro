"""
Router: /conciliacion-bancaria (Fase 5 del módulo de finanzas).

Cuentas bancarias de la empresa (cada una vinculada a su cuenta de Bancos del
PCGE), carga del extracto (manual o import CSV desde el cliente) y conciliación
1-a-1 de cada movimiento contra un asiento del libro mayor. RBAC por
(modulo='conciliacion_bancaria', accion) y filtro por empresa del token.
"""
from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.contabilidad import CuentaContable
from ..models.conciliacion_bancaria import CuentaBancaria, MovimientoBancario
from ..schemas.conciliacion_bancaria import (
    CuentaBancariaCreate, CuentaBancariaUpdate, CuentaBancariaOut,
    MovimientoBancarioCreate, MovimientoBancarioOut, ImportarMovimientosIn,
    SugerenciaAsiento, ConciliarIn, ResumenConciliacion,
)
from ..services import conciliacion_bancaria_service as cb

router = APIRouter(prefix="/conciliacion-bancaria", tags=["conciliacion-bancaria"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


def _cuenta_out(db: Session, empresa_id: str, c: CuentaBancaria,
                cuentas_pcge: dict[str, CuentaContable] | None = None) -> CuentaBancariaOut:
    if cuentas_pcge is not None:
        pc = cuentas_pcge.get(str(c.cuenta_contable_id))
    else:
        pc = db.query(CuentaContable).filter(CuentaContable.id == c.cuenta_contable_id).first()
    sb = cb.saldo_banco(db, c.id)
    sl = cb.saldo_libros(db, empresa_id, c.cuenta_contable_id)
    return CuentaBancariaOut(
        id=str(c.id), banco=c.banco, numero_cuenta=c.numero_cuenta, moneda=c.moneda,
        cuenta_contable_id=str(c.cuenta_contable_id),
        cuenta_contable_codigo=(pc.codigo if pc else None),
        cuenta_contable_nombre=(pc.nombre if pc else None),
        alias=c.alias, activo=bool(c.activo),
        saldo_banco=sb, saldo_libros=sl, diferencia=sb - sl,
        n_pendientes=cb.n_pendientes(db, c.id),
    )


def _mov_out(m: MovimientoBancario, nombres: dict[str, str],
             numeros: dict[str, str]) -> MovimientoBancarioOut:
    return MovimientoBancarioOut(
        id=str(m.id), cuenta_bancaria_id=str(m.cuenta_bancaria_id), fecha=m.fecha,
        descripcion=m.descripcion, referencia=m.referencia, tipo=m.tipo, monto=m.monto,
        estado=m.estado, origen_carga=m.origen_carga,
        asiento_id=(str(m.asiento_id) if m.asiento_id else None),
        asiento_numero=numeros.get(str(m.asiento_id)) if m.asiento_id else None,
        conciliado_por_nombre=nombres.get(str(m.conciliado_por_id)) if m.conciliado_por_id else None,
        conciliado_at=m.conciliado_at,
    )


# ── Cuentas bancarias ────────────────────────────────────────────────────────
@router.get("/cuentas", response_model=List[CuentaBancariaOut])
def listar_cuentas(
    solo_activas: bool = Query(False),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "ver")
    empresa_id = payload["empresa_id"]
    cuentas = cb.listar_cuentas(db, empresa_id, solo_activas)
    # Sin cuentas → no consultar el PCGE. El placeholder ["-"] rompía con
    # 'invalid input syntax for type uuid: "-"' (columna id es UUID nativo),
    # devolviendo 500 cada vez que la empresa no tenía cuentas bancarias.
    ids_pcge = [x.cuenta_contable_id for x in cuentas]
    pcge = {
        str(c.id): c for c in db.query(CuentaContable).filter(
            CuentaContable.id.in_(ids_pcge)
        ).all()
    } if ids_pcge else {}
    return [_cuenta_out(db, empresa_id, c, pcge) for c in cuentas]


@router.post("/cuentas", response_model=CuentaBancariaOut, status_code=201)
def crear_cuenta(
    body: CuentaBancariaCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "gestionar")
    c = cb.crear_cuenta(db, payload["empresa_id"], body)
    return _cuenta_out(db, payload["empresa_id"], c)


@router.get("/cuentas/{cuenta_id}", response_model=CuentaBancariaOut)
def obtener_cuenta(
    cuenta_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "ver")
    c = cb.get_cuenta(db, payload["empresa_id"], cuenta_id)
    return _cuenta_out(db, payload["empresa_id"], c)


@router.put("/cuentas/{cuenta_id}", response_model=CuentaBancariaOut)
def actualizar_cuenta(
    cuenta_id: str, body: CuentaBancariaUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "gestionar")
    c = cb.actualizar_cuenta(db, payload["empresa_id"], cuenta_id, body)
    return _cuenta_out(db, payload["empresa_id"], c)


@router.get("/cuentas/{cuenta_id}/resumen", response_model=ResumenConciliacion)
def resumen_cuenta(
    cuenta_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "ver")
    return ResumenConciliacion(**cb.resumen(db, payload["empresa_id"], cuenta_id))


# ── Movimientos del extracto ─────────────────────────────────────────────────
@router.get("/cuentas/{cuenta_id}/movimientos", response_model=List[MovimientoBancarioOut])
def listar_movimientos(
    cuenta_id: str,
    estado: Optional[str] = Query(None, description="pendiente|conciliado"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "ver")
    empresa_id = payload["empresa_id"]
    movs = cb.listar_movimientos(db, empresa_id, cuenta_id, estado)
    nombres = cb.nombres_empleado(db, empresa_id, [str(m.conciliado_por_id) for m in movs])
    numeros = cb.numeros_asiento(db, empresa_id, [str(m.asiento_id) for m in movs])
    return [_mov_out(m, nombres, numeros) for m in movs]


@router.post("/cuentas/{cuenta_id}/movimientos", response_model=MovimientoBancarioOut, status_code=201)
def registrar_movimiento(
    cuenta_id: str, body: MovimientoBancarioCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "gestionar")
    m = cb.registrar_movimiento(db, payload["empresa_id"], cuenta_id, body)
    return _mov_out(m, {}, {})


@router.post("/cuentas/{cuenta_id}/movimientos/importar")
def importar_movimientos(
    cuenta_id: str, body: ImportarMovimientosIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "gestionar")
    creados = cb.importar_movimientos(db, payload["empresa_id"], cuenta_id, body.movimientos)
    return {"importados": creados}


# ── Conciliación ─────────────────────────────────────────────────────────────
@router.get("/movimientos/{movimiento_id}/sugerencias", response_model=List[SugerenciaAsiento])
def sugerencias(
    movimiento_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "ver")
    return [SugerenciaAsiento(**s) for s in cb.sugerencias(db, payload["empresa_id"], movimiento_id)]


@router.post("/movimientos/{movimiento_id}/conciliar", response_model=MovimientoBancarioOut)
def conciliar(
    movimiento_id: str, body: ConciliarIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "conciliar")
    empresa_id = payload["empresa_id"]
    m = cb.conciliar(db, empresa_id, movimiento_id, body.asiento_id, _empleado_id(db, payload))
    nombres = cb.nombres_empleado(db, empresa_id, [str(m.conciliado_por_id)])
    numeros = cb.numeros_asiento(db, empresa_id, [str(m.asiento_id)])
    return _mov_out(m, nombres, numeros)


@router.post("/movimientos/{movimiento_id}/desconciliar", response_model=MovimientoBancarioOut)
def desconciliar(
    movimiento_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "conciliacion_bancaria", "conciliar")
    m = cb.desconciliar(db, payload["empresa_id"], movimiento_id)
    return _mov_out(m, {}, {})
