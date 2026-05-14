import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, Boolean, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Material(Base):
    __tablename__ = "material"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    categoria_id = Column(String(36))
    nombre       = Column(String(200), nullable=False)
    codigo       = Column(String(50))
    unidad       = Column(String(30),  nullable=False)
    descripcion  = Column(String(255))
    activo       = Column(Boolean, nullable=False, default=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)


class Stock(Base):
    __tablename__ = "stock"

    material_id     = Column(String(36), ForeignKey("material.id"),  primary_key=True)
    empresa_id      = Column(String(36), ForeignKey("empresa.id"),   primary_key=True)
    almacen_id      = Column(String(36),                             primary_key=True)
    cantidad        = Column(Integer, nullable=False, default=0)
    cantidad_minima = Column(Integer, nullable=False, default=0)
    updated_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
