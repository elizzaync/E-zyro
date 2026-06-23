import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Numeric, Boolean, Date, DateTime, Text, ForeignKey
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class CriterioEvaluacion(Base):
    __tablename__ = "criterio_evaluacion"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    # Tipo de evaluación al que pertenece el criterio: rrhh|jefe_directo|companero
    tipo        = Column(String(20), nullable=False, default="rrhh")
    nombre      = Column(String(150), nullable=False)
    descripcion = Column(String(255), nullable=True)
    peso        = Column(Numeric(5, 2), nullable=False)
    activo      = Column(Boolean, nullable=False, default=True)


class PlantillaEvaluacion(Base):
    """Modelo reutilizable de evaluación: agrupa criterios con sus pesos."""
    __tablename__ = "plantilla_evaluacion"

    id          = Column(String(36), primary_key=True, default=_uuid)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre      = Column(String(150), nullable=False)
    descripcion = Column(Text, nullable=True)
    tipo        = Column(String(20), nullable=False, default="rrhh")
    activo      = Column(Boolean, nullable=False, default=True)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at  = Column(DateTime, nullable=True)


class PlantillaEvaluacionCriterio(Base):
    """Criterio incluido en una plantilla, con peso y orden opcionales."""
    __tablename__ = "plantilla_evaluacion_criterio"

    id           = Column(String(36), primary_key=True, default=_uuid)
    plantilla_id = Column(String(36), ForeignKey("plantilla_evaluacion.id", ondelete="CASCADE"), nullable=False)
    criterio_id  = Column(String(36), ForeignKey("criterio_evaluacion.id"), nullable=False)
    peso         = Column(Numeric(5, 2), nullable=True)  # None = usa el peso original del criterio
    orden        = Column(Integer, nullable=False, default=0)


class Evaluacion(Base):
    __tablename__ = "evaluacion"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id      = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    evaluador_id     = Column(String(36), ForeignKey("empleado.id"), nullable=False)
    plantilla_id     = Column(String(36), ForeignKey("plantilla_evaluacion.id"), nullable=True)
    # Tipo de evaluación: rrhh|jefe_directo|companero
    tipo             = Column(String(20), nullable=False, default="rrhh")
    periodo          = Column(String(50), nullable=False)
    # borrador → evaluador llena directo; asignada → empleado completa; completada → finalizada
    estado           = Column(String(30), nullable=False, default="borrador")
    fecha            = Column(Date, nullable=False)
    notas_evaluador  = Column(Text, nullable=True)
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)


class DetalleEvaluacion(Base):
    __tablename__ = "detalle_evaluacion"

    id            = Column(String(36), primary_key=True, default=_uuid)
    evaluacion_id = Column(String(36), ForeignKey("evaluacion.id"), nullable=False)
    criterio_id   = Column(String(36), ForeignKey("criterio_evaluacion.id"), nullable=False)
    puntaje       = Column(Integer, nullable=False)   # 1-10
    comentario    = Column(Text, nullable=True)


class CalificacionCliente(Base):
    __tablename__ = "calificacion_cliente"

    id          = Column(String(36), primary_key=True, default=_uuid)
    cliente_id  = Column(String(36), ForeignKey("cliente.id"), nullable=False)
    proyecto_id = Column(String(36), ForeignKey("proyecto.id"), nullable=False)
    empresa_id  = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    puntaje     = Column(Integer, nullable=False)   # 1-5
    comentario  = Column(Text, nullable=True)
    fecha       = Column(Date, nullable=False)
    created_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
