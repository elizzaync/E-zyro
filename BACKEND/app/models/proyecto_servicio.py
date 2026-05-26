import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, Integer, Text, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class ProyectoServicio(Base):
    __tablename__ = "proyecto_servicio"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    catalogo_servicio_id = Column(String(36), ForeignKey("catalogo_servicio.id"), nullable=False)
    fase_id = Column(String(36), ForeignKey("fase.id"), nullable=True)
    nombre = Column(String(200), nullable=False)
    descripcion = Column(Text)

    # Liderazgo del servicio
    lider_id = Column(String(36), ForeignKey("empleado.id"))        # Líder (jefe) — obligatorio en la app
    responsable_id = Column(String(36), ForeignKey("empleado.id"))  # Técnico líder (opcional) — legacy id_usuario

    orden = Column(Integer, nullable=False, default=1)
    estado = Column(String(30), nullable=False, default='Pendiente')
    fecha_programada = Column(Date)
    fecha_inicio = Column(Date)
    fecha_fin = Column(Date)

    # Alcance, zona y facturación heredados del legacy (por servicio)
    zona_ejecucion = Column(String(255))
    alcance = Column(Text)
    tipo_documento_cliente = Column(String(20))   # 'OC' | 'PROF' | 'SIN_OC'
    nro_documento = Column(String(100))
    nro_conformidad = Column(String(100), default='En Espera')
    acta_url = Column(String(500))
    public_id_cloudinary = Column(String(255))

    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime)
