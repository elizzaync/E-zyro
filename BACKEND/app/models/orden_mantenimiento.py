import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class OrdenMantenimiento(Base):
    __tablename__ = "orden_mantenimiento"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    equipo_id = Column(String(36), nullable=False)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo = Column(String(20), nullable=False)
    estado = Column(String(20), nullable=False) # Activo, Pendiente, Completado
    fecha = Column(Date, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)