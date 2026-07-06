"""
Modelos de nómina / planilla (Fase 8).

⚠️ El cálculo legal real (EsSalud, ONP/AFP, Renta 5ta, gratificaciones, CTS…)
requiere validación de un especialista legal-laboral — fuera del alcance del
laboratorio, igual que la validación por contador colegiado quedó fuera en la
Fase 0. Aquí los conceptos son CONFIGURABLES (monto_referencial por concepto):
la estructura y la integración contable son correctas y balanceadas; las
fórmulas reales se cargan como datos validados externamente, sin tocar código.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Date, DateTime, Numeric, Text,
    ForeignKey, CheckConstraint, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class ConceptoRemunerativo(Base):
    __tablename__ = "concepto_remunerativo"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    codigo              = Column(String(20), nullable=False)
    nombre              = Column(String(150), nullable=False)
    tipo                = Column(String(20), nullable=False)  # ingreso|descuento|aporte_empleador
    monto_referencial   = Column(Numeric(14, 2), nullable=True)  # dato configurable (no fórmula legal embebida)
    formula_referencial = Column(String(255), nullable=True)     # descripción textual
    cuenta_contable_id  = Column(String(36), ForeignKey("cuenta_contable.id"), nullable=True)
    activo              = Column(String(5), nullable=False, default="true")
    # Concepto base (sueldo básico): su monto define el "valor día" (monto/30)
    # para los descuentos por faltas/tardanzas de asistencia (Fase 2).
    es_base             = Column(String(5), nullable=False, default="false")
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "codigo", name="uq_concepto_empresa_codigo"),
        CheckConstraint("tipo IN ('ingreso','descuento','aporte_empleador')", name="chk_concepto_tipo"),
    )


class Planilla(Base):
    __tablename__ = "planilla"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    periodo_id           = Column(String(36), ForeignKey("periodo_contable.id"), nullable=False)
    fecha_proceso        = Column(Date, nullable=False)
    estado               = Column(String(20), nullable=False, default="calculada")  # borrador|calculada|aprobada|pagada|anulada
    total_ingresos       = Column(Numeric(14, 2), nullable=False, default=0)
    total_descuentos     = Column(Numeric(14, 2), nullable=False, default=0)
    total_aportes        = Column(Numeric(14, 2), nullable=False, default=0)
    total_neto           = Column(Numeric(14, 2), nullable=False, default=0)
    # Informativos (Fase 8): provisión mensualizada de CTS/Gratificación/
    # Vacaciones. NO suman a total_ingresos/neto ni a los asientos contables —
    # se pagan en su fecha legal real (CTS mayo/nov, gratificación jul/dic).
    total_cts            = Column(Numeric(14, 2), nullable=False, default=0)
    total_gratificacion  = Column(Numeric(14, 2), nullable=False, default=0)
    total_vacaciones     = Column(Numeric(14, 2), nullable=False, default=0)
    asiento_provision_id = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    asiento_pago_id      = Column(String(36), ForeignKey("asiento_contable.id"), nullable=True)
    aprobado_por_id      = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "periodo_id", name="uq_planilla_empresa_periodo"),
        CheckConstraint("estado IN ('borrador','calculada','aprobada','pagada','anulada')", name="chk_planilla_estado"),
    )


class BoletaPago(Base):
    __tablename__ = "boleta_pago"

    id               = Column(String(36), primary_key=True, default=_uuid)
    planilla_id      = Column(String(36), ForeignKey("planilla.id"), nullable=False)
    empleado_id      = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    total_ingresos   = Column(Numeric(14, 2), nullable=False, default=0)
    total_descuentos = Column(Numeric(14, 2), nullable=False, default=0)
    total_aportes    = Column(Numeric(14, 2), nullable=False, default=0)
    total_neto       = Column(Numeric(14, 2), nullable=False, default=0)
    # Informativos (Fase 8): ver comentario equivalente en Planilla.
    total_cts           = Column(Numeric(14, 2), nullable=False, default=0)
    total_gratificacion = Column(Numeric(14, 2), nullable=False, default=0)
    total_vacaciones    = Column(Numeric(14, 2), nullable=False, default=0)
    pdf_url          = Column(Text, nullable=True)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)


class BoletaPagoDetalle(Base):
    __tablename__ = "boleta_pago_detalle"

    id          = Column(String(36), primary_key=True, default=_uuid)
    boleta_id   = Column(String(36), ForeignKey("boleta_pago.id"), nullable=False)
    concepto_id = Column(String(36), ForeignKey("concepto_remunerativo.id"), nullable=False)
    monto       = Column(Numeric(14, 2), nullable=False)


class EmpleadoConcepto(Base):
    """Monto de un concepto remunerativo asignado a un empleado concreto.

    Permite que cada empleado tenga importes distintos (sueldos diferentes).
    Si no existe asignación para (empleado, concepto), el cálculo cae al
    `monto_referencial` del catálogo. Un monto 0 SÍ es válido (anula ese
    concepto para esa persona); para volver al referencial se elimina la fila.
    """
    __tablename__ = "empleado_concepto"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    concepto_id = Column(String(36), ForeignKey("concepto_remunerativo.id"), nullable=False)
    monto       = Column(Numeric(14, 2), nullable=False)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at  = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empleado_id", "concepto_id", name="uq_empleado_concepto"),
    )
