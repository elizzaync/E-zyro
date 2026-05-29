import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Integer, Text, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class RecursoCloudinary(Base):
    """
    Índice de TODO asset subido a Cloudinary. Alimenta la Galería Global y la
    limpieza de huérfanos. Una fila por archivo.

    `entidad_tipo` es texto libre (servicio, equipo, epp, epp_entrega, itse,
    calibracion, correctivo, asistencia, perfil, galeria, ...) — sin CHECK para
    no requerir migración cada vez que un módulo nuevo lo use.
    `recurso_tipo` sí es acotado (imagen|pdf|raw|video).
    """
    __tablename__ = "recurso_cloudinary"

    id            = Column(String(36), primary_key=True, default=_uuid)
    empresa_id    = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    public_id     = Column(String(300), nullable=False)
    secure_url    = Column(Text, nullable=False)
    folder        = Column(String(300), nullable=True)
    recurso_tipo  = Column(String(20), nullable=False, default="imagen")
    entidad_tipo  = Column(String(40), nullable=False)
    entidad_id    = Column(String(36), nullable=True)
    descripcion   = Column(String(300), nullable=True)
    bytes         = Column(Integer, nullable=True)
    formato       = Column(String(10), nullable=True)
    creado_por_id = Column(String(36), nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
