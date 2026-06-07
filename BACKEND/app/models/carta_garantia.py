import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Text, DateTime, Date, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from app.db.database import Base


class CartaGarantia(Base):
    __tablename__ = "carta_garantia"

    id              = Column(UUID(as_uuid=False), primary_key=True, default=lambda: str(uuid.uuid4()))
    empresa_id      = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    servicio_id     = Column(UUID(as_uuid=False), ForeignKey("proyecto_servicio.id"), nullable=True)
    equipo_ids      = Column(JSONB, nullable=False, default=list)
    razon_social    = Column(String(300), nullable=True)
    lugar           = Column(String(200), nullable=True)
    direccion       = Column(Text,        nullable=True)
    fecha_operatividad    = Column(Date,     nullable=True)
    vigencia_garantia     = Column(Date,     nullable=True)
    firma_verificador_url = Column(Text,     nullable=True)
    firma_gerente_url     = Column(Text,     nullable=True)
    documento_pdf_url     = Column(Text,     nullable=True)
    created_at            = Column(DateTime, nullable=False, default=datetime.utcnow)
