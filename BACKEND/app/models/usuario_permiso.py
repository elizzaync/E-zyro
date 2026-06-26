from datetime import datetime
from sqlalchemy import Column, String, ForeignKey, DateTime
from app.db.database import Base

class UsuarioPermiso(Base):
    __tablename__ = "usuario_permiso"

    # Definimos las llaves foráneas que apuntan a tus tablas existentes
    usuario_id = Column(String(36), ForeignKey("usuario.id"), primary_key=True)
    permiso_id = Column(String(36), ForeignKey("permiso.id"), primary_key=True)

    # Campo opcional para saber quién le dio este permiso extra (auditoría)
    asignado_por = Column(String(36), ForeignKey("usuario.id"), nullable=True)

    # Fecha en la que se le dio la excepción.
    # Default Python (datetime.utcnow), NO func.now(): un default SQL sobre una PK
    # compuesta obliga a INSERT ... RETURNING y dispara `insertmanyvalues`, cuyo
    # sentinel mezcla str/uuid.UUID y revienta con KeyError en psycopg2. El callable
    # se evalúa en cliente, sin RETURNING. (Convención del resto de modelos.)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)