import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, BigInteger, Date, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Plano(Base):
    __tablename__ = "plano"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    # Híbrido: proyecto_id opcional (planos globales tipo Drive o ligados a proyecto)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=True)
    carpeta_id  = Column(String(36), ForeignKey("carpeta_documental.id"), nullable=True)
    nombre      = Column(String(200), nullable=False)
    disciplina  = Column(String(50), nullable=True)
    descripcion = Column(String(255), nullable=True)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)


class VersionPlano(Base):
    __tablename__ = "version_plano"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    plano_id             = Column(String(36), ForeignKey("plano.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    version              = Column(String(20), nullable=False)
    url_cloudinary       = Column(String(500), nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    # FK real en BD apunta a usuario.id (no empleado). Guardamos el usuario_id.
    subido_por           = Column(String(36), ForeignKey("usuario.id"), nullable=True)
    fecha                = Column(Date, nullable=False)
    es_version_activa    = Column(Boolean, nullable=False, default=True)
    formato              = Column(String(20), nullable=True)
    bytes                = Column(BigInteger, nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
