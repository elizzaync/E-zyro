import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Date, ForeignKey
from sqlalchemy.orm import relationship
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class EmpleadoHabilidad(Base):
    __tablename__ = "empleado_habilidad"

    id                 = Column(String(36), primary_key=True, default=generate_uuid)
    empleado_id        = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    habilidad_id       = Column(String(36), ForeignKey("habilidad.id"), nullable=False)
    nivel              = Column(String(20), nullable=False)   # basico|intermedio|avanzado|experto
    certificado_url    = Column(String(500), nullable=True)
    verificado         = Column(Boolean, nullable=False, default=False)
    verificado_por     = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    fecha_verificacion = Column(Date, nullable=True)
    created_at         = Column(String, default=lambda: datetime.utcnow().isoformat())
