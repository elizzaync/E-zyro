import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, Boolean, Integer, Date, Text
from app.db.database import Base

def _uuid():
    return str(uuid.uuid4())

class Equipo(Base):
    __tablename__ = "equipo"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    tipo_equipo_id   = Column(String(36), ForeignKey("tipo_equipo.id"), nullable=True)
    proyecto_id      = Column(String(36), ForeignKey("proyecto.id"), nullable=True)
    cliente_id       = Column(String(36), ForeignKey("cliente.id"), nullable=True)
    tipo_asignacion  = Column(String(20), nullable=True)   # activo_cliente | proyecto
    nombre           = Column(String(150), nullable=False)
    codigo           = Column(String(50), nullable=True)
    modelo           = Column(String(100), nullable=True)
    marca            = Column(String(100), nullable=True)
    numero_serie     = Column(String(100), nullable=True)
    ubicacion        = Column(String(200), nullable=True)
    # FKs a catálogos de marca/modelo. Las columnas `marca` y `modelo` se
    # mantienen como caché denormalizada para listados rápidos.
    marca_id         = Column(String(36), ForeignKey("marca.id"), nullable=True)
    modelo_id        = Column(String(36), ForeignKey("modelo_equipo.id"), nullable=True)
    # FK al almacén donde reside el equipo/herramienta
    almacen_id       = Column(String(36), ForeignKey("almacen.id"), nullable=True)
    estado           = Column(String(20), nullable=False, default="operativo")  # operativo|en_mantenimiento|fuera_de_servicio|baja

    # ── Logística (HU-15) ──────────────────────────────────────────────────
    # En el sistema anterior todo iba en la tabla `articulos`. Aquí separamos:
    #   clase = 'equipo'      → activo que normalmente requiere mantenimiento
    #   clase = 'herramienta' → herramienta manual (la mayoría no lo requiere)
    clase                       = Column(String(20), nullable=False, default="equipo")
    cantidad                    = Column(Integer,    nullable=False, default=1)
    tipo                        = Column(String(120), nullable=True)   # familia/tipo libre (ej "Instrumento de medición")
    fecha_adquisicion           = Column(Date,       nullable=True)
    ficha_tecnica               = Column(Text,       nullable=True)
    requiere_mantenimiento      = Column(Boolean,    nullable=False, default=False)
    frecuencia_mantenimiento    = Column(String(20), nullable=False, default="ninguno")  # ninguno|mensual|trimestral|semestral|anual
    proxima_fecha_mantenimiento = Column(Date,       nullable=True)

    # ── Estado operativo / averiados (Fase 3) ──────────────────────────────
    cantidad_inoperativa = Column(Integer,    nullable=False, default=0)
    estado_operativo     = Column(String(20), nullable=True, default="operativo")  # operativo|parcial|inoperativo

    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True)
