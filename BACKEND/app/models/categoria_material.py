import uuid
from sqlalchemy import Column, String, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class CategoriaMaterial(Base):
    __tablename__ = "categoria_material"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre      = Column(String(100), nullable=False)
    descripcion = Column(String(255), nullable=True)
