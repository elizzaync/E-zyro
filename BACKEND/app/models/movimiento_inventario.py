import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class MovimientoInventario(Base):
    __tablename__ = "movimiento_inventario"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    material_id      = Column(String(36), ForeignKey("material.id"), nullable=False)
    almacen_id       = Column(String(36), ForeignKey("almacen.id"), nullable=True)
    tipo             = Column(String(20), nullable=False)   # entrada|salida|ajuste|requerimiento|transferencia|compra
    cantidad         = Column(Integer, nullable=False)
    referencia_id    = Column(String(36), nullable=True)
    referencia_tipo  = Column(String(50), nullable=True)
    responsable_id   = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    fecha            = Column(DateTime, nullable=False)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
