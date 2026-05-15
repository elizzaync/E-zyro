import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Date, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Plano(Base):
    __tablename__ = "plano"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
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
    subido_por           = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    fecha                = Column(Date, nullable=False)
    es_version_activa    = Column(Boolean, nullable=False, default=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
