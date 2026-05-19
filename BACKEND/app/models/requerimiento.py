import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Integer, Text, Date, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Requerimiento(Base):
    __tablename__ = "requerimiento"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    proyecto_id          = Column(String(36), ForeignKey("proyecto.id"),           nullable=False)
    proyecto_servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"))
    procedimiento_id     = Column(String(36), ForeignKey("procedimiento.id"))
    empresa_id           = Column(String(36), ForeignKey("empresa.id"),            nullable=False)
    solicitante_id       = Column(String(36), ForeignKey("empleado.id"),           nullable=False)
    tipo                 = Column(String(30), nullable=False, default="material")
    estado               = Column(String(20), nullable=False, default="pendiente")
    observacion          = Column(String(500))
    observacion_logistico = Column(String(500), nullable=True)  # HU-16
    fecha                = Column(Date, nullable=False, default=date.today)
    aprobado_por         = Column(String(36), ForeignKey("empleado.id"))
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime)


class RequerimientoDetalle(Base):
    __tablename__ = "requerimiento_detalle"

    id                = Column(String(36), primary_key=True, default=_uuid)
    requerimiento_id  = Column(String(36), ForeignKey("requerimiento.id"), nullable=False)
    material_id       = Column(String(36), ForeignKey("material.id"),      nullable=False)
    cantidad          = Column(Integer, nullable=False)
    cantidad_aprobada = Column(Integer)
    observacion       = Column(String(255))
