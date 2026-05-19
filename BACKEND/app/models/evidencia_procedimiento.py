import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class EvidenciaProcedimiento(Base):
    __tablename__ = "evidencia_procedimiento"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    procedimiento_id     = Column(String(36), ForeignKey("procedimiento.id"),      nullable=False)
    proyecto_servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"),  nullable=False)
    proyecto_id          = Column(String(36), ForeignKey("proyecto.id"),           nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"),            nullable=False)
    subido_por           = Column(String(36), ForeignKey("empleado.id"),           nullable=False)
    url_cloudinary       = Column(String(500), nullable=False)
    public_id_cloudinary = Column(String(255), nullable=False)
    etapa                = Column(String(20))   # 'antes' | 'durante' | 'despues'
    descripcion          = Column(String(500))
    fecha_captura        = Column(DateTime, nullable=False, default=datetime.utcnow)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
