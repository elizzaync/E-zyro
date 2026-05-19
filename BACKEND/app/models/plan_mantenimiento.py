import uuid
from sqlalchemy import Column, String, Integer, Boolean, Date, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class PlanMantenimiento(Base):
    __tablename__ = "plan_mantenimiento"

    id               = Column(String(36), primary_key=True, default=_uuid)
    equipo_id        = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo             = Column(String(20), nullable=False)   # preventivo|correctivo|predictivo
    frecuencia       = Column(String(30), nullable=True)
    frecuencia_dias  = Column(Integer, nullable=True)
    proxima_fecha    = Column(Date, nullable=True)
    activo           = Column(Boolean, nullable=False, default=True)
