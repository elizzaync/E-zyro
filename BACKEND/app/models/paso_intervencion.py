import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, Integer, Boolean, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class PasoIntervencion(Base):
    """Paso del checklist técnico para una intervención específica de un equipo
    dentro de un servicio. Se crea automáticamente desde la plantilla del
    tipo_equipo o desde _PASOS_POR_DEFECTO la primera vez que se abre la vista."""

    __tablename__ = "paso_intervencion"

    id                    = Column(String(36), primary_key=True, default=_uuid)
    equipo_intervenido_id = Column(String(36), ForeignKey("equipo_intervenido.id"), nullable=False)
    empresa_id            = Column(String(36), ForeignKey("empresa.id"),            nullable=False)
    nombre                = Column(String(200), nullable=False)
    descripcion           = Column(Text,        nullable=True)
    orden                 = Column(Integer,     nullable=False, default=1)
    completado            = Column(Boolean,     nullable=False, default=False)
    foto_url              = Column(String(500), nullable=True)
    foto_public_id        = Column(String(255), nullable=True)
    created_at            = Column(DateTime,    nullable=False, default=datetime.utcnow)
