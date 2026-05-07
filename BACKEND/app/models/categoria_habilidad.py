import uuid
from sqlalchemy import Column, String
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class CategoriaHabilidad(Base):
    __tablename__ = "categoria_habilidad"

    id          = Column(String(36), primary_key=True, default=generate_uuid)
    nombre      = Column(String(100), nullable=False)
    descripcion = Column(String(255), nullable=True)
