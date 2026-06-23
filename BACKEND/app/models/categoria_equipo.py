import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class CategoriaEquipo(Base):
    """Catálogo de categorías para equipos, herramientas y activos tecnológicos.
    Separa la clasificación general de inventario del concepto de TipoEquipo
    (que es específico del módulo de Equipos Intervenidos con procedimientos técnicos)."""
    __tablename__ = "categoria_equipo"

    id         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre     = Column(String(100), nullable=False)
    # equipo | herramienta | equipo_tecnologico — orientativo, no restrictivo
    clase      = Column(String(30), nullable=True)
    activo     = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
