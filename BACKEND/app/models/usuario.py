from sqlalchemy import Column, String, Boolean, DateTime
from datetime import datetime
from app.db.database import Base

class Usuario(Base):
    __tablename__ = "usuario"

    id = Column(String(36), primary_key=True, index=True)
    empresa_id = Column(String(36), nullable=False)
    nombre = Column(String(100), nullable=False)
    apellido = Column(String(100), nullable=False)
    username = Column(String(50), nullable=False)
    email = Column(String(150), nullable=False)
    password_hash = Column(String(255), nullable=False)
    telefono = Column(String(20), nullable=True)
    foto_url = Column(String(500), nullable=True)
    activo = Column(Boolean, default=True)
    email_verificado = Column(Boolean, nullable=False, default=False)
    ultimo_acceso = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, onupdate=datetime.utcnow, nullable=True)