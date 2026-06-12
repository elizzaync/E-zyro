import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, ForeignKey, Boolean
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class DocumentoLaboral(Base):
    __tablename__ = "documento_laboral"

    id                   = Column(String(36), primary_key=True, default=generate_uuid)
    empleado_id          = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo                 = Column(String(50), nullable=False)
    nombre               = Column(String(200), nullable=False)
    url_archivo          = Column(String(500), nullable=True)
    public_id_cloudinary = Column(String(255), nullable=True)
    fecha_emision        = Column(Date, nullable=False)
    requiere_firma       = Column(Boolean, nullable=False, default=False)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
