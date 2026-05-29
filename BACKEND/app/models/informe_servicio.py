import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Date, DateTime, Text, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class InformeServicio(Base):
    """
    Pre-informe / informe final de un servicio (refinamiento).
    `tipo='pre'`  → estado actual + procedimientos + evidencias (se puede generar varias veces).
    `tipo='final'`→ se genera al cerrar el servicio (estado 'Completado').
    """
    __tablename__ = "informe_servicio"

    id              = Column(String(36), primary_key=True, default=_uuid)
    empresa_id      = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    servicio_id     = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=False)
    tipo            = Column(String(10), nullable=False, default="pre")  # pre|final
    titulo          = Column(String(200), nullable=True)
    url             = Column(Text, nullable=True)
    public_id       = Column(String(300), nullable=True)
    generado_por_id = Column(String(36), nullable=True)
    fecha           = Column(Date, nullable=False, default=date.today)
    created_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
