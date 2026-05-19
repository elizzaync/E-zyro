import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class RecepcionCompra(Base):
    __tablename__ = "recepcion_compra"

    id          = Column(String(36), primary_key=True, default=_uuid)
    orden_id    = Column(String(36), ForeignKey("orden_compra.id"), nullable=False)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    receptor_id = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    almacen_id  = Column(String(36), ForeignKey("almacen.id"), nullable=False)
    estado      = Column(String(20), nullable=False, default="completa")  # completa|parcial|con_diferencias
    fecha       = Column(DateTime, nullable=False)
    notas       = Column(Text, nullable=True)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)


class RecepcionDetalle(Base):
    __tablename__ = "recepcion_detalle"

    id                = Column(String(36), primary_key=True, default=_uuid)
    recepcion_id      = Column(String(36), ForeignKey("recepcion_compra.id"), nullable=False)
    material_id       = Column(String(36), ForeignKey("material.id"), nullable=False)
    cantidad_esperada = Column(Integer, nullable=False)
    cantidad_recibida = Column(Integer, nullable=False)
    estado_item       = Column(String(20), nullable=False)   # completo|parcial|faltante|danado
    observacion       = Column(String(255), nullable=True)
