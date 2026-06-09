"""
Modelos de Conciliación Bancaria (Fase 5 — cierre del módulo de finanzas).

Permite cuadrar lo que dice el banco (el extracto) contra lo que dicen los
libros (los asientos del libro mayor sobre la cuenta de Bancos del PCGE).

  - cuenta_bancaria     : una cuenta de la empresa en un banco, vinculada a su
                          cuenta contable del PCGE (normalmente familia 104).
  - movimiento_bancario : cada renglón del extracto (cargo/abono). Arranca
                          'pendiente' y pasa a 'conciliado' cuando se vincula a
                          un asiento contable existente (1-a-1 por asiento_id).

La conciliación NO genera asientos: solo enlaza un movimiento del banco con un
asiento que YA existe en el libro mayor. El asiento sigue naciendo de su módulo
de origen (compras, ventas, planilla, caja chica, asiento manual...).

Sigue el patrón de los demás modelos de finanzas: PK/FK String(36), creadas por
Base.metadata.create_all (sin DDL explícito en main.py).
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Boolean, Date, DateTime, Numeric, ForeignKey,
    CheckConstraint, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


# Las tablas de identidad (empresa/empleado) y el núcleo contable
# (cuenta_contable/asiento_contable) usan PK `uuid` en producción. Estas tablas
# son NUEVAS (las crea create_all), así que sus PK/FK deben ser `uuid` para que
# la FK case con el tipo referenciado; con String(36) Postgres rechaza la FK
# (varchar↔uuid). Se usa as_uuid=False para seguir trabajando con str en el ORM.
class CuentaBancaria(Base):
    __tablename__ = "cuenta_bancaria"

    id                 = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id         = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    banco              = Column(String(120), nullable=False)
    numero_cuenta      = Column(String(60), nullable=False)
    moneda             = Column(String(10), nullable=False, default="PEN")   # PEN|USD
    # Cuenta del PCGE que representa este banco en los libros (familia 104).
    cuenta_contable_id = Column(UUID(as_uuid=False), ForeignKey("cuenta_contable.id"), nullable=False)
    alias              = Column(String(120), nullable=True)
    activo             = Column(Boolean, nullable=False, default=True)
    created_at         = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at         = Column(DateTime, nullable=True, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "banco", "numero_cuenta",
                         name="uq_cuenta_bancaria_empresa_banco_numero"),
        CheckConstraint("moneda IN ('PEN','USD')", name="chk_cuenta_bancaria_moneda"),
    )


class MovimientoBancario(Base):
    __tablename__ = "movimiento_bancario"

    id                 = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id         = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    cuenta_bancaria_id = Column(UUID(as_uuid=False), ForeignKey("cuenta_bancaria.id"), nullable=False)
    fecha              = Column(Date, nullable=False)
    descripcion        = Column(String(300), nullable=False)
    referencia         = Column(String(100), nullable=True)   # nro de operación del banco
    tipo               = Column(String(10), nullable=False)   # cargo|abono
    monto              = Column(Numeric(14, 2), nullable=False)
    estado             = Column(String(15), nullable=False, default="pendiente")  # pendiente|conciliado
    # Asiento del libro mayor con el que quedó conciliado (1-a-1). NULL = pendiente.
    asiento_id         = Column(UUID(as_uuid=False), ForeignKey("asiento_contable.id"), nullable=True)
    origen_carga       = Column(String(10), nullable=False, default="manual")  # manual|csv
    conciliado_por_id  = Column(UUID(as_uuid=False), ForeignKey("empleado.id"), nullable=True)
    conciliado_at      = Column(DateTime, nullable=True)
    created_at         = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        CheckConstraint("tipo IN ('cargo','abono')", name="chk_movimiento_bancario_tipo"),
        CheckConstraint("estado IN ('pendiente','conciliado')",
                        name="chk_movimiento_bancario_estado"),
        CheckConstraint("monto > 0", name="chk_movimiento_bancario_monto_positivo"),
    )
