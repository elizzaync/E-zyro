import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class UnidadMedida(Base):
    """Unidades de medida para materiales (catálogo seleccionable)."""
    __tablename__ = "unidad_medida"

    id         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre     = Column(String(60), nullable=False)         # "Unidad", "Metros", "Kilogramos"...
    abreviatura = Column(String(15), nullable=True)         # "und", "m", "kg"...
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
