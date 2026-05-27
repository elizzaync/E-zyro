import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Integer, Numeric, Text, Date, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class SeguimientoProyecto(Base):
    __tablename__ = "seguimiento_proyecto"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    proyecto_id          = Column(String(36), ForeignKey("proyecto.id"),          nullable=False)
    proyecto_servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=True)  # nota ligada al servicio
    empresa_id           = Column(String(36), ForeignKey("empresa.id"),           nullable=False)
    porcentaje_avance    = Column(Numeric(5, 2), nullable=False)
    descripcion          = Column(Text)
    fecha                = Column(Date,     nullable=False, default=date.today)
    registrado_por       = Column(String(36), ForeignKey("empleado.id"),          nullable=False)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
