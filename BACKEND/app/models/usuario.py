from sqlalchemy import Column, String, Boolean
from app.db.database import Base # Asegúrate de tener este archivo como lo vimos antes

class Usuario(Base):
    __tablename__ = "usuario"

    id = Column(String(36), primary_key=True, index=True)
    empresa_id = Column(String(36), nullable=False)
    nombre = Column(String(100), nullable=False)
    apellido = Column(String(100), nullable=False)
    email = Column(String(150), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    activo = Column(Boolean, default=True)
    # No es necesario mapear el 100% de las columnas de la tabla para el login, solo las útiles.