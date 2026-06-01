from __future__ import annotations
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Integer, ForeignKey, Text, DateTime
from sqlalchemy.dialects.postgresql import UUID
from ..db.database import Base


class Retorno(Base):
    __tablename__ = "retorno"

    id                   = Column(UUID(as_uuid=False), primary_key=True)
    empresa_id           = Column(UUID(as_uuid=False), ForeignKey("empresa.id"), nullable=False)
    proyecto_servicio_id = Column(UUID(as_uuid=False), ForeignKey("proyecto_servicio.id"), nullable=True)
    requerimiento_id     = Column(UUID(as_uuid=False), ForeignKey("requerimiento.id"), nullable=True)
    estado               = Column(String, nullable=False, default="enviado")
    iniciado_por_id      = Column(UUID(as_uuid=False), ForeignKey("empleado.id"), nullable=True)
    inspeccionado_por_id = Column(UUID(as_uuid=False), ForeignKey("empleado.id"), nullable=True)
    nota_tecnico         = Column(Text, nullable=True)
    nota_logistica       = Column(Text, nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime, nullable=True)
    completado_en        = Column(DateTime, nullable=True)


class RetornoDetalle(Base):
    __tablename__ = "retorno_detalle"

    id                  = Column(UUID(as_uuid=False), primary_key=True)
    retorno_id          = Column(UUID(as_uuid=False), ForeignKey("retorno.id", ondelete="CASCADE"), nullable=False)
    material_id         = Column(UUID(as_uuid=False), ForeignKey("material.id"), nullable=True)
    equipo_id           = Column(UUID(as_uuid=False), ForeignKey("equipo.id"), nullable=True)
    nombre              = Column(String, nullable=False)
    unidad              = Column(String, nullable=True, default="Unidades")
    tipo_item           = Column(String, nullable=False, default="material")
    cantidad_entregada  = Column(Integer, nullable=False, default=0)
    cantidad_retornada  = Column(Integer, nullable=True)
    cantidad_confirmada = Column(Integer, nullable=True)
    es_obligatorio      = Column(Boolean, nullable=False, default=False)
    estado_item         = Column(String, nullable=False, default="pendiente")
