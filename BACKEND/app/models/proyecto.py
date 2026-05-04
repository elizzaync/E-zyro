import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Proyecto(Base):
    __tablename__ = "proyecto"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    cliente_id = Column(String(36), nullable=False)

    # 🔥 Agregado según tu bd.txt
    contrato_comercial_id = Column(String(36))

    orden_trabajo = Column(String(50), nullable=False)
    jefe_operaciones_id = Column(String(36), ForeignKey("empleado.id"), nullable=False)

    nombre_proyecto = Column(String(200), nullable=False)
    estado = Column(String(30), nullable=False, default='Pendiente')

    fecha_inicio = Column(Date)
    fecha_fin_estimada = Column(Date)
    fecha_fin_real = Column(Date)

    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime)