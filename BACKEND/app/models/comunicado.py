import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ComunicadoProyecto(Base):
    __tablename__ = "comunicado_proyecto"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proyecto_id          = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    autor_id             = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    titulo               = Column(String(200), nullable=False)
    mensaje              = Column(Text, nullable=False)
    adjunto_url          = Column(String(500), nullable=True)
    adjunto_public_id    = Column(String(255), nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)


class ComunicadoLeido(Base):
    __tablename__ = "comunicado_leido"

    comunicado_id = Column(String(36), ForeignKey("comunicado_proyecto.id"), primary_key=True)
    empleado_id   = Column(String(36), ForeignKey("empleado.id"), primary_key=True)
    leido_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
