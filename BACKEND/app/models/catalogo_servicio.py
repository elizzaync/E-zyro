import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Text, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class CatalogoServicio(Base):
    __tablename__ = "catalogo_servicio"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_trabajo = Column(String(50), nullable=False)
    nombre = Column(String(150), nullable=False)
    descripcion = Column(Text)
    activo = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)