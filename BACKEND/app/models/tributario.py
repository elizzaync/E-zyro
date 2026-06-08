"""
Modelos de régimen tributario (Fase 6 — IGV aplicado).

La tasa de IGV y las cuentas de crédito/débito fiscal viven en CONFIGURACIÓN, no
en el código: cambiar la tasa o las subcuentas no requiere despliegue. El motor
(AP/AR) consulta `tributario_service`, que lee estas tablas.

  - regimen_tributario_catalogo : catálogo global de regímenes (general/mype/...)
  - configuracion_tributaria_empresa : parámetros por empresa (FK régimen + cuentas IGV)
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Boolean, DateTime, Numeric, ForeignKey, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class RegimenTributarioCatalogo(Base):
    __tablename__ = "regimen_tributario_catalogo"

    id                     = Column(String(36), primary_key=True, default=_uuid)
    codigo                 = Column(String(20), nullable=False, unique=True)  # general|mype|especial|nrus
    nombre                 = Column(String(120), nullable=False)
    tasa_igv               = Column(Numeric(5, 2), nullable=False, default=18.00)
    tasa_renta_referencial = Column(Numeric(5, 2), nullable=True)
    activo                 = Column(Boolean, nullable=False, default=True)
    created_at             = Column(DateTime, nullable=False, default=datetime.utcnow)


class ConfiguracionTributariaEmpresa(Base):
    __tablename__ = "configuracion_tributaria_empresa"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    regimen_id  = Column(String(36), ForeignKey("regimen_tributario_catalogo.id"), nullable=False)
    cuenta_igv_credito_fiscal_id = Column(String(36), ForeignKey("cuenta_contable.id"), nullable=True)
    cuenta_igv_debito_fiscal_id  = Column(String(36), ForeignKey("cuenta_contable.id"), nullable=True)
    updated_at  = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", name="uq_config_tributaria_empresa"),
    )
