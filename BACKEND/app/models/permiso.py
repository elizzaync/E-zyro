from sqlalchemy import Column, String
from app.db.database import Base

class Permiso(Base):
    __tablename__ = "permiso"

    id = Column(String(36), primary_key=True, index=True)
    modulo = Column(String(100), nullable=False)
    accion = Column(String(50), nullable=False)
    descripcion = Column(String(255), nullable=True)