import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, Date, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from app.db.database import Base


class HistorialInspeccion(Base):
    """Una sesión completa de mantenimiento/inspección sobre un activo.

    - `resultado` JSONB: [{orden, nombre, completado, foto_url, foto_public_id}]
      — se actualiza en vivo durante la sesión activa.
    - Cuando se finaliza se congela el registro y se crea uno nuevo la próxima vez.
    - Regla Cloudinary: dentro de la MISMA sesión activa, cambiar foto reemplaza
      el recurso anterior (mismo public_id). En nueva sesión se genera nuevo public_id.
    """
    __tablename__ = "historial_inspeccion"

    id                          = Column(UUID(as_uuid=False), primary_key=True,
                                         default=lambda: str(uuid.uuid4()))
    equipo_intervenido_id       = Column(UUID(as_uuid=False),
                                         ForeignKey("equipo_intervenido.id"), nullable=False)
    proyecto_servicio_id        = Column(UUID(as_uuid=False),
                                         ForeignKey("proyecto_servicio.id"), nullable=True)
    empresa_id                  = Column(UUID(as_uuid=False),
                                         ForeignKey("empresa.id"), nullable=False)
    estado                      = Column(String(20), nullable=False, default="en_proceso")
    resultado                   = Column(JSONB, nullable=True)
    observaciones               = Column(Text, nullable=True)
    proxima_fecha_mantenimiento = Column(Date, nullable=True)
    fecha_inicio                = Column(DateTime, nullable=False, default=datetime.utcnow)
    fecha_fin                   = Column(DateTime, nullable=True)
    created_at                  = Column(DateTime, nullable=False, default=datetime.utcnow)
