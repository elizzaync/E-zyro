import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Date, DateTime, Text, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class InspeccionItse(Base):
    """Inspección ITSE por tablero o por zona (Fase 5). Fotos en recurso_cloudinary."""
    __tablename__ = "inspeccion_itse"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    cliente_id        = Column(String(36), ForeignKey("cliente.id"), nullable=True)   # empresa solicitante
    ubicacion_id      = Column(String(36), ForeignKey("ubicacion.id"), nullable=True)
    zona_id           = Column(String(36), ForeignKey("zona.id"), nullable=True)
    modo              = Column(String(20), nullable=False, default="tablero")  # tablero|zona
    fecha             = Column(Date, nullable=False, default=date.today)
    estado            = Column(String(20), nullable=False, default="borrador")  # borrador|en_proceso|finalizada|anulada
    pdf_url           = Column(Text, nullable=True)
    observaciones     = Column(Text, nullable=True)
    registrado_por_id = Column(String(36), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at        = Column(DateTime, nullable=True)


class InspeccionTablero(Base):
    __tablename__ = "inspeccion_tablero"

    id           = Column(String(36), primary_key=True, default=_uuid)
    inspeccion_id = Column(String(36), ForeignKey("inspeccion_itse.id"), nullable=False)
    nombre       = Column(String(200), nullable=False)
    ambiente     = Column(String(200), nullable=True)
    descripcion  = Column(String(500), nullable=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)


class InspeccionItem(Base):
    """Hallazgo/equipo revisado dentro de una inspección."""
    __tablename__ = "inspeccion_item"

    id           = Column(String(36), primary_key=True, default=_uuid)
    inspeccion_id = Column(String(36), ForeignKey("inspeccion_itse.id"), nullable=False)
    tablero_id   = Column(String(36), ForeignKey("inspeccion_tablero.id"), nullable=True)
    descripcion  = Column(String(500), nullable=False)
    resultado    = Column(String(20), nullable=False, default="conforme")  # conforme|observado|no_conforme
    observacion  = Column(String(500), nullable=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
