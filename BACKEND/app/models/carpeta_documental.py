import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class CarpetaDocumental(Base):
    __tablename__ = "carpeta_documental"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=True)
    padre_id    = Column(String(36), ForeignKey("carpeta_documental.id"), nullable=True)
    nombre      = Column(String(150), nullable=False)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
