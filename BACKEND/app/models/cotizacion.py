"""
Modelos del ciclo comercial: cotización → aceptación → proyecto.

La cotización es pre-venta: nace en borrador, se envía al cliente (PDF),
y al aceptarse puede convertirse en Proyecto + ContratoComercial con un tap.
NOTA: las tablas se crean con SQL crudo en _run_migrations de main.py
(PK/FK uuid en producción); NO confiar en create_all.
"""
import uuid
from datetime import date, datetime

from sqlalchemy import (
    Column, String, Date, DateTime, Integer, Numeric, Text,
    ForeignKey, CheckConstraint, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Cotizacion(Base):
    __tablename__ = "cotizacion"

    id               = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id       = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    cliente_id       = Column(UUID(as_uuid=False), ForeignKey("cliente.id"), nullable=False)
    numero           = Column(String(30), nullable=False)          # COT-2026-0001
    fecha_emision    = Column(Date, nullable=False, default=date.today)
    validez_dias     = Column(Integer, nullable=False, default=30)
    # borrador → enviada → aceptada|rechazada|vencida → convertida (solo desde aceptada)
    estado           = Column(String(20), nullable=False, default="borrador")
    moneda           = Column(String(3), nullable=False, default="PEN")
    subtotal         = Column(Numeric(14, 2), nullable=False, default=0)
    igv              = Column(Numeric(14, 2), nullable=False, default=0)
    total            = Column(Numeric(14, 2), nullable=False, default=0)
    condiciones_pago = Column(String(300), nullable=True)
    notas            = Column(Text, nullable=True)
    # Resultado de la conversión (cotización aceptada → proyecto)
    proyecto_id            = Column(UUID(as_uuid=False), ForeignKey("proyecto.id"), nullable=True)
    contrato_comercial_id  = Column(UUID(as_uuid=False), ForeignKey("contrato_comercial.id"), nullable=True)
    # Resolución (interna o desde el portal del cliente)
    resuelto_via     = Column(String(20), nullable=True)   # interno | portal
    fecha_resolucion = Column(DateTime, nullable=True)
    creado_por_id    = Column(UUID(as_uuid=False), ForeignKey("usuario.id"), nullable=True)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "numero", name="uq_cotizacion_empresa_numero"),
        CheckConstraint(
            "estado IN ('borrador','enviada','aceptada','rechazada','vencida','convertida')",
            name="chk_cotizacion_estado",
        ),
    )


class CotizacionItem(Base):
    __tablename__ = "cotizacion_item"

    id              = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    cotizacion_id   = Column(UUID(as_uuid=False),
                             ForeignKey("cotizacion.id", ondelete="CASCADE"),
                             nullable=False)
    descripcion     = Column(String(500), nullable=False)
    unidad          = Column(String(30), nullable=True)     # servicio, unidad, hora…
    cantidad        = Column(Numeric(12, 2), nullable=False, default=1)
    precio_unitario = Column(Numeric(14, 2), nullable=False, default=0)
    total           = Column(Numeric(14, 2), nullable=False, default=0)
    orden           = Column(Integer, nullable=False, default=1)

    __table_args__ = (
        CheckConstraint("cantidad > 0", name="chk_cotizacion_item_cantidad"),
        CheckConstraint("precio_unitario >= 0 AND total >= 0",
                        name="chk_cotizacion_item_montos"),
    )
