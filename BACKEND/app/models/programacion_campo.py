import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Boolean, Date, DateTime, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class ProgramacionCampo(Base):
    __tablename__ = "programacion_campo"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proyecto_id       = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    tipo              = Column(String(50), nullable=False)
    descripcion       = Column(Text, nullable=True)
    fecha             = Column(Date, nullable=False)
    cantidad_personas = Column(Integer, nullable=True)
    registrado_por    = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    confirmado        = Column(Boolean, nullable=False, default=False)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)


class ProgramacionEmpleado(Base):
    __tablename__ = "programacion_empleado"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    programacion_id      = Column(String(36), ForeignKey("programacion_campo.id"), nullable=False)
    empleado_id          = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    confirmacion_movil   = Column(Boolean, nullable=False, default=False)
    fecha_confirmacion   = Column(DateTime, nullable=True)
