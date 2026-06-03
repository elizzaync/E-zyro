import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class TicketSoporte(Base):
    """
    Ticket de soporte interno para el equipo de TI.

    Cualquier colaborador reporta una problemática (error de la app, del sistema
    web, acceso, datos incorrectos, etc.). El equipo de TI (admin) los gestiona
    y cambia su estado.

    NOTA: los IDs son `uuid` (mismo criterio que ticket_compra). NO declaramos
    ForeignKey física porque empresa(id)/usuario(id) son uuid y declarar la FK
    con String(36) hace que create_all falle por tipos incompatibles. La
    integridad referencial se maneja a nivel de aplicación.

    categoria : app_movil | sistema_web | acceso | datos | otro
    prioridad : baja | media | alta | urgente
    estado    : abierto | en_proceso | resuelto | cerrado
    """
    __tablename__ = "ticket_soporte"

    id              = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id      = Column(UUID(as_uuid=False), nullable=False)
    codigo          = Column(String(20), nullable=False)            # TI-0001
    reportado_por   = Column(UUID(as_uuid=False), nullable=False)
    titulo          = Column(String(200), nullable=False)
    descripcion     = Column(Text, nullable=False)
    categoria       = Column(String(30), nullable=False, default="otro")
    prioridad       = Column(String(20), nullable=False, default="media")
    estado          = Column(String(20), nullable=False, default="abierto")
    # Datos de contexto del dispositivo (útiles para diagnóstico de TI)
    pantalla        = Column(String(120), nullable=True)
    dispositivo     = Column(String(200), nullable=True)
    adjunto_url     = Column(Text, nullable=True)
    # Gestión por TI
    respuesta_ti    = Column(Text, nullable=True)
    atendido_por    = Column(UUID(as_uuid=False), nullable=True)
    created_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at      = Column(DateTime, nullable=True)
