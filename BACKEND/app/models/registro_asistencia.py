import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class RegistroAsistencia(Base):
    __tablename__ = "registro_asistencia"

    id                   = Column(String(36), primary_key=True, default=generate_uuid)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id          = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    proyecto_id          = Column(String(36), nullable=True)
    proyecto_servicio_id = Column(String(36), nullable=True)
    tipo                 = Column(String(30), nullable=False)
    fecha_hora           = Column(DateTime, nullable=False)
    estado               = Column(String(20), nullable=False, default='pendiente')
    observacion          = Column(String(500))
    validado_por         = Column(String(36), nullable=True)
    fecha_validacion     = Column(DateTime, nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    # UUID generado en el dispositivo — garantiza idempotencia en reintentos offline
    uuid_cliente         = Column(String(36), nullable=True)

    __table_args__ = (
        UniqueConstraint("empresa_id", "uuid_cliente", name="uq_asistencia_empresa_uuid_cliente"),
    )
