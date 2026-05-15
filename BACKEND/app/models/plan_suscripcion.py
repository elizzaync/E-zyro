import uuid
from sqlalchemy import Column, String, Integer, Numeric, Boolean, Text
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class PlanSuscripcion(Base):
    __tablename__ = "plan_suscripcion"

    id              = Column(String(36), primary_key=True, default=_uuid)
    nombre          = Column(String(100), nullable=False)
    max_usuarios    = Column(Integer, nullable=False)
    max_proyectos   = Column(Integer, nullable=True)
    precio_mensual  = Column(Numeric(10, 2), nullable=False)
    descripcion     = Column(Text, nullable=True)
    activo          = Column(Boolean, nullable=False, default=True)
