"""Configuración previsional por empleado (Fase 8 — motor legal de Planilla).

Tabla 1:1 opcional con `empleado` (no columnas en `empleado`, que es
transversal a legajo/asistencia/evaluaciones). Fila ausente = valores por
defecto en código (onp, sin AFP, sin asignación familiar) — ver
`planilla_service`/`planilla_calculo_service`.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Boolean, Numeric, DateTime,
    ForeignKey, CheckConstraint, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class EmpleadoPlanillaConfig(Base):
    __tablename__ = "empleado_planilla_config"

    id                         = Column(String(36), primary_key=True, default=_uuid)
    empresa_id                 = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id                = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    sistema_pension            = Column(String(10), nullable=False, default="onp")   # onp|afp
    entidad_afp                = Column(String(20), nullable=True)                    # integra|prima|profuturo|habitat
    comision_afp_personalizada = Column(Numeric(6, 4), nullable=True)
    tiene_asignacion_familiar  = Column(Boolean, nullable=False, default=False)
    # Esquema de comisión SPP (2026-07-07): 'saldo' (default legal desde
    # 2013, comisión ~0.78% anual sobre el FONDO acumulado — NO se descuenta
    # en planilla) o 'flujo' (comisión sobre la remuneración — SÍ se
    # descuenta cada mes). Ver planilla_calculo_service._comision_afp_efectiva.
    tipo_comision_afp          = Column(String(10), nullable=False, default="saldo")
    created_at                 = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at                 = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empleado_id", name="uq_empleado_planilla_config"),
        CheckConstraint("sistema_pension IN ('onp','afp')", name="chk_epc_sistema_pension"),
        CheckConstraint(
            "entidad_afp IS NULL OR entidad_afp IN ('integra','prima','profuturo','habitat')",
            name="chk_epc_entidad_afp",
        ),
        CheckConstraint("tipo_comision_afp IN ('flujo','saldo')", name="chk_epc_tipo_comision_afp"),
    )
