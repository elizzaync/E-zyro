import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Contrato(Base):
    __tablename__ = "contrato"

    id                   = Column(String(36), primary_key=True, default=generate_uuid)
    empleado_id          = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo                 = Column(String(50), nullable=False)
    fecha_inicio         = Column(Date, nullable=False)
    fecha_fin            = Column(Date, nullable=True)
    estado               = Column(String(20), nullable=False, default='vigente')
    documento_url        = Column(String(500), nullable=True)
    public_id_cloudinary = Column(String(255), nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime, nullable=True)
