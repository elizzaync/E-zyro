import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Text, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Notificacion(Base):
    __tablename__ = "notificacion"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    usuario_id = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    tipo = Column(String(20), nullable=False)
    titulo = Column(String(200), nullable=False)
    mensaje = Column(Text, nullable=False)
    leido = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)