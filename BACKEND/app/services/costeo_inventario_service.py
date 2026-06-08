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

from app.models.contabilidad import CuentaContable
from app.models.costeo_inventario import CostoPromedioMaterial
from app.models.movimiento_inventario import MovimientoInventario
from app.services import contabilizacion_service as contab
from app.services.contabilizacion_service import LineaAsiento

CERO = Decimal("0.00")
Q4 = Decimal("0.0001")
Q2 = Decimal("0.01")

CTA_MERCADERIAS  = "201"   # 20 Mercaderías (detalle)
CTA_VARIACION    = "611"   # 61 Variación de existencias (detalle)
CTA_COSTO_VENTAS = "691"   # 69 Costo de ventas (detalle)


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
        {"material_id": mat, "almacen_id": alm, "saldo_valorizado": saldo}
        for (mat, alm), saldo in acc.items()
    ]


def saldo_inventario_total(db: Session, empresa_id: str) -> Decimal:
    """Suma del kardex valorizado de toda la empresa (para el invariante)."""
    total = CERO
    for fila in kardex_valorizado(db, empresa_id):
        total += fila["saldo_valorizado"]
    return total.quantize(Q2)
