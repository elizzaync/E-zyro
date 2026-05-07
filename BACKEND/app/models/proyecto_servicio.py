import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, Integer, Text, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class ProyectoServicio(Base):
    __tablename__ = "proyecto_servicio"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    catalogo_servicio_id = Column(String(36), nullable=False)
    fase_id = Column(String(36))
    nombre = Column(String(200), nullable=False)
    descripcion = Column(Text)
    responsable_id = Column(String(36), ForeignKey("empleado.id"))
    orden = Column(Integer, nullable=False, default=1)
    estado = Column(String(30), nullable=False, default='Pendiente')
    fecha_programada = Column(Date)
    fecha_inicio = Column(Date)
    fecha_fin = Column(Date)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime)