"""
Modelo de costeo de inventario (Fase 5 — Valuación de inventario).

`costo_promedio_material` guarda el estado vigente del costo por material+almacén
bajo el método de **promedio ponderado**: cada ingreso lo recalcula, cada salida
consume el promedio vigente. Las columnas de valor (costo_unitario, valor_total,
asiento_id) se añaden a `movimiento_inventario` por ALTER en _run_migrations.
"""
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, DateTime, Numeric, ForeignKey, UniqueConstraint, CheckConstraint,
)
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class CostoPromedioMaterial(Base):
    __tablename__ = "costo_promedio_material"

    id                    = Column(String(36), primary_key=True, default=_uuid)
    empresa_id            = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    material_id           = Column(String(36), ForeignKey("material.id"), nullable=False)
    almacen_id            = Column(String(36), ForeignKey("almacen.id"), nullable=False)
    cantidad_actual       = Column(Numeric(18, 4), nullable=False, default=0)
    costo_promedio_actual = Column(Numeric(14, 4), nullable=False, default=0)
    updated_at            = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("empresa_id", "material_id", "almacen_id",
                         name="uq_costo_promedio_mat_alm"),
        CheckConstraint("cantidad_actual >= 0", name="chk_costo_cantidad_no_negativa"),
        CheckConstraint("costo_promedio_actual >= 0", name="chk_costo_promedio_no_negativo"),
    )
