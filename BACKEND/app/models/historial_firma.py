import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class HistorialFirma(Base):
    __tablename__ = "historial_firma"

    id                   = Column(String(36), primary_key=True, default=generate_uuid)
    usuario_id           = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    url_cloudinary       = Column(Text, nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    reemplazada_en       = Column(DateTime, nullable=False, default=datetime.utcnow)
