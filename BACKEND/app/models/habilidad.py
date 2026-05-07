import uuid
from sqlalchemy import Column, String, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Habilidad(Base):
    __tablename__ = "habilidad"

    id           = Column(String(36), primary_key=True, default=generate_uuid)
    categoria_id = Column(String(36), ForeignKey("categoria_habilidad.id"), nullable=False)
    nombre       = Column(String(150), nullable=False)
    descripcion  = Column(String(255), nullable=True)
