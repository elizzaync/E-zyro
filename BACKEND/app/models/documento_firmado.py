import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class DocumentoFirmado(Base):
    __tablename__ = "documento_firmado"

    id              = Column(String(36), primary_key=True, default=generate_uuid)
    firma_id        = Column(String(36), ForeignKey("firma_digital.id"), nullable=False)
    empresa_id      = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    documento_id    = Column(String(36), nullable=True)
    tabla_documento = Column(String(100), nullable=False)
    firmado_en      = Column(DateTime, nullable=False, default=datetime.utcnow)
    ip_firma        = Column(String(45), nullable=True)
