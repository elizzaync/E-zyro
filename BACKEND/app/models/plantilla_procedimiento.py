import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, Boolean, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class PlantillaProcedimiento(Base):
    """Estándar (tipo manual) de procedimientos fijos por **tipo de trabajo**
    (catalogo_servicio.tipo_trabajo): p.ej. 'pozo', 'ups', etc.

    `procesos` guarda el JSON estándar con los pasos:
        [{"orden": 1, "nombre": "...", "descripcion": "..."}, ...]

    Al crear un servicio se copian estos pasos a la tabla `procedimiento` del
    servicio. Son los que alimentan el avance, el informe y el certificado.
    Único por (empresa_id, tipo_trabajo).
    """
    __tablename__ = "plantilla_procedimiento"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_trabajo = Column(String(50), nullable=False)
    nombre       = Column(String(200), nullable=False)
    procesos     = Column(Text, nullable=False, default="[]")  # JSON serializado
    version      = Column(Integer, nullable=False, default=1)
    activo       = Column(Boolean, nullable=False, default=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at   = Column(DateTime)
