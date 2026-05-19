import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Proveedor(Base):
    __tablename__ = "proveedor"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    razon_social = Column(String(200), nullable=False)
    ruc          = Column(String(20), nullable=True)
    contacto     = Column(String(150), nullable=True)
    email        = Column(String(150), nullable=True)
    telefono     = Column(String(20), nullable=True)
    direccion    = Column(String(300), nullable=True)
    activo       = Column(Boolean, nullable=False, default=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)


class ProveedorCategoria(Base):
    __tablename__ = "proveedor_categoria"

    proveedor_id = Column(String(36), ForeignKey("proveedor.id"), primary_key=True)
    categoria_id = Column(String(36), ForeignKey("categoria_material.id"), primary_key=True)
