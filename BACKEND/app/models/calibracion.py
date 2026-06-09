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


class CalibracionEvento(Base):
    """Historial de calibraciones de un equipo: una fila por calibración realizada.

    A diferencia de `Calibracion` (snapshot 'última conocida', 1 fila por equipo),
    aquí se acumula cada evento con su PDF y metadatos (quién la hizo, nº de
    certificado, resultado). Al registrar un evento se recalcula el snapshot.
    """
    __tablename__ = "calibracion_evento"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    equipo_id           = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    fecha_realizada     = Column(Date, nullable=False)
    periodicidad_meses  = Column(Integer, nullable=True)         # cada cuánto toca (3/6/12…)
    fecha_proxima       = Column(Date, nullable=True)            # = fecha_realizada + periodicidad
    realizada_por       = Column(String(200), nullable=True)    # técnico/laboratorio que la hizo
    empresa_responsable = Column(String(200), nullable=True)    # laboratorio acreditado
    numero_certificado  = Column(String(120), nullable=True)
    resultado           = Column(String(20), nullable=True)     # conforme|observado
    certificado_url     = Column(Text, nullable=True)           # PDF/imagen adjunto
    observacion         = Column(String(500), nullable=True)
    registrado_por_id   = Column(String(36), nullable=True)
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)


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
