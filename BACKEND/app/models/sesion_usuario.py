import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class SesionUsuario(Base):
    __tablename__ = "sesion_usuario"

    id               = Column(String(36), primary_key=True, default=generate_uuid)
    usuario_id       = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    token_hash       = Column(String(255), nullable=False)
    dispositivo      = Column(String(100))
    ip               = Column(String(45))
    user_agent       = Column(String(255))
    activa           = Column(Boolean, nullable=False, default=True)
    fecha_expiracion = Column(DateTime, nullable=False)
    fecha_cierre     = Column(DateTime, nullable=True)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
