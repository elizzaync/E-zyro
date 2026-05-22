import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class EvidenciaMantenimiento(Base):
    __tablename__ = "evidencia_mantenimiento"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    orden_id             = Column(String(36), ForeignKey("orden_mantenimiento.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    paso_id              = Column(String(36), ForeignKey("paso_mantenimiento.id"), nullable=True)
    etapa                = Column(String(20), nullable=False)   # antes|durante|despues
    url_cloudinary       = Column(String(500), nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    descripcion          = Column(String(500), nullable=True)
    fecha_captura        = Column(DateTime, nullable=False, default=datetime.utcnow)
