import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Integer, Numeric, Text, Date, DateTime, ForeignKey, Boolean
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class Epp(Base):
    """Catálogo de Equipos de Protección Personal (stock por empresa)."""
    __tablename__ = "epp"

    id           = Column(String(36), primary_key=True, default=_uuid)
    empresa_id   = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    nombre       = Column(String(200), nullable=False)
    descripcion  = Column(String(500), nullable=True)
    marca_id     = Column(String(36), ForeignKey("marca.id"), nullable=True)
    unidad_id    = Column(String(36), ForeignKey("unidad_medida.id"), nullable=True)
    zona_id      = Column(String(36), ForeignKey("zona.id"), nullable=True)
    stock_actual = Column(Integer, nullable=False, default=0)
    stock_min    = Column(Integer, nullable=False, default=0)
    precio       = Column(Numeric(12, 2), nullable=True)
    imagen_url   = Column(Text, nullable=True)
    activo       = Column(Boolean, nullable=False, default=True)
    created_at   = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at   = Column(DateTime, nullable=True)


class EppEntrega(Base):
    """Cabecera de una entrega de EPP a un empleado (con firma + constancia)."""
    __tablename__ = "epp_entrega"

    id               = Column(String(36), primary_key=True, default=_uuid)
    empresa_id       = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    empleado_id      = Column(String(36), ForeignKey("empleado.id"), nullable=False)  # receptor
    fecha            = Column(Date, nullable=False, default=date.today)
    registrado_por_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    firma_url        = Column(Text, nullable=True)
    pdf_url          = Column(Text, nullable=True)
    observacion      = Column(String(500), nullable=True)
    estado           = Column(String(20), nullable=False, default="registrada")  # registrada|anulada
    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)


class EppEntregaDetalle(Base):
    __tablename__ = "epp_entrega_detalle"

    id          = Column(String(36), primary_key=True, default=_uuid)
    entrega_id  = Column(String(36), ForeignKey("epp_entrega.id"), nullable=False)
    epp_id      = Column(String(36), ForeignKey("epp.id"), nullable=False)
    cantidad    = Column(Integer, nullable=False, default=1)


class EppIngreso(Base):
    """Cabecera de ingreso de stock nuevo de EPP."""
    __tablename__ = "epp_ingreso"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    personal_compro_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    proveedor_id      = Column(String(36), ForeignKey("proveedor.id"), nullable=True)
    fecha_compra      = Column(Date, nullable=False, default=date.today)
    registrado_por_id = Column(String(36), ForeignKey("empleado.id"), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)


class EppIngresoDetalle(Base):
    __tablename__ = "epp_ingreso_detalle"

    id              = Column(String(36), primary_key=True, default=_uuid)
    ingreso_id      = Column(String(36), ForeignKey("epp_ingreso.id"), nullable=False)
    epp_id          = Column(String(36), ForeignKey("epp.id"), nullable=False)
    cantidad        = Column(Integer, nullable=False, default=1)
    precio_unitario = Column(Numeric(12, 2), nullable=True)
