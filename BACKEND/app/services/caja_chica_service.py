"""
Servicio de Caja Chica (Fase 5).

Cada movimiento genera su asiento contable automático vía
contabilizacion_service.registrar_asiento (principio "todo conectado a
Finanzas"). El asiento se vincula al movimiento por origen='caja_chica' +
referencia_id=movimiento.id (sin alterar el esquema de las tablas).

Mapeo contable (cuentas de DETALLE del PCGE, resueltas por código con default):
  Ingreso (constituir/reponer fondo):  Db 101 Caja chica / Cr 104 Bancos
  Egreso  (gasto pagado con la caja):  Db 6xx Gasto      / Cr 101 Caja chica
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable, AsientoContable
from app.models.caja_chica import CajaChica, MovimientoCaja
from app.models.empleado import Empleado
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q2 = Decimal("0.01")

CTA_CAJA_CHICA   = "101"   # Caja
CTA_GASTO_DEF    = "659"   # Otros gastos de gestión (default para egresos)
CTA_REPOSICION   = "104"   # Cuentas corrientes (bancos, default origen de ingresos)

ORIGEN = "caja_chica"


def _d(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


def _cuenta(db: Session, empresa_id: str, codigo: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == codigo)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422,
                            detail=f"Falta la cuenta contable {codigo} en el plan de la empresa.")
    return c


def _empleado(db: Session, empresa_id: str, empleado_id: str) -> Empleado:
    e = db.query(Empleado).filter(Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if e is None:
        raise HTTPException(status_code=422, detail="El empleado no existe en la empresa.")
    return e


# ── Cajas ────────────────────────────────────────────────────────────────────
def get_caja(db: Session, empresa_id: str, caja_id: str) -> CajaChica:
    c = db.query(CajaChica).filter(CajaChica.id == caja_id, CajaChica.empresa_id == empresa_id).first()
    if c is None:
        raise HTTPException(status_code=404, detail="Caja chica no encontrada.")
    return c


def crear_caja(db: Session, empresa_id: str, datos) -> CajaChica:
    _empleado(db, empresa_id, datos.responsable_id)
    caja = CajaChica(
        empresa_id=empresa_id,
        responsable_id=datos.responsable_id,
        proyecto_id=datos.proyecto_id,
        nombre=datos.nombre,
        descripcion=datos.descripcion,
        monto_asignado_referencial=(_d(datos.monto_asignado_referencial)
                                    if datos.monto_asignado_referencial is not None else None),
        fecha_apertura=datos.fecha_apertura or date.today(),
        estado="abierta",
    )
    db.add(caja)
    db.commit()
    db.refresh(caja)
    return caja


def cerrar_caja(db: Session, empresa_id: str, caja_id: str) -> CajaChica:
    caja = get_caja(db, empresa_id, caja_id)
    if caja.estado == "cerrada":
        raise HTTPException(status_code=409, detail="La caja ya está cerrada.")
    caja.estado = "cerrada"
    caja.fecha_cierre = date.today()
    caja.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(caja)
    return caja


# ── Saldos ───────────────────────────────────────────────────────────────────
def _totales(db: Session, caja_id: str) -> tuple[Decimal, Decimal, int]:
    """(total_ingresos, total_egresos, n_movimientos) de una caja."""
    filas = (
        db.query(MovimientoCaja.tipo, func.coalesce(func.sum(MovimientoCaja.monto), 0), func.count(MovimientoCaja.id))
        .filter(MovimientoCaja.caja_id == caja_id)
        .group_by(MovimientoCaja.tipo)
        .all()
    )
    ingresos = egresos = CERO
    n = 0
    for tipo, suma, cuantos in filas:
        n += int(cuantos or 0)
        if tipo == "ingreso":
            ingresos = _d(suma)
        elif tipo == "egreso":
            egresos = _d(suma)
    return ingresos, egresos, n


def saldo_caja(db: Session, caja_id: str) -> Decimal:
    ingresos, egresos, _ = _totales(db, caja_id)
    return ingresos - egresos


# ── Movimientos ──────────────────────────────────────────────────────────────
def registrar_movimiento(db: Session, empresa_id: str, caja_id: str, datos,
                         registrado_por_id: str | None = None) -> MovimientoCaja:
    caja = get_caja(db, empresa_id, caja_id)
    if caja.estado != "abierta":
        raise HTTPException(status_code=409,
                            detail=f"La caja está {caja.estado} y no admite movimientos.")

    monto = _d(datos.monto)
    if monto <= CERO:
        raise HTTPException(status_code=422, detail="El monto debe ser mayor que 0.")

    # Un egreso no puede dejar la caja en negativo (forzar constituir fondo antes).
    if datos.tipo == "egreso":
        disponible = saldo_caja(db, caja_id)
        if monto > disponible:
            raise HTTPException(
                status_code=422,
                detail=f"El egreso ({monto}) excede el saldo disponible de la caja ({disponible}).",
            )

    fecha_mov = datos.fecha or datetime.utcnow()
    cuenta_caja = _cuenta(db, empresa_id, CTA_CAJA_CHICA)

    if datos.tipo == "egreso":
        cuenta_contra = _cuenta(db, empresa_id, datos.cuenta_codigo or CTA_GASTO_DEF)
        lineas = [
            LineaAsiento(cuenta_id=cuenta_contra.id, debito=monto, glosa=datos.concepto or datos.descripcion),
            LineaAsiento(cuenta_id=cuenta_caja.id, credito=monto),
        ]
        desc_asiento = f"Caja chica '{caja.nombre}': egreso — {datos.descripcion}"
    else:  # ingreso
        cuenta_contra = _cuenta(db, empresa_id, datos.cuenta_codigo or CTA_REPOSICION)
        lineas = [
            LineaAsiento(cuenta_id=cuenta_caja.id, debito=monto, glosa=datos.concepto or datos.descripcion),
            LineaAsiento(cuenta_id=cuenta_contra.id, credito=monto),
        ]
        desc_asiento = f"Caja chica '{caja.nombre}': ingreso — {datos.descripcion}"

    mov = MovimientoCaja(
        caja_id=caja_id, empresa_id=empresa_id, tipo=datos.tipo, monto=monto,
        descripcion=datos.descripcion, concepto=datos.concepto,
        comprobante_url=datos.comprobante_url, public_id_cloudinary=datos.public_id_cloudinary,
        registrado_por=registrado_por_id, fecha=fecha_mov,
    )
    db.add(mov)
    db.flush()

    try:
        contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha_mov.date() if isinstance(fecha_mov, datetime) else fecha_mov,
            descripcion=desc_asiento, origen=ORIGEN, lineas=lineas,
            referencia_id=mov.id, creado_por_id=registrado_por_id, commit=False,
        )
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo registrar el movimiento: {exc}") from exc

    db.refresh(mov)
    return mov


def listar_movimientos(db: Session, empresa_id: str, caja_id: str) -> list[MovimientoCaja]:
    get_caja(db, empresa_id, caja_id)  # valida pertenencia a la empresa
    return (
        db.query(MovimientoCaja)
        .filter(MovimientoCaja.caja_id == caja_id, MovimientoCaja.empresa_id == empresa_id)
        .order_by(MovimientoCaja.fecha.desc())
        .all()
    )


# ── Apoyo para serialización ─────────────────────────────────────────────────
def nombres_empleado(db: Session, empresa_id: str, ids: list[str]) -> dict[str, str]:
    """Mapea empleado_id → 'Nombre Apellido' (el nombre vive en Usuario)."""
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


def asientos_por_movimiento(db: Session, empresa_id: str, mov_ids: list[str]) -> dict[str, str]:
    """Mapea movimiento_id → asiento_id (vínculo por origen+referencia_id)."""
    mov_ids = [i for i in mov_ids if i]
    if not mov_ids:
        return {}
    filas = (
        db.query(AsientoContable.referencia_id, AsientoContable.id)
        .filter(AsientoContable.empresa_id == empresa_id,
                AsientoContable.origen == ORIGEN,
                AsientoContable.referencia_id.in_(mov_ids))
        .all()
    )
    return {str(ref): str(aid) for ref, aid in filas}
