import uuid
from datetime import datetime
from sqlalchemy import Column, String, Date, DateTime, Numeric, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class ContratoComercial(Base):
    __tablename__ = "contrato_comercial"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    cliente_id           = Column(String(36), ForeignKey("cliente.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    numero_contrato      = Column(String(100), nullable=False)
    fecha_inicio         = Column(Date, nullable=False)
    fecha_fin            = Column(Date, nullable=True)
    monto_total          = Column(Numeric(12, 2), nullable=True)
    estado               = Column(String(20), nullable=False, default="vigente")  # borrador|vigente|vencido|rescindido
    descripcion          = Column(Text, nullable=True)
    documento_url        = Column(String(500), nullable=True)
    public_id_cloudinary = Column(String(255), nullable=True)
    creado_por           = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime, nullable=True)
