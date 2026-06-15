"""
Servicio de costeo de inventario — promedio ponderado (Fase 5).

Cada movimiento valorizado actualiza el costo promedio del material y genera su
asiento contable atómico, manteniendo el invariante central de la fase:

    SUM(valor de ingresos − valor de salidas vigentes)  ==  saldo de 20-Mercaderías

Mapeo contable (cuentas de DETALLE del PCGE), elegido para NO duplicar el
asiento de compra que AP ya registró (60 Compras / 42 por pagar):
  Ingreso a almacén : Db 201 Mercaderías  / Cr 611 Variación de existencias
  Salida (consumo)  : Db 691 Costo de ventas / Cr 201 Mercaderías

601/611 y 691 se netean en el estado de resultados, evitando doble conteo.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable, PeriodoContable
from app.models.costeo_inventario import CostoPromedioMaterial
from app.models.material import Material, Stock
from app.models.movimiento_inventario import MovimientoInventario
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q4 = Decimal("0.0001")
Q2 = Decimal("0.01")

CTA_MERCADERIAS  = "201"   # 20 Mercaderías (detalle)
CTA_VARIACION    = "611"   # 61 Variación de existencias (detalle)
CTA_COSTO_VENTAS = "691"   # 69 Costo de ventas (detalle)
CTA_APERTURA_INV = "591"   # 59 Resultados acumulados — contracuenta de apertura

# Tipos de movimiento que suman inventario (ingreso) vs los que restan (salida).
# 'ajuste' NO se valoriza automáticamente: en Logística fija un stock ABSOLUTO
# (no es un delta direccional), así que valorizar_movimiento lo ignora.
TIPOS_INGRESO = ("entrada", "compra", "ingreso", "retorno")
TIPOS_SALIDA  = ("salida",)


def _d4(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q4)


def _d2(v) -> Decimal:
    return Decimal(str(v if v is not None else 0)).quantize(Q2)


def _cuenta(db: Session, empresa_id: str, codigo: str) -> CuentaContable:
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == codigo)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422, detail=f"Falta la cuenta contable {codigo} en el plan.")
    return c


def _estado_costo(db: Session, empresa_id: str, material_id: str, almacen_id: str) -> CostoPromedioMaterial:
    estado = (
        db.query(CostoPromedioMaterial)
        .filter(CostoPromedioMaterial.empresa_id == empresa_id,
                CostoPromedioMaterial.material_id == material_id,
                CostoPromedioMaterial.almacen_id == almacen_id)
        .first()
    )
    if estado is None:
        estado = CostoPromedioMaterial(
            empresa_id=empresa_id, material_id=material_id, almacen_id=almacen_id,
            cantidad_actual=CERO, costo_promedio_actual=CERO,
        )
        db.add(estado)
        db.flush()
    return estado


def costo_promedio(db: Session, empresa_id: str, material_id: str, almacen_id: str) -> dict:
    estado = (
        db.query(CostoPromedioMaterial)
        .filter(CostoPromedioMaterial.empresa_id == empresa_id,
                CostoPromedioMaterial.material_id == material_id,
                CostoPromedioMaterial.almacen_id == almacen_id)
        .first()
    )
    return {
        "material_id": material_id,
        "almacen_id": almacen_id,
        "cantidad_actual": _d4(estado.cantidad_actual) if estado else CERO,
        "costo_promedio_actual": _d4(estado.costo_promedio_actual) if estado else CERO,
        "valor_actual": (_d4(estado.cantidad_actual) * _d4(estado.costo_promedio_actual)).quantize(Q2) if estado else CERO,
    }


# ── Hook de valorización para movimientos creados por Logística ───────────────
def _precio_material(db: Session, empresa_id: str, material_id: str) -> Decimal:
    m = db.query(Material).filter(
        Material.empresa_id == empresa_id, Material.id == material_id).first()
    return _d4(m.precio) if m and m.precio is not None else CERO


def _puede_contabilizar(db: Session, empresa_id: str, fecha, codigos: tuple[str, ...]) -> bool:
    """True solo si hay periodo ABIERTO para la fecha y todas las cuentas existen
    como detalle activas. La valorización desde Logística es best-effort: si esto
    no se cumple, NO se contabiliza ni se muta nada (la operación logística sigue),
    para no disparar el rollback total de registrar_asiento."""
    p = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == empresa_id,
        PeriodoContable.anio == fecha.year,
        PeriodoContable.mes == fecha.month).first()
    if not p or p.estado != "abierto":
        return False
    n = db.query(func.count(CuentaContable.id)).filter(
        CuentaContable.empresa_id == empresa_id,
        CuentaContable.codigo.in_(codigos),
        CuentaContable.nivel == "detalle",
        CuentaContable.activo.is_(True)).scalar() or 0
    return n == len(set(codigos))


def valorizar_movimiento(
    db: Session, mov: MovimientoInventario, *,
    costo_unitario=None, usar_promedio_vigente: bool = False,
    creado_por_id: str | None = None,
) -> None:
    """Valoriza un movimiento de inventario que **Logística ya creó** (no crea
    otro ni toca la tabla `stock`): fija costo_unitario/valor_total, recalcula el
    costo promedio del material y genera el asiento contable. NO hace commit:
    corre dentro de la transacción del flujo de Logística que lo invoca.

    Reglas:
      - Ingreso (entrada/compra/retorno/ajuste): al `costo_unitario` dado, o a
        `material.precio` si no se pasa. Db 201 / Cr 611.
      - Salida: al costo promedio vigente. Db 691 / Cr 201. Si el material aún no
        tiene costo (apertura perezosa), reconoce primero la cantidad de la salida
        a `material.precio` con Db 201 / Cr 591 y luego la consume.
      - Transferencias y movimientos sin material/almacén: se omiten (neutros).
    """
    if mov.material_id is None or mov.almacen_id is None:
        return
    if mov.tipo == "transferencia":
        return
    cant = _d4(mov.cantidad)
    if cant <= 0:
        return

    empresa_id = mov.empresa_id
    fecha = mov.fecha or datetime.utcnow()

    # Best-effort: si no se puede contabilizar (periodo cerrado/inexistente o
    # falta una cuenta), se omite la valorización SIN tocar nada. El movimiento
    # de stock de Logística queda intacto.
    cuentas_req = ((CTA_MERCADERIAS, CTA_VARIACION) if mov.tipo in TIPOS_INGRESO
                   else (CTA_MERCADERIAS, CTA_COSTO_VENTAS, CTA_APERTURA_INV))
    if not _puede_contabilizar(db, empresa_id, fecha, cuentas_req):
        return

    estado = _estado_costo(db, empresa_id, mov.material_id, mov.almacen_id)

    if mov.tipo in TIPOS_INGRESO:
        # Retorno: reingresa al promedio vigente (no altera el costo) si ya existe.
        if usar_promedio_vigente and _d4(estado.costo_promedio_actual) > CERO:
            costo = _d4(estado.costo_promedio_actual)
        else:
            costo = _d4(costo_unitario if costo_unitario is not None
                        else _precio_material(db, empresa_id, mov.material_id))
        cant_prev = _d4(estado.cantidad_actual)
        costo_prev = _d4(estado.costo_promedio_actual)
        cant_nueva = cant_prev + cant
        nuevo_prom = (((cant_prev * costo_prev + cant * costo) / cant_nueva).quantize(Q4)
                      if cant_nueva > 0 else CERO)
        valor = (cant * costo).quantize(Q2)
        mov.costo_unitario = costo
        mov.valor_total = valor
        if valor > CERO:
            asiento = contab.registrar_asiento(
                db, empresa_id=empresa_id, fecha=fecha.date(),
                descripcion=f"Ingreso a almacén (valorizado) {valor}",
                origen="inventario", lineas=[
                    LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_MERCADERIAS).id, debito=valor),
                    LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_VARIACION).id, credito=valor),
                ],
                referencia_id=mov.id, creado_por_id=creado_por_id, commit=False,
            )
            mov.asiento_id = asiento.id
        estado.cantidad_actual = cant_nueva
        estado.costo_promedio_actual = nuevo_prom
        return

    if mov.tipo in TIPOS_SALIDA:
        # Apertura perezosa: si el material no tiene costo aún, reconoce la
        # cantidad de esta salida a material.precio (Db 201 / Cr 591) para no
        # acreditar un 201 que nunca se debitó.
        if _d4(estado.costo_promedio_actual) <= CERO:
            precio = _precio_material(db, empresa_id, mov.material_id)
            if precio <= CERO:
                return  # sin precio de catálogo no se puede valorizar; queda sin asiento
            valor_ap = (cant * precio).quantize(Q2)
            asiento_ap = contab.registrar_asiento(
                db, empresa_id=empresa_id, fecha=fecha.date(),
                descripcion=f"Apertura de inventario (valorizado) {valor_ap}",
                origen="inventario", lineas=[
                    LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_MERCADERIAS).id, debito=valor_ap),
                    LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_APERTURA_INV).id, credito=valor_ap),
                ],
                referencia_id=mov.material_id, creado_por_id=creado_por_id, commit=False,
            )
            estado.cantidad_actual = _d4(estado.cantidad_actual) + cant
            estado.costo_promedio_actual = precio

        costo = _d4(estado.costo_promedio_actual)
        cant_val = min(cant, _d4(estado.cantidad_actual))
        if cant_val <= CERO or costo <= CERO:
            return
        valor = (cant_val * costo).quantize(Q2)
        mov.costo_unitario = costo
        mov.valor_total = valor
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha.date(),
            descripcion=f"Salida de almacén (costo) {valor}",
            origen="inventario", lineas=[
                LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_COSTO_VENTAS).id, debito=valor),
                LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_MERCADERIAS).id, credito=valor),
            ],
            referencia_id=mov.id, creado_por_id=creado_por_id, commit=False,
        )
        mov.asiento_id = asiento.id
        estado.cantidad_actual = _d4(estado.cantidad_actual) - cant_val


# ── Ingreso ──────────────────────────────────────────────────────────────────
def procesar_ingreso(
    db: Session, empresa_id: str, material_id: str, almacen_id: str,
    cantidad, costo_unitario, fecha: datetime | None = None,
    responsable_id: str | None = None, motivo: str | None = None,
    referencia_id: str | None = None, referencia_tipo: str | None = None,
    creado_por_id: str | None = None,
) -> MovimientoInventario:
    """Ingreso valorizado: recalcula el promedio ponderado y contabiliza
    Db 201 / Cr 611, todo atómico."""
    cant = _d4(cantidad)
    costo = _d4(costo_unitario)
    if cant <= 0:
        raise HTTPException(status_code=422, detail="La cantidad de ingreso debe ser mayor que 0.")
    if costo < 0:
        raise HTTPException(status_code=422, detail="El costo unitario no puede ser negativo.")

    fecha = fecha or datetime.utcnow()
    estado = _estado_costo(db, empresa_id, material_id, almacen_id)

    cant_prev = _d4(estado.cantidad_actual)
    costo_prev = _d4(estado.costo_promedio_actual)
    cant_nueva = cant_prev + cant
    # Promedio ponderado. cant_nueva > 0 siempre aquí (cant > 0), sin div/0.
    nuevo_promedio = ((cant_prev * costo_prev + cant * costo) / cant_nueva).quantize(Q4)
    valor_total = (cant * costo).quantize(Q2)

    mov = MovimientoInventario(
        empresa_id=empresa_id, material_id=material_id, almacen_id=almacen_id,
        tipo="entrada", cantidad=int(cant), referencia_id=referencia_id,
        referencia_tipo=referencia_tipo, responsable_id=responsable_id,
        motivo=motivo or "Ingreso valorizado", fecha=fecha,
        costo_unitario=costo, valor_total=valor_total,
    )
    db.add(mov)
    db.flush()

    lineas = [
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_MERCADERIAS).id, debito=valor_total),
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_VARIACION).id, credito=valor_total),
    ]
    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha.date(),
            descripcion=f"Ingreso a almacén (valorizado) {valor_total}",
            origen="inventario", lineas=lineas, referencia_id=mov.id,
            creado_por_id=creado_por_id, commit=False,
        )
        mov.asiento_id = asiento.id
        estado.cantidad_actual = cant_nueva
        estado.costo_promedio_actual = nuevo_promedio
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo registrar el ingreso: {exc}") from exc

    db.refresh(mov)
    return mov


# ── Salida ───────────────────────────────────────────────────────────────────
def procesar_salida(
    db: Session, empresa_id: str, material_id: str, almacen_id: str,
    cantidad, fecha: datetime | None = None, responsable_id: str | None = None,
    motivo: str | None = None, referencia_id: str | None = None,
    referencia_tipo: str | None = None, creado_por_id: str | None = None,
) -> MovimientoInventario:
    """Salida valorizada al costo promedio vigente: Db 691 / Cr 201. Rechaza si
    deja la cantidad negativa (no se puede despachar lo que no existe)."""
    cant = _d4(cantidad)
    if cant <= 0:
        raise HTTPException(status_code=422, detail="La cantidad de salida debe ser mayor que 0.")

    fecha = fecha or datetime.utcnow()
    estado = _estado_costo(db, empresa_id, material_id, almacen_id)
    cant_prev = _d4(estado.cantidad_actual)
    if cant > cant_prev:
        raise HTTPException(
            status_code=422,
            detail=f"Stock insuficiente: hay {cant_prev}, se intenta retirar {cant}.",
        )

    costo = _d4(estado.costo_promedio_actual)
    valor_total = (cant * costo).quantize(Q2)
    if valor_total <= CERO:
        raise HTTPException(status_code=422, detail="El material no tiene costo promedio cargado; registre un ingreso primero.")

    mov = MovimientoInventario(
        empresa_id=empresa_id, material_id=material_id, almacen_id=almacen_id,
        tipo="salida", cantidad=int(cant), referencia_id=referencia_id,
        referencia_tipo=referencia_tipo, responsable_id=responsable_id,
        motivo=motivo or "Salida valorizada", fecha=fecha,
        costo_unitario=costo, valor_total=valor_total,
    )
    db.add(mov)
    db.flush()

    lineas = [
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_COSTO_VENTAS).id, debito=valor_total),
        LineaAsiento(cuenta_id=_cuenta(db, empresa_id, CTA_MERCADERIAS).id, credito=valor_total),
    ]
    try:
        asiento = contab.registrar_asiento(
            db, empresa_id=empresa_id, fecha=fecha.date(),
            descripcion=f"Salida de almacén (costo) {valor_total}",
            origen="inventario", lineas=lineas, referencia_id=mov.id,
            creado_por_id=creado_por_id, commit=False,
        )
        mov.asiento_id = asiento.id
        estado.cantidad_actual = cant_prev - cant
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=f"No se pudo registrar la salida: {exc}") from exc

    db.refresh(mov)
    return mov


# ── Reporte: kardex valorizado ───────────────────────────────────────────────
def kardex_valorizado(db: Session, empresa_id: str, almacen_id: str | None = None,
                      material_id: str | None = None) -> list[dict]:
    """Saldo valorizado por material+almacén = Σ(valor ingresos) − Σ(valor salidas).
    Debe coincidir con el saldo contable de la cuenta 201-Mercaderías."""
    q = (
        db.query(
            MovimientoInventario.material_id,
            MovimientoInventario.almacen_id,
            MovimientoInventario.tipo,
            func.coalesce(func.sum(MovimientoInventario.valor_total), 0).label("valor"),
        )
        .filter(MovimientoInventario.empresa_id == empresa_id,
                MovimientoInventario.valor_total.isnot(None))
    )
    if almacen_id:
        q = q.filter(MovimientoInventario.almacen_id == almacen_id)
    if material_id:
        q = q.filter(MovimientoInventario.material_id == material_id)
    q = q.group_by(MovimientoInventario.material_id, MovimientoInventario.almacen_id,
                   MovimientoInventario.tipo)

    acc: dict[tuple, Decimal] = {}
    for mat, alm, tipo, valor in q.all():
        clave = (mat, alm)
        signo = Decimal("1") if tipo in ("entrada", "compra", "ajuste") else Decimal("-1")
        acc[clave] = acc.get(clave, CERO) + signo * _d2(valor)
    return [
        {
            "material_id": str(mat) if mat is not None else None,
            "almacen_id": str(alm) if alm is not None else None,
            "saldo_valorizado": saldo,
        }
        for (mat, alm), saldo in acc.items()
    ]


def saldo_inventario_total(db: Session, empresa_id: str) -> Decimal:
    """Suma del kardex valorizado de toda la empresa (para el invariante)."""
    total = CERO
    for fila in kardex_valorizado(db, empresa_id):
        total += fila["saldo_valorizado"]
    return total.quantize(Q2)
