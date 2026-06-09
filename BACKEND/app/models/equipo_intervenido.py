import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Text, DateTime, Date, Boolean, Integer, ForeignKey
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
    ubicacion_referencia = Column(String(200),                                              nullable=True)
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
    # Plan de mantenimiento (cada N meses)
    ultimo_mantenimiento  = Column(Date,         nullable=True)
    proximo_mantenimiento = Column(Date,         nullable=True)
    frecuencia_meses      = Column(Integer,      nullable=True, default=6)
    created_at           = Column(DateTime,      nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime,      nullable=True)


class EquipoIntervenidoMantenimiento(Base):
    """Historial de mantenimientos realizados sobre un equipo intervenido.

    Una fila por mantenimiento ejecutado. Al registrar uno se actualiza el
    snapshot del equipo (ultimo_mantenimiento / proximo_mantenimiento).
    NOTA: la tabla se crea con SQL crudo en _run_migrations de main.py
    (PK/FK uuid en produccion); NO confiar en create_all.
    """

    __tablename__ = "equipo_intervenido_mantenimiento"

    id                    = Column(UUID(as_uuid=False), primary_key=True, default=lambda: str(uuid.uuid4()))
    empresa_id            = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    equipo_intervenido_id = Column(UUID(as_uuid=False),
                                   ForeignKey("equipo_intervenido.id", ondelete="CASCADE"),
                                   nullable=False)
    fecha                 = Column(Date,        nullable=False, default=date.today)
    tipo                  = Column(String(20),  nullable=False, default="preventivo")  # preventivo|correctivo|inspeccion|otro
    descripcion           = Column(Text,        nullable=True)
    realizado_por         = Column(String(200), nullable=True)
    proximo_calculado     = Column(Date,        nullable=True)   # proximo mantenimiento que quedo programado
    registrado_por_id     = Column(UUID(as_uuid=False), nullable=True)
    created_at            = Column(DateTime,    nullable=False, default=datetime.utcnow)
