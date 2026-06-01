from __future__ import annotations
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, ForeignKey, DateTime
from sqlalchemy.dialects.postgresql import UUID
from ..db.database import Base


class Incidencia(Base):
    __tablename__ = "incidencia"

    id                   = Column(UUID(as_uuid=False), primary_key=True)
    empresa_id           = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    equipo_id            = Column(UUID(as_uuid=False), ForeignKey("equipo.id"), nullable=False)
    proyecto_servicio_id = Column(UUID(as_uuid=False), ForeignKey("proyecto_servicio.id"), nullable=True)
    reportado_por_id     = Column(UUID(as_uuid=False), ForeignKey("empleado.id"), nullable=True)
    resuelto_por_id      = Column(UUID(as_uuid=False), ForeignKey("empleado.id"), nullable=True)

    numero_serie         = Column(String, nullable=True)
    cantidad_afectada    = Column(Integer, nullable=False, default=1)

    tipo_falla           = Column(String, nullable=False, default="otro")
    descripcion          = Column(Text, nullable=False)

    estado               = Column(String, nullable=False, default="abierta")
    resolucion_nota      = Column(Text, nullable=True)

    fecha_reporte        = Column(DateTime, nullable=False, default=datetime.utcnow)
    fecha_resolucion     = Column(DateTime, nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime, nullable=True)
