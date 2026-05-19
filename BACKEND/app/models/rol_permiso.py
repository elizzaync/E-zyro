from sqlalchemy import Column, String, ForeignKey
from app.db.database import Base

class RolPermiso(Base):
    __tablename__ = "rol_permiso"

    rol_id = Column(String(36), ForeignKey("rol.id"), primary_key=True)
    permiso_id = Column(String(36), ForeignKey("permiso.id"), primary_key=True)