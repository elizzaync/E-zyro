import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, Boolean, ForeignKey, UniqueConstraint
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class ProyectoMiembro(Base):
    __tablename__ = "proyecto_miembro"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    empleado_id = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    rol_proyecto = Column(String(50))
    fecha_asignacion = Column(Date, nullable=False, default=datetime.utcnow().date)
    activo = Column(Boolean, nullable=False, default=True)
    __table_args__ = (
        UniqueConstraint('proyecto_id', 'empleado_id', name='uq_proyecto_empleado'),
    )