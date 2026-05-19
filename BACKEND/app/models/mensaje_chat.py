import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class MensajeChat(Base):
    __tablename__ = "mensaje_chat"

    id              = Column(String(36), primary_key=True, default=_uuid)
    # servicio_id aísla el chat por servicio específico (proyecto_servicio.id).
    # Migración requerida: ALTER TABLE mensaje_chat ADD COLUMN servicio_id VARCHAR(36)
    #                      REFERENCES proyecto_servicio(id);
    #                      CREATE INDEX ix_mensaje_chat_servicio_id ON mensaje_chat(servicio_id);
    servicio_id     = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=True,  index=True)
    proyecto_id     = Column(String(36), ForeignKey("proyecto.id"),          nullable=False)
    empresa_id      = Column(String(36), ForeignKey("empresa.id"),           nullable=False)
    remitente_id    = Column(String(36), ForeignKey("usuario.id"),           nullable=False)
    destinatario_id = Column(PGUUID(as_uuid=True), ForeignKey("usuario.id"), nullable=True)
    padre_id        = Column(String(36), ForeignKey("mensaje_chat.id"),      nullable=True)
    contenido       = Column(Text,       nullable=False)
    fecha           = Column(DateTime,   nullable=False)
    created_at      = Column(DateTime,   nullable=False, default=datetime.utcnow)


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
