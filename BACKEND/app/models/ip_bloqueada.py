import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Text
from app.db.database import Base

class IpBloqueada(Base):
    __tablename__ = "ip_bloqueada"
    id              = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    empresa_id      = Column(String(36), nullable=False, index=True)
    ip              = Column(String(45), nullable=False)
    motivo          = Column(Text, nullable=True)
    bloqueada_por   = Column(String(36), nullable=True)   # usuario_id
    activa          = Column(Boolean, default=True, nullable=False)
    created_at      = Column(DateTime, default=datetime.utcnow, nullable=False)
    desbloqueada_en = Column(DateTime, nullable=True)
