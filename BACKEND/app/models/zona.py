import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Zona(Base):
    """Zona dentro de una ubicación (catálogo). `tipo` libre (p. ej. eléctrica, almacén)."""
    __tablename__ = "zona"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    ubicacion_id = Column(String(36), ForeignKey("ubicacion.id"), nullable=True)
    nombre       = Column(String(150), nullable=False)
    tipo         = Column(String(50), nullable=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
