import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Date, Text
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class DocumentoSst(Base):
    """Repositorio de documentos de cumplimiento / SST.

    Solo ALMACENAMIENTO + organización (no se generan aquí): subir el archivo,
    clasificarlo por (cliente, tipo), consultarlo, controlar su vencimiento y
    descargarlo. `tipo` distingue homologación / ATS / PETAR / otro, de modo que
    agregar un tipo nuevo no requiere migración.

    Sin ForeignKey a nivel BD a propósito: empresa.id / cliente.id son uuid
    nativo en producción y un FK varchar(36)->uuid rompería Base.metadata
    .create_all al crear esta tabla. La integridad se garantiza por aplicación
    (siempre se filtra por empresa_id del token).
    """
    __tablename__ = "documento_sst"

    id                = Column(String(36), primary_key=True, default=_uuid)
    empresa_id        = Column(String(36), nullable=False, index=True)
    cliente_id        = Column(String(36), nullable=True, index=True)
    # homologacion | ats | petar | otro
    tipo              = Column(String(30), nullable=False, default="homologacion")
    titulo            = Column(String(200), nullable=False)
    entidad_emisora   = Column(String(200), nullable=True)
    codigo            = Column(String(100), nullable=True)
    fecha_emision     = Column(Date, nullable=True)
    fecha_vencimiento = Column(Date, nullable=True)
    archivo_url       = Column(Text, nullable=True)
    archivo_public_id = Column(String(300), nullable=True)
    nombre_archivo    = Column(String(255), nullable=True)
    formato           = Column(String(10), nullable=True)
    observaciones     = Column(Text, nullable=True)
    creado_por_id     = Column(String(36), nullable=True)
    created_at        = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at        = Column(DateTime, nullable=False, default=datetime.utcnow,
                               onupdate=datetime.utcnow)
