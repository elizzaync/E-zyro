import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from app.db.database import Base


class ComunicadoProyecto(Base):
    __tablename__ = "comunicado_proyecto"

    id                   = Column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    empresa_id           = Column(PGUUID(as_uuid=True), ForeignKey("empresa.id"), nullable=False)
    proyecto_id          = Column(PGUUID(as_uuid=True), ForeignKey("proyecto.id"), nullable=False)
    autor_id             = Column(PGUUID(as_uuid=True), ForeignKey("empleado.id"), nullable=True)
    titulo               = Column(String(200), nullable=False)
    mensaje              = Column(Text, nullable=False)
    adjunto_url          = Column(String(500), nullable=True)
    adjunto_public_id    = Column(String(255), nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)


class ComunicadoLeido(Base):
    __tablename__ = "comunicado_leido"

    comunicado_id = Column(PGUUID(as_uuid=True), ForeignKey("comunicado_proyecto.id"), primary_key=True)
    empleado_id   = Column(PGUUID(as_uuid=True), ForeignKey("empleado.id"), primary_key=True)
    leido_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
