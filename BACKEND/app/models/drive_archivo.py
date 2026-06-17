import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Integer, Text, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class DriveArchivo(Base):
    """Archivo del Drive de empresa (cualquier tipo, en Cloudinary). Sin versiones:
    cada fila es un archivo. `ambito`/`propietario_id` replican los de su carpeta
    (o definen dónde vive si está en la raíz, carpeta_id NULL)."""
    __tablename__ = "drive_archivo"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False)
    carpeta_id          = Column(String(36), ForeignKey("drive_carpeta.id"), nullable=True)
    ambito              = Column(String(20), nullable=False, default="compartido")
    propietario_id      = Column(String(36), ForeignKey("usuario.id"), nullable=True)
    nombre              = Column(String(255), nullable=False)
    descripcion         = Column(String(300), nullable=True)
    url_cloudinary      = Column(Text, nullable=False)
    public_id_cloudinary = Column(String(300), nullable=False)
    recurso_tipo        = Column(String(20), nullable=False, default="raw")  # imagen | pdf | raw
    formato             = Column(String(10), nullable=True)
    bytes               = Column(Integer, nullable=True)
    subido_por_id       = Column(String(36), ForeignKey("usuario.id"), nullable=True)
    created_at          = Column(DateTime, nullable=False, default=datetime.utcnow)
