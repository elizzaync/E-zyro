"""
Configuración de facturación electrónica (CPE) por empresa.

FEATURE OPCIONAL: `habilitado=False` por defecto — el sistema funciona igual
sin ella (las facturas de CxC quedan como registros internos). Al habilitarla,
cada factura/boleta emitida en CxC se envía al PSE (Nubefact) que genera el
XML UBL firmado, lo declara a SUNAT y devuelve PDF/XML/CDR.

NOTA: la tabla se crea con SQL crudo en _run_migrations de main.py
(FK uuid en producción); NO confiar en create_all.
"""
import uuid
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ConfiguracionFacturacionElectronica(Base):
    __tablename__ = "configuracion_facturacion_electronica"

    id           = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id   = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    habilitado   = Column(Boolean, nullable=False, default=False)
    proveedor    = Column(String(30), nullable=False, default="nubefact")
    # Nubefact asigna a cada cuenta una URL propia (…/api/v1/<hash>) + token.
    # Una cuenta DEMO de Nubefact sirve para desarrollar sin declarar nada real.
    api_url      = Column(String(300), nullable=True)
    api_token    = Column(String(300), nullable=True)
    serie_factura = Column(String(10), nullable=False, default="F001")
    serie_boleta  = Column(String(10), nullable=False, default="B001")
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at   = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", name="uq_config_fe_empresa"),
    )
