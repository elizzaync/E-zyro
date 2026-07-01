"""Configuración contable por empresa (cierre de ejercicio y políticas).

Principio del módulo: las decisiones contables NO se preguntan al usuario final
ni se fijan en código — viven aquí como configuración con defaults correctos
para una MYPE peruana, editables desde la pantalla "Configuración contable"
(permiso contabilidad.configurar).

Las cuentas se referencian por CÓDIGO PCGE (no por id): el código es estable,
único por empresa (uq_cuenta_empresa_codigo) y legible en auditoría; además
evita FKs varchar→uuid contra cuenta_contable (PK uuid nativa en prod).
"""
import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint

from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ConfiguracionContableEmpresa(Base):
    __tablename__ = "configuracion_contable_empresa"

    id         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    # Cuenta puente del cierre (elemento 8 — determinación del resultado).
    cuenta_cierre_codigo   = Column(String(20), nullable=False, default="891")
    # Destino del resultado en patrimonio: utilidad (59.1) o pérdida (59.2).
    cuenta_utilidad_codigo = Column(String(20), nullable=False, default="591")
    cuenta_perdida_codigo  = Column(String(20), nullable=False, default="592")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", name="uq_config_contable_empresa"),
    )
