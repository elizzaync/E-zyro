import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Ubicacion(Base):
    """Ubicación geográfica (catálogo): nombre + región. Base para zonas/EPP/ITSE."""
    __tablename__ = "ubicacion"

    id         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre     = Column(String(150), nullable=False)
    region     = Column(String(100), nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
