import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Integer, Date, DateTime, Text, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Calibracion(Base):
    """Calibración de un equipo: última/próxima + certificado (Fase 3)."""
    __tablename__ = "calibracion"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    equipo_id           = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    fecha_ultima        = Column(Date, nullable=True)
    fecha_proxima       = Column(Date, nullable=True)
    empresa_responsable = Column(String(200), nullable=True)
    certificado_url     = Column(Text, nullable=True)
    observacion         = Column(String(500), nullable=True)
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at          = Column(DateTime, nullable=True)


class EquipoEstadoMov(Base):
    """Bitácora de cambios de estado operativo de un equipo (inoperativo/reactivar)."""
    __tablename__ = "equipo_estado_mov"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    equipo_id         = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    accion            = Column(String(20), nullable=False)  # inoperativo|reactivar
    cantidad          = Column(Integer, nullable=False, default=1)
    motivo            = Column(String(300), nullable=True)
    fecha             = Column(Date, nullable=False, default=date.today)
    registrado_por_id = Column(String(36), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)
