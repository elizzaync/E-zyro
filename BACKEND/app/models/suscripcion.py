import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Suscripcion(Base):
    __tablename__ = "suscripcion"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    plan_id      = Column(String(36), ForeignKey("plan_suscripcion.id"), nullable=False)
    fecha_inicio = Column(Date, nullable=False)
    fecha_fin    = Column(Date, nullable=True)
    estado       = Column(String(20), nullable=False, default="activa")  # activa|vencida|cancelada|suspendida
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
