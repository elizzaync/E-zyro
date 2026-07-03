"""
Emisión de comprobantes electrónicos (CPE) vía PSE — Nubefact.

Best-effort por diseño: la factura interna y su asiento SIEMPRE se registran;
el CPE se intenta después y su resultado queda en las columnas cpe_* de la
factura. Si falla (sin red, token inválido, SUNAT caída) la factura queda con
cpe_estado='error' y se reintenta con POST /facturas/{id}/emitir-cpe.

Doc Nubefact: https://www.nubefact.com/integracion-api
"""
from __future__ import annotations

from decimal import Decimal

import requests
from sqlalchemy.orm import Session

from app.models.cliente import Cliente
from app.models.cuentas_por_cobrar import FacturaCliente
from app.models.facturacion_electronica import ConfiguracionFacturacionElectronica
from app.models.proyecto_servicio import ProyectoServicio

_TIMEOUT = 30
# Códigos Nubefact/SUNAT
_TIPO_COMPROBANTE = {"factura": 1, "boleta": 2}
_MONEDA = {"PEN": 1, "USD": 2}


def get_config(db: Session, empresa_id: str) -> ConfiguracionFacturacionElectronica | None:
    return (
        db.query(ConfiguracionFacturacionElectronica)
        .filter(ConfiguracionFacturacionElectronica.empresa_id == empresa_id)
        .first()
    )


def habilitada(db: Session, empresa_id: str) -> bool:
    cfg = get_config(db, empresa_id)
    return bool(cfg and cfg.habilitado and cfg.api_url and cfg.api_token)


def _tipo_doc_cliente(ruc: str | None) -> tuple[str, str]:
    """(tipo, numero) SUNAT: 6=RUC, 1=DNI, '-'=sin documento (boletas)."""
    doc = (ruc or "").strip()
    if len(doc) == 11 and doc.isdigit():
        return "6", doc
    if len(doc) == 8 and doc.isdigit():
        return "1", doc
    return "-", ""


def _descripcion_item(db: Session, f: FacturaCliente) -> str:
    if f.proyecto_servicio_id:
        ps = db.query(ProyectoServicio.nombre).filter(
            ProyectoServicio.id == f.proyecto_servicio_id).first()
        if ps and ps.nombre:
            return ps.nombre
    return "Por los servicios prestados"


def emitir_cpe(db: Session, empresa_id: str, factura: FacturaCliente) -> None:
    """Envía el comprobante al PSE y guarda el resultado en cpe_* (sin commit).

    Solo factura/boleta. Nota de crédito/débito electrónica requiere el código
    de motivo SUNAT que el flujo no captura — se marca como no soportada.
    """
    # ponytail: NC/ND electrónicas fuera del v1; agregar cuando el flujo
    # capture tipo_de_nota (catálogo SUNAT 09/10).
    if factura.tipo_documento not in _TIPO_COMPROBANTE:
        factura.cpe_estado = "no_soportado"
        factura.cpe_mensaje = ("Notas de crédito/débito electrónicas aún se "
                               "emiten desde el portal del PSE.")
        return

    cfg = get_config(db, empresa_id)
    if not (cfg and cfg.habilitado and cfg.api_url and cfg.api_token):
        factura.cpe_estado = "error"
        factura.cpe_mensaje = "Facturación electrónica no configurada."
        return

    # numero_documento esperado: 'F001-123' → serie F001, correlativo 123
    partes = (factura.numero_documento or "").split("-", 1)
    if len(partes) != 2 or not partes[1].strip().isdigit():
        factura.cpe_estado = "error"
        factura.cpe_mensaje = ("El número debe tener formato SERIE-CORRELATIVO "
                               "(ej. F001-123) para emitirse electrónicamente.")
        return
    serie, numero = partes[0].strip(), int(partes[1])

    cli = db.query(Cliente).filter(Cliente.id == factura.cliente_id).first()
    tipo_doc, num_doc = _tipo_doc_cliente(cli.ruc if cli else None)
    if factura.tipo_documento == "factura" and tipo_doc != "6":
        factura.cpe_estado = "error"
        factura.cpe_mensaje = "Una factura electrónica exige cliente con RUC (11 dígitos)."
        return

    subtotal = Decimal(str(factura.subtotal))
    igv = Decimal(str(factura.igv))
    body = {
        "operacion": "generar_comprobante",
        "tipo_de_comprobante": _TIPO_COMPROBANTE[factura.tipo_documento],
        "serie": serie,
        "numero": numero,
        "sunat_transaccion": 1,  # venta interna
        "cliente_tipo_de_documento": tipo_doc,
        "cliente_numero_de_documento": num_doc,
        "cliente_denominacion": (cli.razon_social if cli else "CLIENTE"),
        "cliente_direccion": "",
        "fecha_de_emision": factura.fecha_emision.strftime("%d-%m-%Y"),
        "moneda": _MONEDA.get(factura.moneda, 1),
        "porcentaje_de_igv": float(
            (igv / subtotal * 100).quantize(Decimal("0.01")) if subtotal else 18),
        "total_gravada": float(subtotal),
        "total_igv": float(igv),
        "total": float(factura.total),
        "enviar_automaticamente_a_la_sunat": True,
        "items": [{
            "unidad_de_medida": "ZZ",  # servicios
            "codigo": "SERV",
            "descripcion": _descripcion_item(db, factura),
            "cantidad": 1,
            "valor_unitario": float(subtotal),
            "precio_unitario": float(factura.total),
            "subtotal": float(subtotal),
            "tipo_de_igv": 1,  # gravado - operación onerosa
            "igv": float(igv),
            "total": float(factura.total),
        }],
    }

    try:
        r = requests.post(
            cfg.api_url, json=body,
            headers={"Authorization": f"Token token=\"{cfg.api_token}\"",
                     "Content-Type": "application/json"},
            timeout=_TIMEOUT,
        )
        data = r.json() if r.content else {}
    except requests.RequestException:
        factura.cpe_estado = "error"
        factura.cpe_mensaje = "No se pudo contactar al PSE (Nubefact)."
        return
    except ValueError:
        factura.cpe_estado = "error"
        factura.cpe_mensaje = f"Respuesta inválida del PSE (HTTP {r.status_code})."
        return

    if r.status_code == 200 and not data.get("errors"):
        factura.cpe_estado = ("aceptado" if data.get("aceptada_por_sunat")
                              else "pendiente_sunat")
        factura.cpe_pdf_url = data.get("enlace_del_pdf")
        factura.cpe_xml_url = data.get("enlace_del_xml")
        factura.cpe_cdr_url = data.get("enlace_del_cdr")
        factura.cpe_mensaje = data.get("sunat_description") or None
    else:
        factura.cpe_estado = "error"
        factura.cpe_mensaje = str(data.get("errors") or f"HTTP {r.status_code}")[:500]
