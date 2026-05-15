import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, Date, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class OrdenMantenimiento(Base):
    __tablename__ = "orden_mantenimiento"

    id          = Column(String(36), primary_key=True, default=generate_uuid)
    equipo_id   = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tecnico_id  = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    plan_id     = Column(String(36), ForeignKey("plan_mantenimiento.id"), nullable=True)
    tipo        = Column(String(20), nullable=False)   # preventivo|correctivo|predictivo
    estado      = Column(String(20), nullable=False, default="pendiente")  # pendiente|en_proceso|completado|cancelado
    fecha       = Column(Date, nullable=False)
    fecha_inicio = Column(DateTime, nullable=True)
    fecha_fin    = Column(DateTime, nullable=True)
    observaciones = Column(Text, nullable=True)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at  = Column(DateTime, nullable=True)
