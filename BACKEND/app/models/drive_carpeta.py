import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class DriveCarpeta(Base):
    """Carpeta del Drive de empresa (árbol recursivo). `ambito` separa el espacio
    compartido (todos los de la empresa) del personal (solo el propietario + admin)."""
    __tablename__ = "drive_carpeta"

    id            = Column(String(36), primary_key=True, default=_uuid)
    empresa_id    = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    padre_id      = Column(String(36), ForeignKey("drive_carpeta.id"), nullable=True)
    nombre        = Column(String(150), nullable=False)
    ambito        = Column(String(20), nullable=False, default="compartido")  # compartido | personal
    propietario_id = Column(String(36), ForeignKey("usuario.id"), nullable=True)
    creado_por_id = Column(String(36), ForeignKey("usuario.id"), nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
