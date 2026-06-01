import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, Boolean, Date, Text
from sqlalchemy.dialects.postgresql import JSONB
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())


class EquipoIntervenido(Base):
    __tablename__ = "equipo_intervenido"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"),     nullable=False)

    # Contexto del trabajo
    proyecto_id  = Column(String(36), ForeignKey("proyecto.id"),    nullable=True)
    cliente_id   = Column(String(36), ForeignKey("cliente.id"),     nullable=True)

    # Ubicacion en instalacion del cliente
    ubicacion_id     = Column(String(36), ForeignKey("ubicacion.id"), nullable=True)
    zona_id          = Column(String(36), ForeignKey("zona.id"),      nullable=True)
    area_descripcion = Column(String(200), nullable=True)

    # Datos del equipo
    nombre         = Column(String(300), nullable=False)
    codigo         = Column(String(100), nullable=True)
    tipo_equipo_id = Column(String(36), ForeignKey("tipo_equipo.id"), nullable=True)
    marca          = Column(String(150), nullable=True)
    modelo         = Column(String(150), nullable=True)
    numero_serie   = Column(String(150), nullable=True)

    # Estado
    estado            = Column(String(50),  nullable=False, default="operativo")
    fecha_instalacion = Column(Date,        nullable=True)
    ficha_tecnica     = Column(JSONB,       nullable=True)
    observaciones     = Column(Text,        nullable=True)

    activo     = Column(Boolean,  nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True)
