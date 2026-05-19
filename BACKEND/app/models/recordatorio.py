import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Boolean, Numeric, Date, DateTime, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Recordatorio(Base):
    __tablename__ = "recordatorio"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    creado_por          = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    titulo              = Column(String(200), nullable=False)
    descripcion         = Column(Text, nullable=True)
    categoria           = Column(String(50), nullable=True)
    monto_referencial   = Column(Numeric(10, 2), nullable=True)
    fecha_vencimiento   = Column(Date, nullable=False)
    recurrente          = Column(Boolean, nullable=False, default=False)
    frecuencia_dias     = Column(Integer, nullable=True)
    dias_aviso          = Column(Integer, nullable=False, default=3)
    estado              = Column(String(20), nullable=False, default="activo")  # activo|vencido|completado|cancelado
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at          = Column(DateTime, nullable=True)


class RecordatorioDestinatario(Base):
    __tablename__ = "recordatorio_destinatario"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    recordatorio_id      = Column(String(36), ForeignKey("recordatorio.id"), nullable=False)
    usuario_id           = Column(String(36), ForeignKey("usuario.id"), nullable=False)
    notificado_push      = Column(Boolean, nullable=False, default=False)
    notificado_email     = Column(Boolean, nullable=False, default=False)
    fecha_notificacion   = Column(DateTime, nullable=True)
