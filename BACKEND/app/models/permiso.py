from sqlalchemy import Column, String, UniqueConstraint
from app.db.database import Base

class Permiso(Base):
    __tablename__ = "permiso"

    id = Column(String(36), primary_key=True, index=True)
    modulo = Column(String(100), nullable=False)
    accion = Column(String(50), nullable=False)
    descripcion = Column(String(255), nullable=True)

    # El seed (`ON CONFLICT (modulo, accion)`) asume este UNIQUE; en producción
    # existe vía migración cruda fuera del modelo ORM.
    __table_args__ = (UniqueConstraint("modulo", "accion", name="permiso_modulo_accion_key"),)