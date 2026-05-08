import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class FirmaDigital(Base):
    __tablename__ = "firma_digital"

    id                   = Column(String(36), primary_key=True, default=generate_uuid)
    empleado_id          = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    url_firma            = Column(String(500), nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime, nullable=True)
