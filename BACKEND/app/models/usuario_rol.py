from sqlalchemy import Column, String, DateTime
from datetime import datetime
from app.db.database import Base

class UsuarioRol(Base):
    __tablename__ = "usuario_rol"

    id = Column(String(36), primary_key=True, index=True)
    usuario_id = Column(String(36), nullable=False)
    rol_id = Column(String(36), nullable=False)
    empresa_id = Column(String(36), nullable=False)
    asignado_por = Column(String(36), nullable=True)
    # Manejo de fecha automática
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)