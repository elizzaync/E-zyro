from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


class PortalAcceso(Base):
    __tablename__ = "portal_acceso"

    usuario_id = Column(String(36), primary_key=True)
    cliente_id = Column(String(36), nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
