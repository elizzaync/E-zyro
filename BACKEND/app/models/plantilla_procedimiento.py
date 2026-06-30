import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, Boolean, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class PlantillaProcedimiento(Base):
    """Estándar (tipo manual) de procedimientos fijos por **tipo de servicio**
    (`catalogo_servicio`): p.ej. 'Mantenimiento de pozo a tierra', 'UPS', etc.

    `procesos` guarda el JSON estándar con los pasos:
        [{"orden": 1, "nombre": "...", "descripcion": "..."}, ...]

    Al crear un servicio se copian estos pasos a la tabla `procedimiento` del
    servicio. Son los que alimentan el avance, el informe y el certificado.
    Único por (empresa_id, catalogo_servicio_id).

    `tipo_trabajo` queda como columna LEGACY (cache de catalogo.tipo_trabajo,
    auto-rellenada al guardar) — la usa el fallback de `_instanciar_procedimientos`
    para servicios/plantillas que aún no tengan `catalogo_servicio_id` (NOTA:
    columna añadida con SQL manual, ver migrations/2026_06_30_plantilla_catalogo_id.sql;
    create_all NO altera tablas vivas).
    """
    __tablename__ = "plantilla_procedimiento"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    catalogo_servicio_id = Column(UUID(as_uuid=False), ForeignKey("catalogo_servicio.id"), nullable=True)
    tipo_trabajo = Column(String(50), nullable=False)
    nombre       = Column(String(200), nullable=False)
    procesos     = Column(Text, nullable=False, default="[]")  # JSON serializado
    version      = Column(Integer, nullable=False, default=1)
    activo       = Column(Boolean, nullable=False, default=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at   = Column(DateTime)
