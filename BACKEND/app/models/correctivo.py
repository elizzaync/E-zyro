import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Date, DateTime, Text, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ServicioCorrectivo(Base):
    """Trabajo correctivo / garantía asociado a un servicio (Fase 4)."""
    __tablename__ = "servicio_correctivo"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=False)
    codigo      = Column(String(30), nullable=True)
    alcance     = Column(String(500), nullable=True)
    fecha_inicio = Column(Date, nullable=True)
    fecha_fin    = Column(Date, nullable=True)
    estado      = Column(String(20), nullable=False, default="registrado")
    informe_url = Column(Text, nullable=True)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at  = Column(DateTime, nullable=True)


class ServicioObservacion(Base):
    """Observaciones y recomendaciones (descargo) por servicio (Fase 4)."""
    __tablename__ = "servicio_observacion"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    servicio_id       = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=False)
    correctivo_id     = Column(String(36), ForeignKey("servicio_correctivo.id"), nullable=True)
    observaciones     = Column(Text, nullable=True)
    recomendaciones   = Column(Text, nullable=True)
    fecha_descargo    = Column(Date, nullable=False, default=date.today)
    registrado_por_id = Column(String(36), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)
