import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, UniqueConstraint, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class FeriadoEmpresa(Base):
    __tablename__ = "feriado_empresa"

    id         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    fecha      = Column(Date, nullable=False)
    nombre     = Column(String(200), nullable=False)
    tipo       = Column(String(20),  nullable=False, default="empresa")
    created_by = Column(String(36),  nullable=True)
    created_at = Column(DateTime,    nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "fecha", name="uq_feriado_empresa_fecha"),
    )
