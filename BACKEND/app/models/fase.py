import uuid
from sqlalchemy import Column, String, Integer, Date, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Fase(Base):
    __tablename__ = "fase"

    id          = Column(String(36), primary_key=True, default=_uuid)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    nombre      = Column(String(150), nullable=False)
    orden       = Column(Integer, nullable=False)
    estado      = Column(String(20), nullable=False, default="pendiente")  # pendiente|en_proceso|completada|cancelada
    fecha_inicio = Column(Date, nullable=True)
    fecha_fin    = Column(Date, nullable=True)
