import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class PasoMantenimiento(Base):
    """Paso del checklist técnico para un equipo concreto.

    Se genera la primera vez que el técnico abre el checklist del equipo
    (auto-poblado desde `tipo_equipo.procedimiento_tecnico`, o desde una
    lista por defecto si el tipo no tiene plantilla).
    """
    __tablename__ = "paso_mantenimiento"

    id          = Column(String(36), primary_key=True, default=_uuid)
    equipo_id   = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre      = Column(String(200), nullable=False)
    descripcion = Column(Text, nullable=True)
    orden       = Column(Integer, nullable=False, default=1)
    estado      = Column(String(20), nullable=False, default="pendiente")  # pendiente|en_proceso|completado
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at  = Column(DateTime, nullable=True)
