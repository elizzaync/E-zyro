import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Integer, Numeric, Text, Date, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Requerimiento(Base):
    __tablename__ = "requerimiento"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    proyecto_id          = Column(String(36), ForeignKey("proyecto.id"),           nullable=False)
    proyecto_servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"))
    procedimiento_id     = Column(String(36), ForeignKey("procedimiento.id"))
    empresa_id           = Column(String(36), ForeignKey("empresa.id"),            nullable=False)
    solicitante_id       = Column(String(36), ForeignKey("empleado.id"),           nullable=True)   # nullable: admins sin registro de empleado
    tipo                 = Column(String(30), nullable=False, default="material")
    estado               = Column(String(20), nullable=False, default="pendiente")
    observacion          = Column(String(500))
    observacion_logistico = Column(String(500), nullable=True)  # HU-16
    fecha                = Column(Date, nullable=False, default=date.today)
    aprobado_por         = Column(String(36), ForeignKey("empleado.id"))
    # HU-16: firma del técnico que confirma recepción (estado 'listo')
    firma_receptor_url   = Column(Text, nullable=True)
    firma_recibido_por_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    firma_fecha          = Column(DateTime, nullable=True)
    # HU-16 ext: firma cinema-seat locking (2-minute timeout)
    firmando_por_id   = Column(String(36), nullable=True)
    firmando_desde    = Column(DateTime, nullable=True)
    firma_entregador_url = Column(Text, nullable=True)
    # Firma del solicitante al ENVIAR el lote a Logística (la pone el técnico/jefe
    # que confirma el pedido). Distinta de la firma de recepción (firma_receptor_url).
    firma_solicitante_url   = Column(Text, nullable=True)
    firma_solicitante_fecha = Column(DateTime, nullable=True)
    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime)


class RequerimientoDetalle(Base):
    __tablename__ = "requerimiento_detalle"

    id                = Column(String(36), primary_key=True, default=_uuid)
    requerimiento_id  = Column(String(36), ForeignKey("requerimiento.id"), nullable=False)
    material_id       = Column(String(36), ForeignKey("material.id"),      nullable=True)
    equipo_id         = Column(String(36), ForeignKey("equipo.id"),        nullable=True)   # equipo/herramienta existente (compra del faltante de un préstamo)
    cantidad          = Column(Integer, nullable=False)
    cantidad_aprobada = Column(Integer)
    observacion       = Column(String(255))
    # Motivo categórico del rechazo (solo relevante cuando estado_item='rechazado')
    #   sin_tiempo_compra | no_disponible_catalogo | duplicado | otro
    motivo_rechazo    = Column(String(30), nullable=True)
    nombre_libre      = Column(String(255))   # nombre cuando material_id es None (compra externa)
    unidad_libre      = Column(String(50))
    especificacion    = Column(String(500))
    agregado_por_id   = Column(String(36))    # empleado.id que agregó este ítem al borrador
    # HU-16: decisión de logística por ítem
    #   pendiente | aprobado (sale de stock) | para_compra (ticket) | rechazado
    estado_item       = Column(String(20), nullable=False, default="pendiente")
    # Fase 1 — clasificación capturada al solicitar una compra externa
    #   material | equipo | herramienta  (solo relevante cuando material_id IS NULL)
    tipo_item_compra  = Column(String(20), nullable=True, default="material")
    precio_estimado   = Column(Numeric(12, 2), nullable=True)
