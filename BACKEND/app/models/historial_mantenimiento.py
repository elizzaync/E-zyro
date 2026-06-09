import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


class HistorialMantenimiento(Base):
    """Registro inmutable de la asignación de un equipo a un servicio.

    Una nueva fila se crea cada vez que `_vincular_equipos_al_servicio`
    asocia un equipo a un servicio. El estado se congela cuando el equipo
    es re-asignado a otro servicio, preservando el contexto histórico en
    el Portal Cliente aunque `equipo_intervenido.proyecto_servicio_id`
    apunte al servicio más reciente.
    """
    __tablename__ = "historial_mantenimiento"

    id           = Column(UUID(as_uuid=False), primary_key=True,
                          default=lambda: str(uuid.uuid4()))
    empresa_id   = Column(UUID(as_uuid=False), ForeignKey("empresa.id"),
                          nullable=False)
    equipo_id    = Column(UUID(as_uuid=False),
                          ForeignKey("equipo_intervenido.id", ondelete="CASCADE"),
                          nullable=False)
    servicio_id  = Column(UUID(as_uuid=False),
                          ForeignKey("proyecto_servicio.id", ondelete="CASCADE"),
                          nullable=False)
    estado              = Column(String(20), nullable=False, default="pendiente")
    fecha_asignacion    = Column(DateTime, nullable=False, default=datetime.utcnow)
    fecha_ejecucion     = Column(DateTime, nullable=True)
    observaciones       = Column(Text, nullable=True)
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)
