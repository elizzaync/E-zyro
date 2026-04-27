import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Empresa(Base):
    __tablename__ = "empresa"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    razon_social = Column(String(200), nullable=False)
    ruc = Column(String(20), nullable=False, unique=True)
    email_contacto = Column(String(150), nullable=False)
    slug = Column(String(100), nullable=False, unique=True)
    estado = Column(String(20), nullable=False)
    fecha_registro = Column(DateTime, nullable=False, default=datetime.utcnow)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)