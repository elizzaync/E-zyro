import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Text, DateTime, Date, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from app.db.database import Base


class EquipoIntervenido(Base):
    """Activo instalado en cliente. Puede vincularse a un servicio activo
    a través de proyecto_servicio_id y rastrear su estado de intervención."""

    __tablename__ = "equipo_intervenido"

    id                   = Column(UUID(as_uuid=False), primary_key=True, default=lambda: str(uuid.uuid4()))
    empresa_id           = Column(UUID(as_uuid=False), ForeignKey("empresa.id"),            nullable=False)
    proyecto_id          = Column(UUID(as_uuid=False), ForeignKey("proyecto.id"),           nullable=True)
    cliente_id           = Column(UUID(as_uuid=False), ForeignKey("cliente.id"),            nullable=True)
    ubicacion_id         = Column(UUID(as_uuid=False),                                      nullable=True)
    zona_id              = Column(UUID(as_uuid=False),                                      nullable=True)
    area_id              = Column(UUID(as_uuid=False),                                      nullable=True)
    area_descripcion     = Column(String(200),                                              nullable=True)
    nombre               = Column(String(200),                                              nullable=False)
    codigo               = Column(String(50),                                               nullable=True)
    tipo_equipo_id       = Column(UUID(as_uuid=False), ForeignKey("tipo_equipo.id"),        nullable=True)
    marca                = Column(String(100),                                              nullable=True)
    modelo               = Column(String(100),                                              nullable=True)
    numero_serie         = Column(String(100),                                              nullable=True)
    estado               = Column(String(20),  nullable=False, default="operativo")
    fecha_instalacion    = Column(Date,         nullable=True)
    ficha_tecnica        = Column(JSONB,         nullable=True)
    observaciones        = Column(Text,          nullable=True)
    activo               = Column(Boolean,       nullable=False, default=True)
    # Campos de intervención en servicio
    equipo_id            = Column(UUID(as_uuid=False), ForeignKey("equipo.id"),             nullable=True)
    proyecto_servicio_id = Column(UUID(as_uuid=False), ForeignKey("proyecto_servicio.id"), nullable=True)
    estado_intervencion  = Column(String(20),   nullable=False, default="pendiente")
    activo_cliente_id    = Column(UUID(as_uuid=False),                                     nullable=True)
    fecha_fin            = Column(Date,          nullable=True)
    created_at           = Column(DateTime,      nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime,      nullable=True)
