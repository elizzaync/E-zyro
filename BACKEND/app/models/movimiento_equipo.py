import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class MovimientoEquipo(Base):
    """Bitácora por unidad de equipo/herramienta (activos propios serializados).

    A diferencia de `movimiento_inventario` (materiales, por cantidad), aquí cada
    fila es un EVENTO del ciclo de vida de UNA unidad: alta, cambio de estado,
    transferencia de almacén, asignación a servicio, retorno, mantenimiento, baja.
    No lleva costo: los equipos son activos, no inventario de consumo.
    """
    __tablename__ = "movimiento_equipo"

    id              = Column(String(36), primary_key=True, default=_uuid)
    empresa_id      = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    equipo_id       = Column(String(36), ForeignKey("equipo.id"), nullable=False)
    tipo            = Column(String(20), nullable=False)  # alta|estado|transferencia|asignacion|retorno|mantenimiento|baja
    detalle         = Column(String(255), nullable=True)  # descripción (p.ej. "operativo → en_mantenimiento")
    referencia_id   = Column(String(36), nullable=True)
    referencia_tipo = Column(String(30), nullable=True)
    responsable_id  = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    fecha           = Column(DateTime, nullable=False, default=datetime.utcnow)
    created_at      = Column(DateTime, nullable=False, default=datetime.utcnow)
