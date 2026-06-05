import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Almacen(Base):
    __tablename__ = "almacen"

    id             = Column(String(36), primary_key=True, default=_uuid)
    empresa_id     = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre         = Column(String(100), nullable=False)
    ubicacion      = Column(String(255), nullable=True)
    responsable_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    activo         = Column(Boolean, nullable=False, default=True)
    predeterminado = Column(Boolean, nullable=False, default=False)  # almacén por defecto (Oficina): destino de altas/compras
    created_at     = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at     = Column(DateTime, nullable=True)
