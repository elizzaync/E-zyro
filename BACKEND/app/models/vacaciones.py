import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Integer, Date, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ConfigVacaciones(Base):
    """Configuración de vacaciones por empresa (Punto 3.3).

    Régimen parametrizable: General 30 días/año, REMYPE 15 días/año.
    `tope_acumulacion` limita los días disponibles acumulados (no gozados).
    """
    __tablename__ = "config_vacaciones"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False, unique=True)
    regimen          = Column(String(40), nullable=False, default="general")  # general|remype|otro
    dias_por_anio    = Column(Integer, nullable=False, default=30)
    tope_acumulacion = Column(Integer, nullable=False, default=30)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True)


class SolicitudVacaciones(Base):
    """Solicitud de vacaciones de un empleado. Los días aprobados se descuentan
    del saldo (gozado = suma de solicitudes aprobadas)."""
    __tablename__ = "solicitud_vacaciones"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id       = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    fecha_inicio      = Column(Date, nullable=False)
    fecha_fin         = Column(Date, nullable=False)
    dias              = Column(Integer, nullable=False)         # días calendario inclusive
    estado            = Column(String(20), nullable=False, default="pendiente")  # pendiente|aprobada|rechazada|cancelada
    motivo            = Column(String(500), nullable=True)
    solicitado_por_id = Column(String(36), nullable=True)
    resuelto_por_id   = Column(String(36), nullable=True)
    fecha_resolucion  = Column(DateTime, nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)


class AjusteSaldoVacaciones(Base):
    """Saldo inicial de vacaciones por empleado, para migración desde un
    sistema anterior. Almacena la diferencia (ajuste_dias) entre los días
    disponibles reales en la fecha de ajuste y el devengado calculado a esa
    fecha. El router lo aplica como: disponible = min(devengado + ajuste_dias
    - gozado, tope). Un ajuste negativo absorbe días ya gozados sin registro."""
    __tablename__ = "ajuste_saldo_vacaciones"

    id             = Column(String(36), primary_key=True, default=_uuid)
    empresa_id     = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id    = Column(String(36), ForeignKey("empleado.id"), nullable=False, unique=True)
    ajuste_dias    = Column(Integer, nullable=False)          # puede ser negativo
    notas          = Column(String(500), nullable=True)
    creado_por_id  = Column(String(36), nullable=True)
    created_at     = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at     = Column(DateTime, nullable=True)
