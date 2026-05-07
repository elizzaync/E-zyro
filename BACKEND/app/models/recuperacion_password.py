from sqlalchemy import Column, String, Integer, Boolean, DateTime, ForeignKey
from datetime import datetime
from app.db.database import Base

class RecuperacionPassword(Base):
    __tablename__ = "recuperacion_password"

    id = Column(String(36), primary_key=True, index=True)
    usuario_id = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    codigo_hash = Column(String(255), nullable=False)
    intentos_fallidos = Column(Integer, default=0, nullable=False)
    usado = Column(Boolean, default=False, nullable=False)
    ip_solicitud = Column(String(45), nullable=True)
    fecha_expiracion = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)