from sqlalchemy import Column, String, Boolean, DateTime
from datetime import datetime
from app.db.database import Base

class Rol(Base):
    __tablename__ = "rol"

    id = Column(String(36), primary_key=True, index=True)
    empresa_id = Column(String(36), nullable=False)
    nombre = Column(String(100), nullable=False)
    descripcion = Column(String(255), nullable=True)
    es_rol_sistema = Column(Boolean, nullable=False, default=False)
    # Manejo de fechas automáticas
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, onupdate=datetime.utcnow, nullable=True)