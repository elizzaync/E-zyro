import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Boolean, Date, Time, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Turno(Base):
    __tablename__ = "turno"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre              = Column(String(100), nullable=False)
    hora_entrada        = Column(Time, nullable=False)
    hora_salida         = Column(Time, nullable=False)
    tolerancia_minutos  = Column(Integer, nullable=True, default=5)
    activo              = Column(Boolean, nullable=False, default=True)


class TurnoEmpleado(Base):
    __tablename__ = "turno_empleado"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empleado_id  = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    turno_id     = Column(String(36), ForeignKey("turno.id"), nullable=False)
    fecha_desde  = Column(Date, nullable=False)
    fecha_hasta  = Column(Date, nullable=True)
    activo       = Column(Boolean, nullable=False, default=True)
