"""
Préstamo de equipos y herramientas asociado a un proyecto_servicio.
A diferencia de los materiales (Requerimiento), los equipos/herramientas no se
consumen: se entregan, se devuelven y la diferencia (cantidad_perdida) se contabiliza.
"""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, DateTime, ForeignKey
from app.db.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


class Prestamo(Base):
    __tablename__ = "prestamo"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    empresa_id           = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    proyecto_servicio_id = Column(String(36), ForeignKey("proyecto_servicio.id"), nullable=False)
    solicitante_id       = Column(String(36), ForeignKey("empleado.id"), nullable=False)

    # Estados: solicitado | por_recibir | entregado | devuelto | confirmado | rechazado
    #   por_recibir = logística despachó y firmó (entregador); falta firma de recepción del equipo
    estado               = Column(String(20), nullable=False, default="solicitado")

    observacion              = Column(Text, nullable=True)   # del técnico al solicitar
    observacion_logistico    = Column(Text, nullable=True)   # del log al rechazar/confirmar

    entregado_por_id     = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    devuelto_por_id      = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    confirmado_por_id    = Column(String(36), ForeignKey("empleado.id"), nullable=True)

    firma_receptor_url   = Column(Text, nullable=True)   # firma del técnico al recibir el préstamo
    firma_entregador_url = Column(Text, nullable=True)   # firma de logística al despachar
    firma_solicitante_url   = Column(Text, nullable=True)   # firma del solicitante al pedir el lote
    firma_solicitante_fecha = Column(DateTime, nullable=True)

    # Cinema-seat lock para la firma de recepción (anti-duplicidad entre técnicos)
    firmando_por_id      = Column(String(36), nullable=True)   # usuario_id que tiene el lock
    firmando_desde       = Column(DateTime, nullable=True)     # inicio del lock (timeout 2 min)

    fecha_solicitud      = Column(DateTime, nullable=False, default=datetime.utcnow)
    fecha_entrega        = Column(DateTime, nullable=True)
    fecha_devolucion     = Column(DateTime, nullable=True)
    fecha_confirmacion   = Column(DateTime, nullable=True)

    created_at           = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at           = Column(DateTime, nullable=True)


class PrestamoItem(Base):
    __tablename__ = "prestamo_item"

    id          = Column(String(36), primary_key=True, default=_uuid)
    prestamo_id = Column(String(36), ForeignKey("prestamo.id"), nullable=False)
    equipo_id   = Column(String(36), ForeignKey("equipo.id"), nullable=False)

    cantidad_solicitada = Column(Integer, nullable=False, default=1)
    cantidad_entregada  = Column(Integer, nullable=True)     # log llena al entregar
    cantidad_devuelta   = Column(Integer, nullable=True)     # técnico llena al devolver
    cantidad_perdida    = Column(Integer, nullable=False, default=0)  # entregada - devuelta

    observacion         = Column(Text, nullable=True)        # nota libre por item
