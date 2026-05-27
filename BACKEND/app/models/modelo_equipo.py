import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ModeloEquipo(Base):
    """Modelos asociados a una Marca (catálogo seleccionable)."""
    __tablename__ = "modelo_equipo"

    id         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    marca_id   = Column(String(36), ForeignKey("marca.id"), nullable=False)
    nombre     = Column(String(120), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
