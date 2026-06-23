import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, Boolean, Integer, Date, Text, Numeric
from sqlalchemy.dialects.postgresql import JSONB
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
    ubicacion        = Column(String(200), nullable=True)  # legacy texto (caché)
    # FKs a la jerarquía geográfica (ubicacion → zona → area). Reemplazan el
    # texto libre `ubicacion`, que se conserva como caché denormalizada.
    ubicacion_id     = Column(String(36), ForeignKey("ubicacion.id"), nullable=True)
    zona_id          = Column(String(36), ForeignKey("zona.id"),      nullable=True)
    area_id          = Column(String(36), ForeignKey("area.id"),      nullable=True)
    # FKs a catálogos de marca/modelo. Las columnas `marca` y `modelo` se
    # mantienen como caché denormalizada para listados rápidos.
    marca_id         = Column(String(36), ForeignKey("marca.id"), nullable=True)
    modelo_id        = Column(String(36), ForeignKey("modelo_equipo.id"), nullable=True)
    # FK al almacén donde reside el equipo/herramienta
    almacen_id           = Column(String(36), ForeignKey("almacen.id"), nullable=True)
    # Categoría general de inventario (herramienta de mano, equipo eléctrico, etc.)
    # Distinta de tipo_equipo_id que es exclusivo del módulo de Equipos Intervenidos.
    categoria_equipo_id  = Column(String(36), ForeignKey("categoria_equipo.id"), nullable=True)
    estado               = Column(String(20), nullable=False, default="operativo")  # operativo|en_mantenimiento|fuera_de_servicio|baja

    # ── Logística (HU-15) ──────────────────────────────────────────────────
    # Taxonomía de activos propios de la empresa (3 clases):
    #   clase = 'equipo'             → herramienta tecnológica/eléctrica que suele
    #                                  requerir calibración o mantenimiento
    #                                  (multímetro, pinza amperimétrica, aspiradora,
    #                                   taladro, amoladora, cámara termográfica…)
    #   clase = 'herramienta'        → herramienta manual no tecnológica; rara vez
    #                                  tiene mantenimiento, pero puede llegar a
    #                                  tenerlo (alicate, martillo, llave,
    #                                   destornillador dieléctrico…) — por eso
    #                                  comparte tabla con 'equipo'
    #   clase = 'equipo_tecnologico' → activo TI / de cómputo (PC, laptop,
    #                                  impresora, monitor, cámara IP, router…)
    # NOTA: distinto de `equipo_intervenido` (equipos DE CLIENTES atendidos en
    # servicio), que vive en su propia tabla y no es inventario propio.
    clase                       = Column(String(20), nullable=False, default="equipo")
    cantidad                    = Column(Integer,    nullable=False, default=1)
    tipo                        = Column(String(120), nullable=True)   # familia/tipo libre (ej "Instrumento de medición")
    fecha_adquisicion           = Column(Date,       nullable=True)
    ficha_tecnica               = Column(Text,       nullable=True)
    requiere_mantenimiento      = Column(Boolean,    nullable=False, default=False)
    frecuencia_mantenimiento    = Column(String(20), nullable=False, default="ninguno")  # ninguno|mensual|trimestral|semestral|anual
    proxima_fecha_mantenimiento = Column(Date,       nullable=True)

    # ── Estado operativo / averiados (Fase 3) ──────────────────────────────
    cantidad_inoperativa = Column(Integer, nullable=False, default=0)
    # estado_operativo eliminado — era redundante con `estado`; columna dropeada en migración.

    # ── Ingreso Directo: specs flexibles + datos de compra/asignación ───────
    # `atributos` guarda los campos específicos por tipo (procesador, RAM,
    # almacenamiento, SO, IP, MAC para equipo_tecnologico…) sin migraciones.
    atributos        = Column(JSONB,         nullable=True)
    asignado_a       = Column(String(200),   nullable=True)   # usuario/responsable al que se asigna
    proveedor        = Column(String(200),   nullable=True)
    precio_compra    = Column(Numeric(12, 2), nullable=True)
    fecha_garantia   = Column(Date,          nullable=True)
    imagen_url       = Column(Text,          nullable=True)
    observaciones    = Column(Text,          nullable=True)

    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at       = Column(DateTime, nullable=True)
