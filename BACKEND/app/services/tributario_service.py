"""
Servicio tributario centralizado (Fase 6 — IGV).

Punto único de cálculo de IGV y de resolución de la cuenta contable de IGV.
AP (compras → crédito fiscal) y AR (ventas → débito fiscal) lo invocan, en vez
de embeber `0.18` o el código de cuenta `40111`. Cambiar la tasa o la cuenta es
configuración (tablas de la Fase 6), nunca código.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.contabilidad import CuentaContable
from app.models.tributario import RegimenTributarioCatalogo, ConfiguracionTributariaEmpresa

Q2 = Decimal("0.01")
CIEN = Decimal("100")
CTA_IGV_DEFECTO = "40111"


def _config(db: Session, empresa_id: str) -> ConfiguracionTributariaEmpresa | None:
    return (
        db.query(ConfiguracionTributariaEmpresa)
        .filter(ConfiguracionTributariaEmpresa.empresa_id == empresa_id)
        .first()
    )


def tasa_igv(db: Session, empresa_id: str) -> Decimal:
    """Tasa de IGV vigente de la empresa (desde configuración). Si no hay
    configuración, cae al régimen 'general' del catálogo; si tampoco, 18%."""
    cfg = _config(db, empresa_id)
    if cfg:
        reg = db.query(RegimenTributarioCatalogo).filter(
            RegimenTributarioCatalogo.id == cfg.regimen_id).first()
        if reg:
            return Decimal(str(reg.tasa_igv))
    reg = db.query(RegimenTributarioCatalogo).filter(
        RegimenTributarioCatalogo.codigo == "general").first()
    return Decimal(str(reg.tasa_igv)) if reg else Decimal("18.00")


def calcular_igv(db: Session, empresa_id: str, monto_base) -> tuple[Decimal, Decimal]:
    """Devuelve (igv, total) para una base imponible, con la tasa configurada."""
    base = Decimal(str(monto_base if monto_base is not None else 0)).quantize(Q2)
    tasa = tasa_igv(db, empresa_id)
    igv = (base * tasa / CIEN).quantize(Q2)
    return igv, (base + igv).quantize(Q2)


def cuenta_igv(db: Session, empresa_id: str, tipo: str) -> CuentaContable:
    """Cuenta contable de IGV configurada para 'credito_fiscal' o 'debito_fiscal'.
    Si no hay configuración explícita, usa la cuenta 40111 del PCGE de la empresa."""
    cfg = _config(db, empresa_id)
    cuenta_id = None
    if cfg:
        cuenta_id = (cfg.cuenta_igv_credito_fiscal_id if tipo == "credito_fiscal"
                     else cfg.cuenta_igv_debito_fiscal_id)
    if cuenta_id:
        c = db.query(CuentaContable).filter(CuentaContable.id == cuenta_id).first()
        if c:
            return c
    c = (
        db.query(CuentaContable)
        .filter(CuentaContable.empresa_id == empresa_id, CuentaContable.codigo == CTA_IGV_DEFECTO)
        .first()
    )
    if c is None:
        raise HTTPException(status_code=422, detail="No hay cuenta de IGV configurada ni 40111 en el plan.")
    return c


# ── Registros auxiliares (libros de compras / ventas) ────────────────────────
def _periodo_rango(periodo: str) -> tuple[date, date]:
    """'YYYY-MM' → (primer día, último día) del mes."""
    try:
        anio, mes = (int(x) for x in periodo.split("-"))
        ini = date(anio, mes, 1)
        fin = date(anio + (mes == 12), (mes % 12) + 1, 1)
        from datetime import timedelta
        return ini, fin - timedelta(days=1)
    except Exception:
        raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")


def registro_compras(db: Session, empresa_id: str, periodo: str) -> list[dict]:
    from app.models.cuentas_por_pagar import FacturaProveedor
    from app.models.proveedor import Proveedor
    ini, fin = _periodo_rango(periodo)
    filas = (
        db.query(FacturaProveedor, Proveedor.razon_social, Proveedor.ruc)
        .join(Proveedor, Proveedor.id == FacturaProveedor.proveedor_id)
        .filter(FacturaProveedor.empresa_id == empresa_id,
                FacturaProveedor.estado != "anulada",
                FacturaProveedor.fecha_emision >= ini,
                FacturaProveedor.fecha_emision <= fin)
        .order_by(FacturaProveedor.fecha_emision)
        .all()
    )
    return [
        {
            "fecha": f.fecha_emision, "ruc": ruc, "proveedor": razon,
            "tipo_documento": f.tipo_documento, "numero_documento": f.numero_documento,
            "base_imponible": f.subtotal, "igv": f.igv, "total": f.total,
        }
        for f, razon, ruc in filas
    ]


def registro_ventas(db: Session, empresa_id: str, periodo: str) -> list[dict]:
    from app.models.cuentas_por_cobrar import FacturaCliente
    from app.models.cliente import Cliente
    ini, fin = _periodo_rango(periodo)
    filas = (
        db.query(FacturaCliente, Cliente.razon_social, Cliente.ruc)
        .join(Cliente, Cliente.id == FacturaCliente.cliente_id)
        .filter(FacturaCliente.empresa_id == empresa_id,
                FacturaCliente.estado != "anulada",
                FacturaCliente.fecha_emision >= ini,
                FacturaCliente.fecha_emision <= fin)
        .order_by(FacturaCliente.fecha_emision)
        .all()
    )
    return [
        {
            "fecha": f.fecha_emision, "ruc": ruc, "cliente": razon,
            "tipo_documento": f.tipo_documento, "numero_documento": f.numero_documento,
            "base_imponible": f.subtotal, "igv": f.igv, "total": f.total,
        }
        for f, razon, ruc in filas
    ]
