import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class UsuarioCliente(Base):
    __tablename__ = "usuario_cliente"

    id            = Column(String(36), primary_key=True, default=_uuid)
    cliente_id    = Column(String(36), ForeignKey("cliente.id"), nullable=False)
    empresa_id    = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre        = Column(String(100), nullable=False)
    apellido      = Column(String(100), nullable=False)
    email         = Column(String(150), nullable=False)
    password_hash = Column(String(255), nullable=False)
    cargo         = Column(String(100), nullable=True)
    activo        = Column(Boolean, nullable=False, default=True)
    ultimo_acceso = Column(DateTime, nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at    = Column(DateTime, nullable=True)
