import uuid
from sqlalchemy import Column, String, Numeric, ForeignKey
from app.db.database import Base


class GeolocalizacionAsistencia(Base):
    __tablename__ = "geolocalizacion_asistencia"

    id          = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    registro_id = Column(String(36), ForeignKey("registro_asistencia.id"), nullable=False)
    latitud     = Column(Numeric(10, 7), nullable=False)
    longitud    = Column(Numeric(10, 7), nullable=False)
    precision_m = Column(Numeric(8, 2),  nullable=True)
    altitud     = Column(Numeric(10, 2), nullable=True)
