import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Text, Boolean, Integer
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class TicketActividad(Base):
    """Historial / timeline de un ticket de soporte TI.

    Cada entrada es un comentario, un avance, una solución (versionada) o un
    evento (tomar el ticket / cambio de estado). Permite que cualquier miembro
    de TI registre progreso y adjuntos, y llevar el control de versiones de las
    soluciones propuestas.

    IDs uuid (mismo criterio que ticket_soporte); sin FK física por los tipos
    uuid de empresa/usuario. La tabla se crea en _pre_create_migrations.

    tipo : comentario | avance | solucion | cambio_estado | tomado
    """
    __tablename__ = "ticket_actividad"

    id              = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id      = Column(UUID(as_uuid=False), nullable=False)
    ticket_id       = Column(UUID(as_uuid=False), nullable=False)
    autor_id        = Column(UUID(as_uuid=False), nullable=False)
    tipo            = Column(String(20), nullable=False, default="comentario")
    texto           = Column(Text, nullable=True)
    adjunto_url     = Column(Text, nullable=True)
    es_solucion     = Column(Boolean, nullable=False, default=False)
    version_solucion = Column(Integer, nullable=True)  # 1,2,3… solo si es solución
    created_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
