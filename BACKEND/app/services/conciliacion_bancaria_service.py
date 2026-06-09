"""
Servicio de Conciliación Bancaria (Fase 5).

Cuadra el extracto del banco contra el libro mayor. NO crea asientos: enlaza
(1-a-1) cada movimiento del extracto con un asiento ya existente que toque la
cuenta de Bancos del PCGE vinculada a la cuenta bancaria.

Signo del extracto (ver schemas):
  abono → entró dinero → en libros la cuenta de bancos se DEBITA
  cargo → salió dinero → en libros la cuenta de bancos se ACREDITA

Todos los cálculos monetarios usan Decimal.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.conciliacion_bancaria import CuentaBancaria, MovimientoBancario
from app.models.contabilidad import CuentaContable, AsientoContable, AsientoLinea
from app.models.empleado import Empleado
from app.services import contabilizacion_service as contab

CERO = Decimal("0.00")
Q2 = Decimal("0.01")
VENTANA_DIAS = 30   # máximo desfase de fecha para sugerir un asiento


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


# ── Cuentas bancarias ────────────────────────────────────────────────────────
def _cuenta_pcge(db: Session, empresa_id: str, cuenta_contable_id: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.id == cuenta_contable_id,
                CuentaContable.empresa_id == empresa_id)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422, detail="La cuenta contable no existe en la empresa.")
    if c.nivel != "detalle":
        raise HTTPException(status_code=422,
                            detail=f"La cuenta {c.codigo} es de nivel 'mayor'; elija una cuenta de detalle.")
    return c


def get_cuenta(db: Session, empresa_id: str, cuenta_id: str) -> CuentaBancaria:
    c = (
        db.query(CuentaBancaria)
        .filter(CuentaBancaria.id == cuenta_id, CuentaBancaria.empresa_id == empresa_id)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=404, detail="Cuenta bancaria no encontrada.")
    return c


def listar_cuentas(db: Session, empresa_id: str, solo_activas: bool = False) -> list[CuentaBancaria]:
    q = db.query(CuentaBancaria).filter(CuentaBancaria.empresa_id == empresa_id)
    if solo_activas:
        q = q.filter(CuentaBancaria.activo.is_(True))
    return q.order_by(CuentaBancaria.banco, CuentaBancaria.numero_cuenta).all()


def crear_cuenta(db: Session, empresa_id: str, datos) -> CuentaBancaria:
    _cuenta_pcge(db, empresa_id, datos.cuenta_contable_id)
    dup = (
        db.query(CuentaBancaria)
        .filter(CuentaBancaria.empresa_id == empresa_id,
                CuentaBancaria.banco == datos.banco,
                CuentaBancaria.numero_cuenta == datos.numero_cuenta)
        .first()
    )
    if dup:
        raise HTTPException(status_code=409,
                            detail="Ya existe una cuenta con ese banco y número.")
    cuenta = CuentaBancaria(
        empresa_id=empresa_id, banco=datos.banco, numero_cuenta=datos.numero_cuenta,
        moneda=datos.moneda, cuenta_contable_id=datos.cuenta_contable_id,
        alias=datos.alias, activo=True,
    )
    db.add(cuenta)
    db.commit()
    db.refresh(cuenta)
    return cuenta


def actualizar_cuenta(db: Session, empresa_id: str, cuenta_id: str, datos) -> CuentaBancaria:
    cuenta = get_cuenta(db, empresa_id, cuenta_id)
    if datos.cuenta_contable_id is not None:
        _cuenta_pcge(db, empresa_id, datos.cuenta_contable_id)
        cuenta.cuenta_contable_id = datos.cuenta_contable_id
    for campo in ("banco", "numero_cuenta", "moneda", "alias", "activo"):
        valor = getattr(datos, campo, None)
        if valor is not None:
            setattr(cuenta, campo, valor)
    db.commit()
    db.refresh(cuenta)
    return cuenta


# ── Saldos ───────────────────────────────────────────────────────────────────
def saldo_banco(db: Session, cuenta_bancaria_id: str) -> Decimal:
    """Σ abonos − Σ cargos del extracto (lo que el banco dice que hay)."""
    filas = (
        db.query(MovimientoBancario.tipo, func.coalesce(func.sum(MovimientoBancario.monto), 0))
        .filter(MovimientoBancario.cuenta_bancaria_id == cuenta_bancaria_id)
        .group_by(MovimientoBancario.tipo)
        .all()
    )
    abonos = cargos = CERO
    for tipo, suma in filas:
        if tipo == "abono":
            abonos = _d(suma)
        elif tipo == "cargo":
            cargos = _d(suma)
    return abonos - cargos


def saldo_libros(db: Session, empresa_id: str, cuenta_contable_id: str) -> Decimal:
    """Saldo (débitos − créditos) de la cuenta del PCGE en el libro mayor."""
    return contab.obtener_saldo_cuenta(db, empresa_id, cuenta_contable_id)


def _conteos(db: Session, cuenta_bancaria_id: str) -> tuple[int, int, int, Decimal]:
    """(total, conciliados, pendientes, importe_pendiente)."""
    filas = (
        db.query(MovimientoBancario.estado,
                 func.count(MovimientoBancario.id),
                 func.coalesce(func.sum(MovimientoBancario.monto), 0))
        .filter(MovimientoBancario.cuenta_bancaria_id == cuenta_bancaria_id)
        .group_by(MovimientoBancario.estado)
        .all()
    )
    total = conciliados = pendientes = 0
    importe_pendiente = CERO
    for estado, n, suma in filas:
        n = int(n or 0)
        total += n
        if estado == "conciliado":
            conciliados += n
        else:
            pendientes += n
            importe_pendiente += _d(suma)
    return total, conciliados, pendientes, importe_pendiente


def n_pendientes(db: Session, cuenta_bancaria_id: str) -> int:
    return (
        db.query(func.count(MovimientoBancario.id))
        .filter(MovimientoBancario.cuenta_bancaria_id == cuenta_bancaria_id,
                MovimientoBancario.estado == "pendiente")
        .scalar()
    ) or 0


def resumen(db: Session, empresa_id: str, cuenta_id: str) -> dict:
    cuenta = get_cuenta(db, empresa_id, cuenta_id)
    total, conciliados, pendientes, importe_pendiente = _conteos(db, cuenta_id)
    sb = saldo_banco(db, cuenta_id)
    sl = saldo_libros(db, empresa_id, cuenta.cuenta_contable_id)
    return {
        "cuenta_bancaria_id": cuenta_id,
        "saldo_banco": sb,
        "saldo_libros": sl,
        "diferencia": sb - sl,
        "total_movimientos": total,
        "conciliados": conciliados,
        "pendientes": pendientes,
        "importe_pendiente": importe_pendiente,
    }


# ── Movimientos del extracto ─────────────────────────────────────────────────
def registrar_movimiento(db: Session, empresa_id: str, cuenta_id: str, datos,
                         origen_carga: str = "manual") -> MovimientoBancario:
    get_cuenta(db, empresa_id, cuenta_id)   # valida pertenencia a la empresa
    if _d(datos.monto) <= CERO:
        raise HTTPException(status_code=422, detail="El monto debe ser mayor que 0.")
    mov = MovimientoBancario(
        empresa_id=empresa_id, cuenta_bancaria_id=cuenta_id,
        fecha=datos.fecha, descripcion=datos.descripcion, referencia=datos.referencia,
        tipo=datos.tipo, monto=_d(datos.monto), estado="pendiente",
        origen_carga=origen_carga,
    )
    db.add(mov)
    db.commit()
    db.refresh(mov)
    return mov


def importar_movimientos(db: Session, empresa_id: str, cuenta_id: str, filas: list) -> int:
    """Carga masiva del extracto. Inserta todas las filas en una sola transacción."""
    get_cuenta(db, empresa_id, cuenta_id)
    creados = 0
    for f in filas:
        if _d(f.monto) <= CERO:
            raise HTTPException(status_code=422,
                                detail=f"Monto inválido en la fila '{f.descripcion}'.")
        db.add(MovimientoBancario(
            empresa_id=empresa_id, cuenta_bancaria_id=cuenta_id,
            fecha=f.fecha, descripcion=f.descripcion, referencia=f.referencia,
            tipo=f.tipo, monto=_d(f.monto), estado="pendiente", origen_carga="csv",
        ))
        creados += 1
    db.commit()
    return creados


def listar_movimientos(db: Session, empresa_id: str, cuenta_id: str,
                       estado: str | None = None) -> list[MovimientoBancario]:
    get_cuenta(db, empresa_id, cuenta_id)
    q = db.query(MovimientoBancario).filter(
        MovimientoBancario.cuenta_bancaria_id == cuenta_id,
        MovimientoBancario.empresa_id == empresa_id,
    )
    if estado:
        q = q.filter(MovimientoBancario.estado == estado)
    return q.order_by(MovimientoBancario.fecha.desc(), MovimientoBancario.created_at.desc()).all()


def get_movimiento(db: Session, empresa_id: str, movimiento_id: str) -> MovimientoBancario:
    m = (
        db.query(MovimientoBancario)
        .filter(MovimientoBancario.id == movimiento_id,
                MovimientoBancario.empresa_id == empresa_id)
        .first()
    )
    if m is None:
        raise HTTPException(status_code=404, detail="Movimiento bancario no encontrado.")
    return m


# ── Conciliación ─────────────────────────────────────────────────────────────
def _monto_asiento_en_banco(db: Session, empresa_id: str, asiento_id: str,
                            cuenta_contable_id: str, tipo_mov: str) -> Decimal:
    """Importe del asiento que afecta la cuenta de bancos, en el lado que aplica.

    abono → débito de la cuenta de bancos; cargo → crédito.
    """
    columna = AsientoLinea.debito if tipo_mov == "abono" else AsientoLinea.credito
    suma = (
        db.query(func.coalesce(func.sum(columna), 0))
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.id == asiento_id,
                AsientoContable.empresa_id == empresa_id,
                AsientoLinea.cuenta_id == cuenta_contable_id)
        .scalar()
    )
    return _d(suma)


def _asientos_ya_conciliados(db: Session, empresa_id: str, cuenta_bancaria_id: str) -> set[str]:
    filas = (
        db.query(MovimientoBancario.asiento_id)
        .filter(MovimientoBancario.empresa_id == empresa_id,
                MovimientoBancario.cuenta_bancaria_id == cuenta_bancaria_id,
                MovimientoBancario.asiento_id.isnot(None))
        .all()
    )
    return {str(a) for (a,) in filas if a}


def sugerencias(db: Session, empresa_id: str, movimiento_id: str) -> list[dict]:
    """Asientos candidatos a conciliar: mismo importe en la cuenta de bancos,
    lado correcto (débito para abono, crédito para cargo), aún no conciliados y
    con fecha dentro de ±VENTANA_DIAS. Ordenados por cercanía de fecha."""
    mov = get_movimiento(db, empresa_id, movimiento_id)
    if mov.estado == "conciliado":
        return []
    cuenta = get_cuenta(db, empresa_id, mov.cuenta_bancaria_id)
    columna = AsientoLinea.debito if mov.tipo == "abono" else AsientoLinea.credito
    usados = _asientos_ya_conciliados(db, empresa_id, mov.cuenta_bancaria_id)

    filas = (
        db.query(AsientoContable.id, AsientoContable.numero, AsientoContable.fecha,
                 AsientoContable.descripcion, AsientoContable.origen,
                 func.coalesce(func.sum(columna), 0).label("monto"))
        .join(AsientoLinea, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoLinea.cuenta_id == cuenta.cuenta_contable_id)
        .group_by(AsientoContable.id, AsientoContable.numero, AsientoContable.fecha,
                  AsientoContable.descripcion, AsientoContable.origen)
        .having(func.coalesce(func.sum(columna), 0) == _d(mov.monto))
        .all()
    )
    candidatos: list[dict] = []
    for aid, numero, fecha, descripcion, origen, monto in filas:
        if str(aid) in usados:
            continue
        dias = abs((fecha - mov.fecha).days)
        if dias > VENTANA_DIAS:
            continue
        candidatos.append({
            "asiento_id": str(aid), "numero": numero, "fecha": fecha,
            "descripcion": descripcion, "origen": origen, "monto": _d(monto),
            "dias_diferencia": dias,
        })
    candidatos.sort(key=lambda c: c["dias_diferencia"])
    return candidatos


def conciliar(db: Session, empresa_id: str, movimiento_id: str, asiento_id: str,
              empleado_id: str | None = None) -> MovimientoBancario:
    mov = get_movimiento(db, empresa_id, movimiento_id)
    if mov.estado == "conciliado":
        raise HTTPException(status_code=409, detail="El movimiento ya está conciliado.")
    cuenta = get_cuenta(db, empresa_id, mov.cuenta_bancaria_id)

    asiento = (
        db.query(AsientoContable)
        .filter(AsientoContable.id == asiento_id, AsientoContable.empresa_id == empresa_id)
        .first()
    )
    if asiento is None:
        raise HTTPException(status_code=422, detail="El asiento no existe en la empresa.")

    # El asiento debe afectar la cuenta de bancos por el mismo importe y lado.
    monto_asiento = _monto_asiento_en_banco(db, empresa_id, asiento_id,
                                            cuenta.cuenta_contable_id, mov.tipo)
    if monto_asiento <= CERO:
        lado = "débito" if mov.tipo == "abono" else "crédito"
        raise HTTPException(
            status_code=422,
            detail=f"El asiento no tiene un {lado} en la cuenta de bancos de esta cuenta.")
    if monto_asiento != _d(mov.monto):
        raise HTTPException(
            status_code=422,
            detail=f"El importe del asiento en bancos ({monto_asiento}) no coincide "
                   f"con el del movimiento ({_d(mov.monto)}).")

    # 1-a-1: el asiento no puede estar ya conciliado con otro movimiento.
    if str(asiento_id) in _asientos_ya_conciliados(db, empresa_id, mov.cuenta_bancaria_id):
        raise HTTPException(status_code=409,
                            detail="Ese asiento ya está conciliado con otro movimiento.")

    mov.estado = "conciliado"
    mov.asiento_id = asiento_id
    mov.conciliado_por_id = empleado_id
    mov.conciliado_at = datetime.utcnow()
    db.commit()
    db.refresh(mov)
    return mov


def desconciliar(db: Session, empresa_id: str, movimiento_id: str) -> MovimientoBancario:
    mov = get_movimiento(db, empresa_id, movimiento_id)
    if mov.estado != "conciliado":
        raise HTTPException(status_code=409, detail="El movimiento no está conciliado.")
    mov.estado = "pendiente"
    mov.asiento_id = None
    mov.conciliado_por_id = None
    mov.conciliado_at = None
    db.commit()
    db.refresh(mov)
    return mov


# ── Apoyo para serialización ─────────────────────────────────────────────────
def nombres_empleado(db: Session, empresa_id: str, ids: list[str]) -> dict[str, str]:
    ids = [i for i in ids if i]
    if not ids:
        return {}
    from app.models.usuario import Usuario
    filas = (
        db.query(Empleado.id, Usuario.nombre, Usuario.apellido)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.id.in_(ids))
        .all()
    )
    return {str(i): f"{n or ''} {a or ''}".strip() for i, n, a in filas}


def numeros_asiento(db: Session, empresa_id: str, ids: list[str]) -> dict[str, str]:
    ids = [i for i in ids if i]
    if not ids:
        return {}
    filas = (
        db.query(AsientoContable.id, AsientoContable.numero)
        .filter(AsientoContable.empresa_id == empresa_id, AsientoContable.id.in_(ids))
        .all()
    )
    return {str(i): num for i, num in filas}
