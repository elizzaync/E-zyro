"""
Tipo de cambio diario (SUNAT). Tabla GLOBAL — el TC oficial es nacional, no
por empresa. Lo alimenta un job diario (API) o registro manual.
NOTA: tabla creada con SQL crudo en _run_migrations (PK uuid en prod).
"""
import uuid
from datetime import datetime

from sqlalchemy import Column, Date, DateTime, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class TipoCambio(Base):
    __tablename__ = "tipo_cambio"

    id         = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    fecha      = Column(Date, nullable=False)
    moneda     = Column(String(3), nullable=False, default="USD")
    compra     = Column(Numeric(10, 4), nullable=True)
    venta      = Column(Numeric(10, 4), nullable=False)
    fuente     = Column(String(30), nullable=False, default="SUNAT")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("fecha", "moneda", name="uq_tipo_cambio_fecha_moneda"),
    )
