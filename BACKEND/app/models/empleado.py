import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Empleado(Base):
    __tablename__ = "empleado"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    usuario_id = Column(String(36), ForeignKey("usuario.id"), nullable=False, unique=True)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    cargo = Column(String(100), nullable=False)
    tipo = Column(String(20), nullable=False)
    fecha_ingreso = Column(Date, nullable=False)