import uuid
from datetime import datetime
from sqlalchemy import Column, String, Numeric, DateTime, ForeignKey
from app.db.database import Base


class FotoAsistencia(Base):
    __tablename__ = "foto_asistencia"

    id                   = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    registro_id          = Column(String(36), ForeignKey("registro_asistencia.id"), nullable=False)
    url_cloudinary       = Column(String(500), nullable=True)
    public_id_cloudinary = Column(String(255), nullable=True)
    similitud_ia         = Column(Numeric(6, 4), nullable=True)   # 0.0000 – 1.0000
    resultado            = Column(String(20),  nullable=True)     # aprobado | revision_manual | rechazado
    fecha_captura        = Column(DateTime, nullable=False, default=datetime.utcnow)
