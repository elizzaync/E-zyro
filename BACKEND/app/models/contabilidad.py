"""
Modelos del núcleo contable (Fase 1 — Libro Mayor).

Cuatro tablas que forman el cimiento de todo el módulo de finanzas:
  - cuenta_contable  : catálogo PCGE por empresa (jerárquico, mayor/detalle)
  - periodo_contable : meses contables abiertos/cerrados por empresa
  - asiento_contable : cabecera del asiento (un hecho económico)
  - asiento_linea    : detalle (cada renglón débito XOR crédito)

El invariante de oro (SUM debito = SUM credito) se defiende en TRES capas:
schema (pydantic) → servicio (contabilizacion_service) → constraints de BD
(definidos aquí con CheckConstraint). Esta es la última línea de defensa: aunque
un UPDATE manual o un bug intente escribir directo, la BD rechaza el descuadre
de cada línea.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Boolean, Integer, Date, DateTime, Numeric,
    ForeignKey, CheckConstraint, UniqueConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class CuentaContable(Base):
    __tablename__ = "cuenta_contable"

    id              = Column(String(36), primary_key=True, default=_uuid)
    empresa_id      = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    codigo          = Column(String(20), nullable=False)   # jerárquico: 10, 101, 1041
    nombre          = Column(String(200), nullable=False)
    tipo            = Column(String(20), nullable=False)   # activo|pasivo|patrimonio|ingreso|gasto
    naturaleza      = Column(String(20), nullable=False)   # deudora|acreedora
    nivel           = Column(String(20), nullable=False)   # mayor|detalle (solo detalle recibe movimientos)
    cuenta_padre_id = Column(String(36), ForeignKey("cuenta_contable.id"), nullable=True)
    activo          = Column(Boolean, nullable=False, default=True)
    created_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at      = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "codigo", name="uq_cuenta_empresa_codigo"),
        CheckConstraint(
            "tipo IN ('activo','pasivo','patrimonio','ingreso','gasto')",
            name="chk_cuenta_tipo",
        ),
        CheckConstraint(
            "naturaleza IN ('deudora','acreedora')",
            name="chk_cuenta_naturaleza",
        ),
        CheckConstraint(
            "nivel IN ('mayor','detalle')",
            name="chk_cuenta_nivel",
        ),
    )


class PeriodoContable(Base):
    __tablename__ = "periodo_contable"

    id            = Column(String(36), primary_key=True, default=_uuid)
    empresa_id    = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    anio          = Column(Integer, nullable=False)
    mes           = Column(Integer, nullable=False)        # 1-12
    estado        = Column(String(20), nullable=False, default="abierto")  # abierto|cerrado
    cerrado_por_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    cerrado_at    = Column(DateTime, nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "anio", "mes", name="uq_periodo_empresa_anio_mes"),
        CheckConstraint("estado IN ('abierto','cerrado')", name="chk_periodo_estado"),
        CheckConstraint("mes >= 1 AND mes <= 12", name="chk_periodo_mes"),
    )


class AsientoContable(Base):
    __tablename__ = "asiento_contable"

    id            = Column(String(36), primary_key=True, default=_uuid)
    empresa_id    = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    numero        = Column(String(30), nullable=False)     # correlativo por empresa+periodo
    fecha         = Column(Date, nullable=False)
    periodo_id    = Column(String(36), ForeignKey("periodo_contable.id"), nullable=False)
    descripcion   = Column(String(500), nullable=False)
    origen        = Column(String(40), nullable=False, default="manual")  # manual|compras|ventas|inventario|planilla|depreciacion|apertura...
    referencia_id = Column(String(36), nullable=True)      # id del documento origen
    creado_por_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "periodo_id", "numero", name="uq_asiento_numero"),
    )


class AsientoLinea(Base):
    # Nombre fijado y único en todo el módulo: NO usar `detalle_asiento`.
    __tablename__ = "asiento_linea"

    id              = Column(String(36), primary_key=True, default=_uuid)
    asiento_id      = Column(String(36), ForeignKey("asiento_contable.id"), nullable=False)
    cuenta_id       = Column(String(36), ForeignKey("cuenta_contable.id"), nullable=False)
    debito          = Column(Numeric(14, 2), nullable=False, default=0)
    credito         = Column(Numeric(14, 2), nullable=False, default=0)
    # FK a centro_costo materializada en Fase 2 (imputación analítica opcional).
    centro_costo_id = Column(String(36), ForeignKey("centro_costo.id"), nullable=True)
    glosa           = Column(String(255), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "(debito > 0 AND credito = 0) OR (credito > 0 AND debito = 0)",
            name="chk_linea_debito_xor_credito",
        ),
    )


class CentroCosto(Base):
    """Centro de costo (Fase 2 — Controlling).

    Permite imputación analítica: cada línea de asiento puede asociarse a un
    centro (proyecto/área/empleado/libre) para responder "¿cuánto costó este
    proyecto?". No genera asientos: solo etiqueta líneas que el motor de la
    Fase 1 ya persiste. Los reportes (controlling_service) lo leen.
    """
    __tablename__ = "centro_costo"

    id                      = Column(String(36), primary_key=True, default=_uuid)
    empresa_id              = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    codigo                  = Column(String(20), nullable=False)   # legible: CC-001
    nombre                  = Column(String(150), nullable=False)
    tipo_referencia         = Column(String(20), nullable=False, default="libre")  # proyecto|area|empleado|libre
    referencia_id           = Column(String(36), nullable=True)    # id del proyecto/area/empleado segun tipo
    presupuesto_referencial = Column(Numeric(14, 2), nullable=True)
    activo                  = Column(Boolean, nullable=False, default=True)
    created_at              = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at              = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "codigo", name="uq_centro_costo_empresa_codigo"),
        CheckConstraint(
            "tipo_referencia IN ('proyecto','area','empleado','libre')",
            name="chk_centro_costo_tipo_referencia",
        ),
    )
