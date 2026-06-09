"""
Log de errores/eventos del sistema (Auditoría General — SuperAdmin).

La tabla se crea con SQL crudo (uuid) en _pre_create_migrations de main.py,
ANTES de create_all — este modelo es solo el mapeo ORM (String(36) ≈ uuid,
mismo patrón que auditoria.py).
"""
from sqlalchemy import Column, String, Text, Integer, DateTime
from datetime import datetime
from app.db.database import Base


class LogSistema(Base):
    __tablename__ = "log_sistema"

    id = Column(String(36), primary_key=True, index=True)
    empresa_id = Column(String(36), nullable=True)
    usuario_id = Column(String(36), nullable=True)
    nivel = Column(String(10), nullable=False, default="error")  # info | warning | error
    origen = Column(String(300), nullable=True)   # ruta / módulo que originó el evento
    mensaje = Column(String(1000), nullable=False)
    detalle = Column(Text, nullable=True)         # stack trace u otro detalle largo
    metodo = Column(String(10), nullable=True)    # GET/POST/PUT/DELETE
    status_code = Column(Integer, nullable=True)
    fecha = Column(DateTime, default=datetime.utcnow, nullable=False)
