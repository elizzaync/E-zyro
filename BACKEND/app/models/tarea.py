import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, Date, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Tarea(Base):
    """Cronograma del servicio: ítems que el jefe de operaciones añade/quita y
    asigna (responsable + fechas). Alimentan el Diagrama de Gantt.

    Antes esta data vivía en la tabla `procedimiento`; se separó para que
    `procedimiento` quede reservado a los pasos fijos por tipo de trabajo.
    """
    __tablename__ = "tarea"

    id                     = Column(String(36), primary_key=True, default=_uuid)
    proyecto_servicio_id   = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=False)
    empresa_id             = Column(String(36), ForeignKey("empresa.id"),           nullable=False)
    responsable_id         = Column(String(36), ForeignKey("empleado.id"))
    nombre               = Column(String(200), nullable=False)
    descripcion          = Column(Text)
    orden                = Column(Integer, nullable=False, default=1)
    estado               = Column(String(20), nullable=False, default="pendiente")
    fecha_inicio_tarea   = Column(Date)   # inicio planificado (Gantt)
    fecha_limite         = Column(Date)   # fin planificado (Gantt)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime)
