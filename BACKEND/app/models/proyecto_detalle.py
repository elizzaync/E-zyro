from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from app.db.database import Base

class ProyectoDetalle(Base):
    __tablename__ = "proyecto_detalle"

    # La llave primaria es también llave foránea porque es relación 1 a 1 estricta
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), primary_key=True)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)

    zona_ejecucion = Column(String(255))
    alcance = Column(Text, nullable=False)

    orden_compra_cliente = Column(String(100))
    tipo_documento_cliente = Column(String(50))
    nro_documento = Column(String(100))

    nro_conformidad = Column(String(100), default='En Espera')
    acta_url = Column(String(500))
    public_id_cloudinary = Column(String(255))

    updated_at = Column(DateTime)