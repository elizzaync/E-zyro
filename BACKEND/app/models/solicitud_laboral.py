import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Date, Text, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class SolicitudLaboral(Base):
    __tablename__ = "solicitud_laboral"

    id               = Column(String(36), primary_key=True, default=generate_uuid)
    empleado_id      = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo             = Column(String(50), nullable=False)
    estado           = Column(String(20), nullable=False, default='pendiente')
    descripcion      = Column(Text)
    fecha_inicio     = Column(Date)
    fecha_fin        = Column(Date)
    aprobado_por     = Column(String(36), nullable=True)
    fecha_aprobacion = Column(DateTime, nullable=True)
    observacion      = Column(String(500))
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True)
