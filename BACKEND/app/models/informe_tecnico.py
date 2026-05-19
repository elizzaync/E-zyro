import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, Date, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class InformeTecnico(Base):
    __tablename__ = "informe_tecnico"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    orden_id             = Column(String(36), ForeignKey("orden_mantenimiento.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    titulo               = Column(String(200), nullable=False)
    contenido            = Column(Text, nullable=True)
    url_archivo          = Column(String(500), nullable=True)
    public_id_cloudinary = Column(String(255), nullable=True)
    generado_por         = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    fecha                = Column(Date, nullable=False)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
