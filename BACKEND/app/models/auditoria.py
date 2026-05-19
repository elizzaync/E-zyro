from sqlalchemy import Column, String, DateTime
from sqlalchemy.dialects.postgresql import JSONB
from datetime import datetime
from app.db.database import Base

class Auditoria(Base):
    __tablename__ = "auditoria"

    id = Column(String(36), primary_key=True, index=True)
    empresa_id = Column(String(36), nullable=True)
    usuario_id = Column(String(36), nullable=True)
    tabla_afectada = Column(String(100), nullable=False)
    registro_id = Column(String(36), nullable=True)
    accion = Column(String(50), nullable=False)
    modulo = Column(String(100), nullable=True)
    datos_anteriores = Column(JSONB, nullable=True)
    datos_nuevos     = Column(JSONB, nullable=True)
    ip = Column(String(45), nullable=True)
    user_agent = Column(String(500), nullable=True)
    descripcion = Column(String(500), nullable=True)
    # Manejo de fecha automática
    fecha = Column(DateTime, default=datetime.utcnow, nullable=False)