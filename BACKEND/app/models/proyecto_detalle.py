from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base

class ProyectoDetalle(Base):
    __tablename__ = "proyecto_detalle"

    # Relación 1 a 1 estricta con proyecto
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), primary_key=True)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)

    # Solo el OC "marco" del proyecto. El alcance, zona, documentación y conformidad
    # ahora viven a nivel de proyecto_servicio (cada servicio lleva los suyos).
    orden_compra_cliente = Column(String(100))

    updated_at = Column(DateTime)
