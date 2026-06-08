"""
Bus de eventos contables (Fase 10) — capa de integración configurable.

Centraliza el conocimiento "transacción operativa → asiento contable" en una
tabla editable desde el aplicativo, en vez de dispersarlo por el código. Es una
función SÍNCRONA y transaccional (no mensajería): el hecho económico y su
asiento ocurren o fallan juntos.

  - mapeo_transaccion_contable : regla por (empresa, tipo_evento) con la
        plantilla de líneas en JSON (plantilla_lineas, guardada como Text
        siguiendo el patrón del repo).
  - evento_contable_historial  : trazabilidad origen→evento→asiento.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Boolean, DateTime, Text, ForeignKey, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class MapeoTransaccionContable(Base):
    __tablename__ = "mapeo_transaccion_contable"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_evento      = Column(String(50), nullable=False)
    descripcion      = Column(String(255), nullable=True)
    # JSON: [{"cuenta_codigo": "601", "tipo": "debito", "origen_monto": "subtotal"}, ...]
    plantilla_lineas = Column(Text, nullable=False, default="[]")
    activo           = Column(Boolean, nullable=False, default=True)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "tipo_evento", name="uq_mapeo_empresa_evento"),
    )


class EventoContableHistorial(Base):
    __tablename__ = "evento_contable_historial"

    id            = Column(String(36), primary_key=True, default=_uuid)
    empresa_id    = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_evento   = Column(String(50), nullable=False)
    referencia_id = Column(String(36), nullable=True)
    asiento_id    = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    resultado     = Column(String(20), nullable=False, default="generado")  # generado|sin_mapeo|error
    detalle       = Column(Text, nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
