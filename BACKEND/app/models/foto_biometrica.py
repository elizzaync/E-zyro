import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

class FotoBiometrica(Base):    
    __tablename__ = "foto_biometrica"

    id                   = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    usuario_id           = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    url_cloudinary       = Column(String(500), nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    activa               = Column(Boolean, nullable=False, default=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
  
