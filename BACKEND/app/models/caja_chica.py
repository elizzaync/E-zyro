import uuid
from datetime import datetime
from sqlalchemy import Column, String, Numeric, Boolean, Date, DateTime, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class CajaChica(Base):
    __tablename__ = "caja_chica"

    id                        = Column(String(36), primary_key=True, default=_uuid)
    empresa_id                = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    responsable_id            = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    proyecto_id               = Column(String(36), ForeignKey("proyecto.id"), nullable=True)
    nombre                    = Column(String(150), nullable=False)
    descripcion               = Column(String(255), nullable=True)
    monto_asignado_referencial = Column(Numeric(10, 2), nullable=True)
    fecha_apertura            = Column(Date, nullable=False)
    fecha_cierre              = Column(Date, nullable=True)
    estado                    = Column(String(30), nullable=False, default="abierta")  # abierta|cerrada|suspendida
    created_at                = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at                = Column(DateTime, nullable=True)


class MovimientoCaja(Base):
    __tablename__ = "movimiento_caja"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    caja_id              = Column(String(36), ForeignKey("caja_chica.id"), nullable=False)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo                 = Column(String(10), nullable=False)   # ingreso|egreso
    monto                = Column(Numeric(10, 2), nullable=False)
    descripcion          = Column(String(500), nullable=False)
    concepto             = Column(String(100), nullable=True)
    comprobante_url      = Column(String(500), nullable=True)
    public_id_cloudinary = Column(String(255), nullable=True)
    registrado_por       = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    fecha                = Column(DateTime, nullable=False)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
