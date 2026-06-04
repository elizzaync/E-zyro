import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Numeric, Boolean, Text, DateTime
from sqlalchemy.dialects.postgresql import UUID
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class TicketCompra(Base):
    __tablename__ = "ticket_compra"

    id                     = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    empresa_id             = Column(UUID(as_uuid=False), nullable=False)
    requerimiento_id       = Column(UUID(as_uuid=False), nullable=True)
    codigo                 = Column(String(20), nullable=False)
    estado                 = Column(String(20), nullable=False, default="pendiente")
    origen                 = Column(String(30), nullable=True)          # 'prestamo_faltante' → al recibir genera préstamo
    solicitante_id         = Column(UUID(as_uuid=False), nullable=True)  # técnico que pidió (para el auto-préstamo)
    proyecto_id            = Column(UUID(as_uuid=False), nullable=True)
    proyecto_servicio_id   = Column(UUID(as_uuid=False), nullable=True)
    proyecto_nombre        = Column(String(300), nullable=True)
    servicio_nombre        = Column(String(300), nullable=True)
    solicitante_nombre     = Column(String(200), nullable=True)
    modo_unificado         = Column(Boolean, nullable=True)
    proveedor_unico_id     = Column(UUID(as_uuid=False), nullable=True)
    proveedor_unico_nombre = Column(String(200), nullable=True)
    canal_unico            = Column(String(200), nullable=True)
    total_estimado         = Column(Numeric(12, 2), nullable=True)
    total_real             = Column(Numeric(12, 2), nullable=True)
    responsable_id         = Column(UUID(as_uuid=False), nullable=True)
    nota                   = Column(Text, nullable=True)
    motivo_cancelacion     = Column(Text, nullable=True)
    created_at             = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at             = Column(DateTime, nullable=True)
    # Fase 3 — guard de idempotencia para el ingreso al inventario
    ingreso_registrado     = Column("ingreso_registrado", __import__("sqlalchemy").Boolean,
                                    nullable=False, default=False, server_default="false")


class TicketCompraItem(Base):
    __tablename__ = "ticket_compra_item"

    id                       = Column(UUID(as_uuid=False), primary_key=True, default=_uuid)
    ticket_id                = Column(UUID(as_uuid=False), nullable=False)
    requerimiento_detalle_id = Column(UUID(as_uuid=False), nullable=True)
    material_id              = Column(UUID(as_uuid=False), nullable=True)
    nombre                   = Column(String(300), nullable=False)
    cantidad                 = Column(Integer, nullable=False, default=1)
    unidad                   = Column(String(50), nullable=True)
    cantidad_comprada        = Column(Integer, nullable=True)
    precio_unitario          = Column(Numeric(12, 2), nullable=True)
    total_item               = Column(Numeric(12, 2), nullable=True)
    proveedor_id             = Column(UUID(as_uuid=False), nullable=True)
    proveedor_nombre         = Column(String(200), nullable=True)
    canal_personalizado      = Column(String(200), nullable=True)
    factura                  = Column(String(100), nullable=True)
    estado_item              = Column(String(20), nullable=False, default="pendiente")
    nota                     = Column(Text, nullable=True)
    # Fase 2 — sugerencia automática (snapshot inmutable para auditoría)
    cantidad_sugerida        = Column(Integer, nullable=True)
    stock_al_aprobar         = Column(Integer, nullable=True)
    stock_minimo_al_aprobar  = Column(Integer, nullable=True)
    # Fase 1 — clasificación del ítem propagada desde requerimiento_detalle
    #   material | equipo | herramienta
    tipo_item                = Column(String(20), nullable=True, default="material")
    # Fase 2 — FK al registro creado en equipo (solo para tipo_item equipo/herramienta)
    equipo_id                = Column(__import__("sqlalchemy.dialects.postgresql", fromlist=["UUID"]).UUID(as_uuid=False), nullable=True)
