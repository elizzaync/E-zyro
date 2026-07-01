"""
Modelos de Cuentas por Cobrar — AR (Fase 4 del módulo de finanzas).

Espejo simétrico de AP (Fase 3) del lado de ingresos: comprobantes emitidos a
clientes, cobros y su aplicación. Cada hecho genera su asiento automático vía
`contabilizacion_service`. Referencian `empresa`, `cliente`, `proyecto` y
`asiento_contable` ya existentes — no los alteran.
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


class FacturaCliente(Base):
    __tablename__ = "factura_cliente"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    cliente_id        = Column(String(36), ForeignKey("cliente.id"), nullable=False)
    proyecto_id       = Column(String(36), ForeignKey("proyecto.id"), nullable=True)
    # Servicio que originó la factura (cuando se emite desde "Facturar servicio").
    # Permite listar servicios completados aún sin facturar y evitar doble emisión.
    proyecto_servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=True)
    numero_documento  = Column(String(50), nullable=False)
    tipo_documento    = Column(String(20), nullable=False)   # factura|boleta|nota_credito|nota_debito
    fecha_emision     = Column(Date, nullable=False)
    fecha_vencimiento = Column(Date, nullable=True)          # null si es al contado
    # Nota de crédito: comprobante del mismo cliente cuyo saldo rebaja.
    # Referencia lógica a factura_cliente.id (columna uuid en prod, ver migración).
    documento_afectado_id = Column(String(36), nullable=True)
    moneda            = Column(String(3), nullable=False, default="PEN")
    subtotal          = Column(Numeric(14, 2), nullable=False, default=0)
    igv               = Column(Numeric(14, 2), nullable=False, default=0)
    total             = Column(Numeric(14, 2), nullable=False, default=0)
    estado            = Column(String(20), nullable=False, default="pendiente")  # pendiente|cobrada_parcial|cobrada|anulada
    asiento_id        = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at        = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "tipo_documento", "numero_documento",
                         name="uq_factura_cli_doc"),
        CheckConstraint(
            "tipo_documento IN ('factura','boleta','nota_credito','nota_debito')",
            name="chk_factura_cli_tipo_documento",
        ),
        CheckConstraint(
            "estado IN ('pendiente','cobrada_parcial','cobrada','anulada')",
            name="chk_factura_cli_estado",
        ),
        CheckConstraint("subtotal >= 0 AND igv >= 0 AND total >= 0",
                        name="chk_factura_cli_montos_no_negativos"),
    )


class CobroCliente(Base):
    __tablename__ = "cobro_cliente"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    cliente_id   = Column(String(36), ForeignKey("cliente.id"), nullable=False)
    fecha_cobro  = Column(Date, nullable=False)
    monto        = Column(Numeric(14, 2), nullable=False)
    medio_pago   = Column(String(20), nullable=False)   # efectivo|transferencia|cheque
    referencia   = Column(String(100), nullable=True)
    asiento_id   = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        CheckConstraint(
            "medio_pago IN ('efectivo','transferencia','cheque')",
            name="chk_cobro_medio",
        ),
        CheckConstraint("monto > 0", name="chk_cobro_monto_positivo"),
    )


class AplicacionCobroCliente(Base):
    __tablename__ = "aplicacion_cobro_cliente"

    id             = Column(String(36), primary_key=True, default=_uuid)
    cobro_id       = Column(String(36), ForeignKey("cobro_cliente.id"), nullable=False)
    factura_id     = Column(String(36), ForeignKey("factura_cliente.id"), nullable=False)
    monto_aplicado = Column(Numeric(14, 2), nullable=False)

    __table_args__ = (
        CheckConstraint("monto_aplicado > 0", name="chk_aplicacion_cobro_monto_positivo"),
    )
