import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class TableroCircuito(Base):
    """Directorio de circuitos de un tablero eléctrico (equipo_intervenido).
    NOTA: la tabla se crea con SQL crudo en _run_migrations de main.py
    (PK/FK uuid en producción); NO confiar en create_all."""

    __tablename__ = "tablero_circuito"

    id                    = Column(String(36), primary_key=True, default=_uuid)
    empresa_id            = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    equipo_intervenido_id = Column(String(36), ForeignKey("equipo_intervenido.id", ondelete="CASCADE"), nullable=False)
    circuito              = Column(String(200), nullable=False)
    tipo_circuito          = Column(String(10), nullable=False, default="ITM")  # IG|ID|ITM
    capacidad_itm          = Column(String(50), nullable=True)
    descripcion            = Column(String(300), nullable=True)
    orden                  = Column(Integer, nullable=False, default=1)
    created_at             = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at             = Column(DateTime, nullable=True)
