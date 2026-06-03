import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Date, DateTime, Text, ForeignKey
from sqlalchemy.dialects.postgresql import JSONB
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())


class ActivoCliente(Base):
    """Catálogo maestro de activos físicos del cliente (pozos, tableros, UPS, etc.).
    Completamente separado de la tabla 'equipo', que es exclusiva de herramientas internas."""
    __tablename__ = "activo_cliente"

    id             = Column(String(36), primary_key=True, default=_uuid)
    empresa_id     = Column(String(36), ForeignKey("empresa.id"),    nullable=False)
    cliente_id     = Column(String(36), ForeignKey("cliente.id"),    nullable=True)
    tipo_equipo_id = Column(String(36), ForeignKey("tipo_equipo.id"),nullable=True)

    nombre         = Column(String(300), nullable=False)
    codigo         = Column(String(100), nullable=True)
    marca          = Column(String(150), nullable=True)
    modelo         = Column(String(150), nullable=True)
    numero_serie   = Column(String(150), nullable=True)

    ubicacion_id     = Column(String(36), ForeignKey("ubicacion.id"), nullable=True)
    zona_id          = Column(String(36), ForeignKey("zona.id"),      nullable=True)
    area_id          = Column(String(36), ForeignKey("area.id"),      nullable=True)
    area_descripcion = Column(String(200), nullable=True)

    estado            = Column(String(50),  nullable=False, default="operativo")
    fecha_instalacion = Column(Date,        nullable=True)
    ficha_tecnica     = Column(JSONB,       nullable=True)
    observaciones     = Column(Text,        nullable=True)

    activo     = Column(Boolean,  nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True)
