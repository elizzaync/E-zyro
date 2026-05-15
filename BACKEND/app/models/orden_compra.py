import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Numeric, Date, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class OrdenCompra(Base):
    __tablename__ = "orden_compra"

    id                      = Column(String(36), primary_key=True, default=_uuid)
    empresa_id              = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proveedor_id            = Column(String(36), ForeignKey("proveedor.id"), nullable=False)
    requerimiento_id        = Column(String(36), ForeignKey("requerimiento.id"), nullable=True)
    estado                  = Column(String(20), nullable=False, default="borrador")  # borrador|enviada|confirmada|en_transito|recibida|cancelada
    fecha_emision           = Column(Date, nullable=False)
    fecha_entrega_estimada  = Column(Date, nullable=True)
    fecha_entrega_real      = Column(Date, nullable=True)
    total_referencial       = Column(Numeric(10, 2), nullable=True)
    created_at              = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at              = Column(DateTime, nullable=True)


class DetalleCompra(Base):
    __tablename__ = "detalle_compra"

    id              = Column(String(36), primary_key=True, default=_uuid)
    orden_id        = Column(String(36), ForeignKey("orden_compra.id"), nullable=False)
    material_id     = Column(String(36), ForeignKey("material.id"), nullable=False)
    cantidad        = Column(Integer, nullable=False)
    precio_unitario = Column(Numeric(10, 2), nullable=False)
