"""
Alertas del monitoreo de seguridad (módulo Gestión de TIC).

Las genera el job `_monitoreo_seguridad` (cada 5 min) evaluando reglas sobre
audit_log: fuerza bruta por IP, logins fallidos por usuario, permisos denegados
repetidos y descargas masivas. Notifican al rol Soporte (igual que backups).

Sin FK a usuario: rastro de auditoría que sobrevive a borrados.
"""
import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, Index, String
from sqlalchemy.dialects.postgresql import JSONB

from app.db.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


class AlertaSeguridad(Base):
    __tablename__ = "alerta_seguridad"

    id             = Column(String(36), primary_key=True, default=_uuid)
    # fuerza_bruta | denegados_repetidos | descarga_masiva | logins_fallidos_usuario
    tipo           = Column(String(30), nullable=True)
    severidad      = Column(String(10), nullable=True)   # baja|media|alta
    titulo         = Column(String(200), nullable=True)
    detalle        = Column(JSONB, nullable=True)
    ip             = Column(String(45), nullable=True)
    usuario_id     = Column(String(36), nullable=True)
    fecha          = Column(DateTime, nullable=True, default=datetime.utcnow)
    estado         = Column(String(10), nullable=True, default="abierta")  # abierta|revisada
    revisada_por   = Column(String(36), nullable=True)
    fecha_revision = Column(DateTime, nullable=True)

    __table_args__ = (
        Index("idx_alerta_seguridad_estado_fecha", estado, fecha.desc()),
        Index("idx_alerta_seguridad_tipo_fecha", tipo, fecha.desc()),
    )
