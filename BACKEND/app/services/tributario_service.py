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


# ── Export PLE (Programa de Libros Electrónicos — SUNAT) ─────────────────────
# TXT pipe-delimited, estructura v5.2: 8.1 Registro de Compras (080100) y
# 14.1 Registro de Ventas (140100). Los campos que este ERP no maneja aún
# (DUA, detracciones, documentos modificados…) van vacíos o en cero, que es
# válido cuando no aplican. Antes de la PRIMERA presentación real, pasar el
# archivo por el Validador PLE de SUNAT y ajustar aquí cualquier posición.

TIPO_DOC_SUNAT = {
    "factura": "01", "recibo_honorarios": "02", "boleta": "03",
    "nota_credito": "07", "nota_debito": "08",
}


def _ruc_empresa(db: Session, empresa_id: str) -> str:
    from app.models.empresa import Empresa
    emp = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    ruc = (getattr(emp, "ruc", None) or "").strip()
    if len(ruc) != 11 or not ruc.isdigit():
        raise HTTPException(
            status_code=422,
            detail="La empresa no tiene un RUC válido de 11 dígitos; "
                   "corríjalo antes de generar el PLE.",
        )
    return ruc


def _serie_numero(numero_documento: str) -> tuple[str, str]:
    """'F001-00000123' → ('F001', '123'). Sin guion: serie vacía."""
    if "-" in (numero_documento or ""):
        serie, _, num = numero_documento.partition("-")
        return serie.strip(), num.strip().lstrip("0") or "0"
    return "", (numero_documento or "").strip()


def _f(v) -> str:
    return f"{Decimal(str(v if v is not None else 0)):.2f}"


def _fecha(d: date | None) -> str:
    return d.strftime("%d/%m/%Y") if d else ""


def _nombre_ple(ruc: str, anio: int, mes: int, codigo_libro: str, con_info: bool) -> str:
    # LE + RUC + AAAAMM00 + libro(6) + oportunidad(00) + operaciones(1)
    #    + contenido(1|0) + moneda PEN(1) + libro electrónico(1) + .txt
    return f"LE{ruc}{anio}{mes:02d}00{codigo_libro}001{'1' if con_info else '0'}11.txt"


def registro_compras_ple(db: Session, empresa_id: str, periodo: str) -> dict:
    """Registro de Compras 8.1 en TXT PLE. Devuelve nombre + contenido."""
    ruc = _ruc_empresa(db, empresa_id)
    anio, mes = (int(x) for x in periodo.split("-"))
    filas = registro_compras(db, empresa_id, periodo)
    lineas = []
    for i, r in enumerate(filas, start=1):
        serie, numero = _serie_numero(r["numero_documento"])
        ruc_prov = (r["ruc"] or "").strip()
        tipo_ident = "6" if len(ruc_prov) == 11 else "0"
        campos = [
            f"{anio}{mes:02d}00",                      # 1  periodo
            f"{i:06d}",                                # 2  CUO
            f"M{i:06d}",                               # 3  correlativo asiento
            _fecha(r["fecha"]),                        # 4  fecha emisión
            "",                                        # 5  fecha vencimiento/pago
            TIPO_DOC_SUNAT.get(r["tipo_documento"], "00"),  # 6 tipo comprobante
            serie,                                     # 7  serie
            "",                                        # 8  año DUA/DSI
            numero,                                    # 9  número
            "",                                        # 10 nº final (consolidado)
            tipo_ident,                                # 11 tipo doc proveedor
            ruc_prov,                                  # 12 nº doc proveedor
            r["proveedor"],                            # 13 razón social
            _f(r["base_imponible"]),                   # 14 BI gravada
            _f(r["igv"]),                              # 15 IGV
            "0.00", "0.00", "0.00", "0.00",            # 16-19 BI/IGV mixtas
            "0.00",                                    # 20 no gravadas
            "0.00",                                    # 21 ISC
            "0.00",                                    # 22 ICBPER
            "0.00",                                    # 23 otros tributos
            _f(r["total"]),                            # 24 importe total
            "PEN",                                     # 25 moneda
            "1.000",                                   # 26 tipo de cambio
            "", "", "", "",                            # 27-30 doc modificado
            "", "",                                    # 31-32 detracción
            "",                                        # 33 marca retención
            "",                                        # 34 clasificación bienes
            "",                                        # 35 contrato
            "", "", "", "",                            # 36-39 errores tipo 1-4
            "",                                        # 40 medios de pago
            "1",                                       # 41 estado
        ]
        lineas.append("|".join(campos) + "|")
    contenido = "\r\n".join(lineas) + ("\r\n" if lineas else "")
    return {"nombre_archivo": _nombre_ple(ruc, anio, mes, "080100", bool(lineas)),
            "lineas": len(lineas), "contenido": contenido}


def registro_ventas_ple(db: Session, empresa_id: str, periodo: str) -> dict:
    """Registro de Ventas e Ingresos 14.1 en TXT PLE."""
    ruc = _ruc_empresa(db, empresa_id)
    anio, mes = (int(x) for x in periodo.split("-"))
    filas = registro_ventas(db, empresa_id, periodo)
    lineas = []
    for i, r in enumerate(filas, start=1):
        serie, numero = _serie_numero(r["numero_documento"])
        ruc_cli = (r["ruc"] or "").strip()
        tipo_ident = "6" if len(ruc_cli) == 11 else "0"
        campos = [
            f"{anio}{mes:02d}00",                      # 1  periodo
            f"{i:06d}",                                # 2  CUO
            f"M{i:06d}",                               # 3  correlativo asiento
            _fecha(r["fecha"]),                        # 4  fecha emisión
            "",                                        # 5  fecha vencimiento
            TIPO_DOC_SUNAT.get(r["tipo_documento"], "00"),  # 6 tipo comprobante
            serie,                                     # 7  serie
            numero,                                    # 8  número
            "",                                        # 9  nº final (consolidado)
            tipo_ident,                                # 10 tipo doc cliente
            ruc_cli,                                   # 11 nº doc cliente
            r["cliente"],                              # 12 razón social
            "0.00",                                    # 13 exportación
            _f(r["base_imponible"]),                   # 14 BI gravada
            "0.00",                                    # 15 dscto BI
            _f(r["igv"]),                              # 16 IGV
            "0.00",                                    # 17 dscto IGV
            "0.00",                                    # 18 exonerado
            "0.00",                                    # 19 inafecto
            "0.00",                                    # 20 ISC
            "0.00",                                    # 21 BI arroz pilado
            "0.00",                                    # 22 imp. arroz pilado
            "0.00",                                    # 23 ICBPER
            "0.00",                                    # 24 otros cargos
            _f(r["total"]),                            # 25 importe total
            "PEN",                                     # 26 moneda
            "1.000",                                   # 27 tipo de cambio
            "", "", "", "",                            # 28-31 doc modificado
            "",                                        # 32 contrato
            "",                                        # 33 error tipo 1
            "",                                        # 34 medios de pago
            "1",                                       # 35 estado
        ]
        lineas.append("|".join(campos) + "|")
    contenido = "\r\n".join(lineas) + ("\r\n" if lineas else "")
    return {"nombre_archivo": _nombre_ple(ruc, anio, mes, "140100", bool(lineas)),
            "lineas": len(lineas), "contenido": contenido}
