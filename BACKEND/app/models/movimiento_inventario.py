import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Numeric
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
    motivo           = Column(String(300), nullable=True)   # sustento libre: "Despacho al servicio X", "Recepción OC", etc.
    fecha            = Column(DateTime, nullable=False)
    # Valuación de inventario (Fase 5): se rellenan al procesar el movimiento
    # con costeo. Existentes sin costear quedan en NULL (referencia histórica).
    costo_unitario   = Column(Numeric(14, 4), nullable=True)
    valor_total      = Column(Numeric(14, 2), nullable=True)
    asiento_id       = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
