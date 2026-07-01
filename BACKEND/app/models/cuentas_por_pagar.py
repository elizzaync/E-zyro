"""
Modelos de Cuentas por Pagar — AP (Fase 3 del módulo de finanzas).

Convierte el campo de texto libre `ticket_compra.factura` en un documento real
con estado y vencimiento, y conecta el ciclo compra→pago al libro mayor: cada
factura/pago genera su asiento automático vía `contabilizacion_service` (el
único punto de escritura contable). Estas tablas referencian `empresa`,
`proveedor`, `orden_compra` y `asiento_contable` ya existentes — no los alteran.

Invariantes defendidos en BD (CheckConstraint), no solo en el código:
  - tipo_documento y estado acotados por CHECK.
  - montos no negativos; total = subtotal + igv (validado en servicio/schema).
  - UNIQUE(empresa, proveedor, numero_documento): sin facturas duplicadas.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Date, DateTime, Numeric,
    ForeignKey, CheckConstraint, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class FacturaProveedor(Base):
    __tablename__ = "factura_proveedor"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proveedor_id      = Column(String(36), ForeignKey("proveedor.id"), nullable=False)
    orden_compra_id   = Column(String(36), ForeignKey("orden_compra.id"), nullable=True)
    numero_documento  = Column(String(50), nullable=False)
    tipo_documento    = Column(String(20), nullable=False)   # factura|boleta|nota_credito|nota_debito
    fecha_emision     = Column(Date, nullable=False)
    fecha_vencimiento = Column(Date, nullable=False)
    moneda            = Column(String(3), nullable=False, default="PEN")
    subtotal          = Column(Numeric(14, 2), nullable=False, default=0)
    igv               = Column(Numeric(14, 2), nullable=False, default=0)
    total             = Column(Numeric(14, 2), nullable=False, default=0)
    estado            = Column(String(20), nullable=False, default="pendiente")  # pendiente|pagada_parcial|pagada|anulada
    asiento_id        = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    # Cuenta de gasto que debita la factura manual (601 mercadería | 63/65 servicios…).
    # Referencia lógica a cuenta_contable.id (sin FK: esa PK es uuid nativo en prod).
    cuenta_gasto_id   = Column(String(36), nullable=True)
    # Nota de crédito: factura del mismo proveedor cuyo saldo rebaja.
    # Referencia lógica a factura_proveedor.id (columna uuid en prod, ver migración).
    documento_afectado_id = Column(String(36), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at        = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "proveedor_id", "numero_documento",
                         name="uq_factura_prov_doc"),
        CheckConstraint(
            "tipo_documento IN ('factura','boleta','nota_credito','nota_debito')",
            name="chk_factura_tipo_documento",
        ),
        CheckConstraint(
            "estado IN ('pendiente','pagada_parcial','pagada','anulada')",
            name="chk_factura_estado",
        ),
        CheckConstraint("subtotal >= 0 AND igv >= 0 AND total >= 0",
                        name="chk_factura_montos_no_negativos"),
    )


class PagoProveedor(Base):
    __tablename__ = "pago_proveedor"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proveedor_id = Column(String(36), ForeignKey("proveedor.id"), nullable=False)
    fecha_pago   = Column(Date, nullable=False)
    monto        = Column(Numeric(14, 2), nullable=False)
    medio_pago   = Column(String(20), nullable=False)   # efectivo|transferencia|cheque
    referencia   = Column(String(100), nullable=True)
    asiento_id   = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        CheckConstraint(
            "medio_pago IN ('efectivo','transferencia','cheque')",
            name="chk_pago_medio",
        ),
        CheckConstraint("monto > 0", name="chk_pago_monto_positivo"),
    )


class AplicacionPagoProveedor(Base):
    """Puente N:N — un pago puede cubrir varias facturas y una factura admitir
    varios pagos parciales. `monto_aplicado` es la porción del pago imputada a
    esa factura; su suma por factura nunca puede exceder el total de la factura."""
    __tablename__ = "aplicacion_pago_proveedor"

    id             = Column(String(36), primary_key=True, default=_uuid)
    pago_id        = Column(String(36), ForeignKey("pago_proveedor.id"), nullable=False)
    factura_id     = Column(String(36), ForeignKey("factura_proveedor.id"), nullable=False)
    monto_aplicado = Column(Numeric(14, 2), nullable=False)

    __table_args__ = (
        CheckConstraint("monto_aplicado > 0", name="chk_aplicacion_monto_positivo"),
    )
