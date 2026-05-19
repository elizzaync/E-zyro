import uuid
from sqlalchemy import Column, String, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class ProyectoEquipo(Base):
    __tablename__ = "proyecto_equipo"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    proyecto_id         = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    equipo_id           = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_intervencion   = Column(String(100), nullable=True)
    observaciones       = Column(Text, nullable=True)
