"""
Presupuesto anual por cuenta contable (o grupo PCGE).

Cada línea presupuesta un código PCGE (detalle o prefijo de grupo: '631' o
'63') para un año. La ejecución se calcula en vivo contra el libro mayor —
aquí solo vive el monto presupuestado.
NOTA: tabla creada con SQL crudo en _run_migrations (PK uuid en prod).
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class PresupuestoAnual(Base):
    __tablename__ = "presupuesto_anual"

    id            = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id    = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    anio          = Column(Integer, nullable=False)
    cuenta_codigo = Column(String(20), nullable=False)   # código PCGE (detalle o grupo)
    monto_anual   = Column(Numeric(14, 2), nullable=False, default=0)
    notas         = Column(String(300), nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at    = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "anio", "cuenta_codigo",
                         name="uq_presupuesto_empresa_anio_cuenta"),
    )
