import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Date, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class GrupoTrabajo(Base):
    __tablename__ = "grupo_trabajo"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre      = Column(String(150), nullable=False)
    descripcion = Column(String(255), nullable=True)
    jefe_id     = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    activo      = Column(Boolean, nullable=False, default=True)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at  = Column(DateTime, nullable=True)


class GrupoMiembro(Base):
    __tablename__ = "grupo_miembro"

    id               = Column(String(36), primary_key=True, default=_uuid)
    grupo_id         = Column(String(36), ForeignKey("grupo_trabajo.id"), nullable=False)
    empleado_id      = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    fecha_asignacion = Column(Date, nullable=False)
    activo           = Column(Boolean, nullable=False, default=True)
    asignado_por     = Column(String(36), ForeignKey("empleado.id"), nullable=True)
