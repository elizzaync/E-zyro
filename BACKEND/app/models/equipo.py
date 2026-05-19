import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Equipo(Base):
    __tablename__ = "equipo"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_equipo_id   = Column(String(36), ForeignKey("tipo_equipo.id"), nullable=False)
    proyecto_id      = Column(String(36), ForeignKey("proyecto.id"), nullable=True)
    cliente_id       = Column(String(36), ForeignKey("cliente.id"), nullable=True)
    tipo_asignacion  = Column(String(20), nullable=True)   # activo_cliente | proyecto
    nombre           = Column(String(150), nullable=False)
    codigo           = Column(String(50), nullable=True)
    modelo           = Column(String(100), nullable=True)
    marca            = Column(String(100), nullable=True)
    numero_serie     = Column(String(100), nullable=True)
    ubicacion        = Column(String(200), nullable=True)
    estado           = Column(String(20), nullable=False, default="operativo")  # operativo|en_mantenimiento|fuera_de_servicio|baja
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True)
