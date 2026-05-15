import uuid
from sqlalchemy import Column, String, Date, ForeignKey
from app.db.database import Base

class ProyectoGrupo(Base):
    __tablename__ = "proyecto_grupo"

    proyecto_id      = Column(String(36), ForeignKey("proyecto.id"), primary_key=True)
    grupo_id         = Column(String(36), ForeignKey("grupo_trabajo.id"), primary_key=True)
    rol_en_proyecto  = Column(String(100), nullable=True)
    fecha_asignacion = Column(Date, nullable=False)
