import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Area(Base):
    """Área (catálogo) con doble uso:

    - Área física dentro de una zona (jerarquía `ubicacion → zona → area`):
      `zona_id`/`ubicacion_id` poblados. Es donde "vive" un equipo intervenido.
    - Área de RR.HH. de la empresa (uso histórico, reemplaza `empleado.area`):
      `zona_id`/`ubicacion_id` en NULL.
    """
    __tablename__ = "area"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    # Jerarquía física (NULL = área RR.HH.). `ubicacion_id` es denormalización
    # de conveniencia para filtrar/dibujar el árbol sin re-resolver la zona.
    ubicacion_id = Column(String(36), ForeignKey("ubicacion.id"), nullable=True)
    zona_id      = Column(String(36), ForeignKey("zona.id"),      nullable=True)
    nombre       = Column(String(150), nullable=False)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
