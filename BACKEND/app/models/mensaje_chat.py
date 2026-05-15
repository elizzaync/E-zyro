import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class MensajeChat(Base):
    __tablename__ = "mensaje_chat"

    id           = Column(String(36), primary_key=True, default=_uuid)
    proyecto_id  = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    remitente_id = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    padre_id     = Column(String(36), ForeignKey("mensaje_chat.id"), nullable=True)
    contenido    = Column(Text, nullable=False)
    fecha        = Column(DateTime, nullable=False)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)


class AdjuntoMensaje(Base):
    __tablename__ = "adjunto_mensaje"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    mensaje_id           = Column(String(36), ForeignKey("mensaje_chat.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    url_cloudinary       = Column(String(500), nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    tipo_archivo         = Column(String(50), nullable=True)
    nombre_archivo       = Column(String(200), nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)


class LecturaMensaje(Base):
    __tablename__ = "lectura_mensaje"

    mensaje_id = Column(String(36), ForeignKey("mensaje_chat.id"), primary_key=True)
    usuario_id = Column(String(36), ForeignKey("usuario.id"), primary_key=True)
    leido_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
