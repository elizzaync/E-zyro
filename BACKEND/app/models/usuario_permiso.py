from sqlalchemy import Column, String, ForeignKey, DateTime
from sqlalchemy.sql import func
from app.db.database import Base

class UsuarioPermiso(Base):
    __tablename__ = "usuario_permiso"

    # Definimos las llaves foráneas que apuntan a tus tablas existentes
    usuario_id = Column(String(36), ForeignKey("usuario.id"), primary_key=True)
    permiso_id = Column(String(36), ForeignKey("permiso.id"), primary_key=True)

    # Campo opcional para saber quién le dio este permiso extra (auditoría)
    asignado_por = Column(String(36), ForeignKey("usuario.id"), nullable=True)

    # Fecha en la que se le dio la excepción
    created_at = Column(DateTime, default=func.now(), nullable=False)