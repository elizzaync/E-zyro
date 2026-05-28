import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Numeric, Boolean, Text, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class TicketCompra(Base):
    __tablename__ = "ticket_compra"

    id                     = Column(String(36), primary_key=True, default=_uuid)
    empresa_id             = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    requerimiento_id       = Column(String(36), ForeignKey("requerimiento.id"), nullable=True)
    codigo                 = Column(String(20), nullable=False)
    estado                 = Column(String(20), nullable=False, default="pendiente")
    # Contexto desnormalizado (para no hacer JOIN en cada listado)
    proyecto_id            = Column(String(36), nullable=True)
    proyecto_servicio_id   = Column(String(36), nullable=True)
    proyecto_nombre        = Column(String(300), nullable=True)
    servicio_nombre        = Column(String(300), nullable=True)
    solicitante_nombre     = Column(String(200), nullable=True)
    # Modo de compra (se guarda al procesar)
    modo_unificado         = Column(Boolean, nullable=True)
    proveedor_unico_id     = Column(String(36), nullable=True)   # demo id, no FK
    proveedor_unico_nombre = Column(String(200), nullable=True)
    canal_unico            = Column(String(200), nullable=True)
    # Totales
    total_estimado         = Column(Numeric(12, 2), nullable=True)
    total_real             = Column(Numeric(12, 2), nullable=True)
    # Responsable de compras
    responsable_id         = Column(String(36), nullable=True)
    nota                   = Column(Text, nullable=True)
    motivo_cancelacion     = Column(Text, nullable=True)
    created_at             = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at             = Column(DateTime, nullable=True)


class TicketCompraItem(Base):
    __tablename__ = "ticket_compra_item"

    id                       = Column(String(36), primary_key=True, default=_uuid)
    ticket_id                = Column(String(36), ForeignKey("ticket_compra.id"), nullable=False)
    requerimiento_detalle_id = Column(String(36), nullable=True)
    material_id              = Column(String(36), nullable=True)
    nombre                   = Column(String(300), nullable=False)
    cantidad                 = Column(Integer, nullable=False, default=1)
    unidad                   = Column(String(50), nullable=True)
    cantidad_comprada        = Column(Integer, nullable=True)
    precio_unitario          = Column(Numeric(12, 2), nullable=True)
    total_item               = Column(Numeric(12, 2), nullable=True)
    proveedor_id             = Column(String(36), nullable=True)
    proveedor_nombre         = Column(String(200), nullable=True)
    canal_personalizado      = Column(String(200), nullable=True)
    factura                  = Column(String(100), nullable=True)
    estado_item              = Column(String(20), nullable=False, default="pendiente")
    nota                     = Column(Text, nullable=True)
