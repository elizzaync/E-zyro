import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Integer, Date, DateTime, ForeignKey
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Empleado(Base):
    __tablename__ = "empleado"

    id                     = Column(String(36), primary_key=True, default=generate_uuid)
    usuario_id             = Column(String(36), ForeignKey("usuario.id"), nullable=False, unique=True)
    empresa_id             = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    codigo                 = Column(String(50), nullable=True)
    cargo                  = Column(String(100), nullable=False)
    area                   = Column(String(100), nullable=True)
    tipo                   = Column(String(20), nullable=False)
    fecha_ingreso          = Column(Date, nullable=False)
    fecha_fin_contrato     = Column(Date, nullable=True)
    dias_aviso_vencimiento = Column(Integer, nullable=True, default=7)
    activo                 = Column(Boolean, nullable=False, default=True)
    created_at             = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at             = Column(DateTime, nullable=True)
