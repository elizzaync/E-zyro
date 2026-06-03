import uuid
from sqlalchemy import Column, String, Text, ForeignKey
from sqlalchemy.dialects.postgresql import JSONB
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class TipoEquipo(Base):
    __tablename__ = "tipo_equipo"

    id                      = Column(String(36), primary_key=True, default=_uuid)
    empresa_id              = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre                  = Column(String(100), nullable=False)
    descripcion             = Column(Text, nullable=True)
    procedimiento_tecnico   = Column(Text, nullable=True)
    procedimientos_template = Column(JSONB, nullable=True)  # checklist estático por tipo de equipo
