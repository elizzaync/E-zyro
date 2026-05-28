import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class RequerimientoEntrega(Base):
    __tablename__ = "requerimiento_entrega"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    requerimiento_id    = Column(String(36), ForeignKey("requerimiento.id"), nullable=False)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    entregado_por_id    = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    recibido_por_id     = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    firma_receptor_url  = Column(String(500), nullable=True)
    firma_public_id     = Column(String(255), nullable=True)
    firma_entregador_url = Column(String(500), nullable=True)
    fecha_entrega       = Column(DateTime, nullable=False)
    notas               = Column(Text, nullable=True)
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)
