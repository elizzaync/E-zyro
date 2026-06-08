"""
Modelos de activos fijos y depreciación (Fase 7).

`activo_fijo` es la ficha financiera del bien (puede vincularse al `equipo`
operativo ya existente). `depreciacion_mensual` registra cada mes procesado:
su UNIQUE(activo, periodo) es lo que garantiza que el job no duplique asientos
de depreciación aunque se ejecute dos veces.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Integer, Date, DateTime, Numeric,
    ForeignKey, CheckConstraint, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ActivoFijo(Base):
    __tablename__ = "activo_fijo"

    id                        = Column(String(36), primary_key=True, default=_uuid)
    empresa_id                = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    equipo_id                 = Column(String(36), ForeignKey("equipo.id"), nullable=True)
    nombre                    = Column(String(200), nullable=False)
    fecha_adquisicion         = Column(Date, nullable=False)
    valor_adquisicion         = Column(Numeric(14, 2), nullable=False)
    valor_residual            = Column(Numeric(14, 2), nullable=False, default=0)
    vida_util_meses           = Column(Integer, nullable=False)
    metodo_depreciacion       = Column(String(20), nullable=False, default="linea_recta")
    fecha_inicio_depreciacion = Column(Date, nullable=False)
    estado                    = Column(String(20), nullable=False, default="activo")
    centro_costo_id           = Column(String(36), ForeignKey("centro_costo.id"), nullable=True)
    created_at                = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at                = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        CheckConstraint("metodo_depreciacion IN ('linea_recta')", name="chk_activo_metodo"),
        CheckConstraint("estado IN ('activo','depreciado_total','dado_de_baja')", name="chk_activo_estado"),
        CheckConstraint("vida_util_meses > 0", name="chk_activo_vida_util"),
        CheckConstraint("valor_adquisicion >= 0 AND valor_residual >= 0", name="chk_activo_valores"),
    )


class DepreciacionMensual(Base):
    __tablename__ = "depreciacion_mensual"

    id                         = Column(String(36), primary_key=True, default=_uuid)
    activo_fijo_id             = Column(String(36), ForeignKey("activo_fijo.id"), nullable=False)
    periodo_id                 = Column(String(36), ForeignKey("periodo_contable.id"), nullable=False)
    monto_depreciado           = Column(Numeric(14, 2), nullable=False)
    valor_en_libros_resultante = Column(Numeric(14, 2), nullable=False)
    asiento_id                 = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    procesado_at               = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("activo_fijo_id", "periodo_id", name="uq_depreciacion_activo_periodo"),
    )
