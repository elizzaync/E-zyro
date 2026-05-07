import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Cliente(Base):
    __tablename__ = "cliente"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    razon_social = Column(String(200), nullable=False)
    ruc = Column(String(20))
    activo = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)