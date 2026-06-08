"""
Motor de contabilización (Fase 1 — Libro Mayor).

`registrar_asiento` es el ÚNICO punto de entrada para escribir en el libro
mayor. Ningún router ni servicio inserta en `asiento_linea` directamente.

Garantiza el invariante de oro (SUM débito = SUM crédito) y las reglas de
negocio (periodo abierto, cuentas de detalle activas) ANTES de tocar la BD,
y persiste cabecera + líneas en una sola transacción atómica (todo o nada).

Todos los cálculos monetarios usan Decimal — nunca float.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, InvalidOperation

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import (
    CuentaContable, PeriodoContable, AsientoContable, AsientoLinea, CentroCosto,
)

CERO = Decimal("0.00")


@dataclass
class LineaAsiento:
    cuenta_id: str
    debito: Decimal = field(default_factory=lambda: CERO)
    credito: Decimal = field(default_factory=lambda: CERO)
    centro_costo_id: str | None = None
    glosa: str | None = None


def _a_decimal(valor) -> Decimal:
    """Convierte a Decimal de forma segura (acepta str/int/Decimal, nunca float ciego)."""
    if isinstance(valor, Decimal):
        return valor.quantize(Decimal("0.01"))
    try:
        return Decimal(str(valor if valor is not None else 0)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError):
        raise HTTPException(status_code=422, detail=f"Monto inválido: {valor!r}")


def obtener_periodo(db: Session, empresa_id: str, fecha: date) -> PeriodoContable:
    """Devuelve el periodo contable de la fecha. 409 si no existe o está cerrado."""
    periodo = (
        db.query(PeriodoContable)
        .filter(
            PeriodoContable.empresa_id == empresa_id,
            PeriodoContable.anio == fecha.year,
            PeriodoContable.mes == fecha.month,
        )
        .first()
    )
    if not periodo:
        raise HTTPException(
            status_code=409,
            detail=f"No existe un periodo contable para {fecha.year}-{fecha.month:02d}. Ábralo antes de contabilizar.",
        )
    if periodo.estado != "abierto":
        raise HTTPException(
            status_code=409,
            detail=f"El periodo {fecha.year}-{fecha.month:02d} está cerrado; no admite asientos.",
        )
    return periodo


def _siguiente_numero(db: Session, empresa_id: str, periodo_id: str) -> str:
    """Correlativo por empresa+periodo, con ceros a la izquierda."""
    cuantos = (
        db.query(func.count(AsientoContable.id))
        .filter(
            AsientoContable.empresa_id == empresa_id,
            AsientoContable.periodo_id == periodo_id,
        )
        .scalar()
    ) or 0
    return f"{cuantos + 1:06d}"


def registrar_asiento(
    db: Session,
    empresa_id: str,
    fecha: date,
    descripcion: str,
    origen: str,
    lineas: list[LineaAsiento],
    referencia_id: str | None = None,
    creado_por_id: str | None = None,
    commit: bool = True,
) -> AsientoContable:
    """Crea un asiento balanceado. Lanza HTTPException si algo no cumple.

    Pasos (en este orden, todos ANTES de escribir):
      1. periodo abierto
      2. cada cuenta es de detalle y está activa
      3. SUM(debito) == SUM(credito), en Decimal
      4. inserción atómica (cabecera + líneas) en una sola transacción

    `commit=False`: el asiento se inserta y valida (flush, dispara los
    constraints de BD) pero NO se hace commit — para que un módulo de origen
    (p. ej. cuentas_por_pagar) confirme factura + asiento en una sola
    transacción atómica. En ese caso el llamador es responsable del commit;
    si algo posterior falla, su rollback revierte también este asiento.
    """
    if not lineas:
        raise HTTPException(status_code=422, detail="El asiento debe tener al menos una línea.")

    # 1) periodo abierto
    periodo = obtener_periodo(db, empresa_id, fecha)

    # 2 y 3) validar líneas y cuadre
    total_debito = CERO
    total_credito = CERO
    cache_cuentas: dict[str, CuentaContable] = {}
    cache_centros: dict[str, CentroCosto] = {}

    for ln in lineas:
        deb = _a_decimal(ln.debito)
        cre = _a_decimal(ln.credito)
        if deb < 0 or cre < 0:
            raise HTTPException(status_code=422, detail="Los montos no pueden ser negativos.")
        if (deb > 0 and cre > 0) or (deb == 0 and cre == 0):
            raise HTTPException(
                status_code=422,
                detail="Cada línea debe tener débito XOR crédito (uno mayor que 0 y el otro en 0).",
            )

        cuenta = cache_cuentas.get(ln.cuenta_id)
        if cuenta is None:
            cuenta = (
                db.query(CuentaContable)
                .filter(CuentaContable.id == ln.cuenta_id, CuentaContable.empresa_id == empresa_id)
                .first()
            )
            if cuenta is None:
                raise HTTPException(status_code=422, detail=f"La cuenta {ln.cuenta_id} no existe en la empresa.")
            cache_cuentas[ln.cuenta_id] = cuenta

        if cuenta.nivel != "detalle":
            raise HTTPException(
                status_code=422,
                detail=f"La cuenta {cuenta.codigo} es de nivel 'mayor'; solo las cuentas de detalle reciben movimientos.",
            )
        if not cuenta.activo:
            raise HTTPException(status_code=422, detail=f"La cuenta {cuenta.codigo} está inactiva.")

        # Imputación analítica opcional (Fase 2): si la línea trae centro de
        # costo, debe existir, ser de la empresa y estar activo. Un centro
        # inactivo conserva su historial pero no admite nuevas imputaciones.
        if ln.centro_costo_id:
            cc = cache_centros.get(ln.centro_costo_id)
            if cc is None:
                cc = (
                    db.query(CentroCosto)
                    .filter(CentroCosto.id == ln.centro_costo_id,
                            CentroCosto.empresa_id == empresa_id)
                    .first()
                )
                if cc is None:
                    raise HTTPException(
                        status_code=422,
                        detail=f"El centro de costo {ln.centro_costo_id} no existe en la empresa.",
                    )
                cache_centros[ln.centro_costo_id] = cc
            if not cc.activo:
                raise HTTPException(
                    status_code=422,
                    detail=f"El centro de costo {cc.codigo} está inactivo; no admite nuevas imputaciones.",
                )

        total_debito += deb
        total_credito += cre

    if total_debito != total_credito:
        raise HTTPException(
            status_code=422,
            detail=f"Asiento descuadrado: débitos {total_debito} ≠ créditos {total_credito}.",
        )
    if total_debito == CERO:
        raise HTTPException(status_code=422, detail="El asiento no puede ser de monto cero.")

    # 4) inserción atómica
    numero = _siguiente_numero(db, empresa_id, periodo.id)
    asiento = AsientoContable(
        empresa_id=empresa_id,
        numero=numero,
        fecha=fecha,
        periodo_id=periodo.id,
        descripcion=descripcion,
        origen=origen,
        referencia_id=referencia_id,
        creado_por_id=creado_por_id,
    )
    try:
        db.add(asiento)
        db.flush()  # obtiene asiento.id sin cerrar la transacción
        for ln in lineas:
            db.add(
                AsientoLinea(
                    asiento_id=asiento.id,
                    cuenta_id=ln.cuenta_id,
                    debito=_a_decimal(ln.debito),
                    credito=_a_decimal(ln.credito),
                    centro_costo_id=ln.centro_costo_id,
                    glosa=ln.glosa,
                )
            )
        # flush dispara los constraints de BD (xor débito/crédito, etc.) AHORA,
        # tanto si confirmamos aquí como si delegamos el commit al llamador.
        db.flush()
        if commit:
            db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:  # constraint de BD u otro fallo → rollback total
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo persistir el asiento: {exc}") from exc

    # Con commit=False el asiento queda en la sesión (no persistido aún): el
    # módulo de origen confirmará factura + asiento en una sola transacción. No
    # se hace refresh porque la fila todavía no está consolidada.
    if commit:
        db.refresh(asiento)
    return asiento


# ── Consultas de apoyo (alimentan reportes de la Fase 9 y las pruebas) ───────

def obtener_saldo_cuenta(
    db: Session, empresa_id: str, cuenta_id: str,
    periodo_desde: date | None = None, periodo_hasta: date | None = None,
) -> Decimal:
    """Saldo (débitos - créditos) de una cuenta en un rango de fechas opcional."""
    q = (
        db.query(
            func.coalesce(func.sum(AsientoLinea.debito), 0),
            func.coalesce(func.sum(AsientoLinea.credito), 0),
        )
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(
            AsientoContable.empresa_id == empresa_id,
            AsientoLinea.cuenta_id == cuenta_id,
        )
    )
    if periodo_desde:
        q = q.filter(AsientoContable.fecha >= periodo_desde)
    if periodo_hasta:
        q = q.filter(AsientoContable.fecha <= periodo_hasta)
    deb, cre = q.first()
    return _a_decimal(deb) - _a_decimal(cre)


def balance_comprobacion(db: Session, empresa_id: str, periodo_id: str) -> list[dict]:
    """Saldos deudor/acreedor de cada cuenta de detalle con movimiento en el periodo.

    El total de saldos deudores debe ser igual al total de saldos acreedores —
    es la prueba de salud continua de todo el sistema contable.
    """
    filas = (
        db.query(
            CuentaContable.codigo,
            CuentaContable.nombre,
            func.coalesce(func.sum(AsientoLinea.debito), 0).label("td"),
            func.coalesce(func.sum(AsientoLinea.credito), 0).label("tc"),
        )
        .join(AsientoLinea, AsientoLinea.cuenta_id == CuentaContable.id)
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(
            AsientoContable.empresa_id == empresa_id,
            AsientoContable.periodo_id == periodo_id,
        )
        .group_by(CuentaContable.codigo, CuentaContable.nombre)
        .order_by(CuentaContable.codigo)
        .all()
    )
    resultado: list[dict] = []
    for codigo, nombre, td, tc in filas:
        td = _a_decimal(td)
        tc = _a_decimal(tc)
        saldo = td - tc
        resultado.append(
            {
                "codigo": codigo,
                "nombre": nombre,
                "total_debito": td,
                "total_credito": tc,
                "saldo_deudor": saldo if saldo > 0 else CERO,
                "saldo_acreedor": -saldo if saldo < 0 else CERO,
            }
        )
    return resultado
