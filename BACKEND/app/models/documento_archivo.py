"""
Archivo centralizado de documentos generados (módulo Gestión de TIC).

Cada PDF/Excel/CSV que el sistema genera pasa (o irá pasando) por
`document_archive_service.archivar(...)`, que deduplica por `identidad`
(identidad lógica = public_id determinístico en Cloudinary con formato
"e-zyro/{empresa_id}/archivo/{modulo}/{slug}") + hash SHA-256:
  - mismo hash  → no re-sube; incrementa `descargas`.
  - hash nuevo  → sobrescribe el MISMO public_id (overwrite) y sube `version`.

Sin FK a usuario: el archivo (y su rastro) sobrevive a borrados de usuarios.
"""
import uuid
from datetime import datetime

from sqlalchemy import BigInteger, Column, DateTime, Index, Integer, String, Text

from app.db.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


class DocumentoArchivo(Base):
    __tablename__ = "documento_archivo"

    id                   = Column(String(36), primary_key=True, default=_uuid)
    nombre               = Column(String(200), nullable=False)
    tipo                 = Column(String(20), nullable=True)   # pdf|excel|csv|export|otro
    modulo_origen        = Column(String(50), nullable=True)
    entidad_tipo         = Column(String(60), nullable=True)
    entidad_id           = Column(String(64), nullable=True)
    identidad            = Column(String(300), nullable=False, unique=True)
    generado_por         = Column(String(36), nullable=True)   # usuario.id | NULL = sistema
    empresa_id           = Column(String(36), nullable=True)
    fecha_creacion       = Column(DateTime, nullable=True, default=datetime.utcnow)
    fecha_actualizacion  = Column(DateTime, nullable=True)
    tamano_bytes         = Column(BigInteger, nullable=True)
    hash_sha256          = Column(String(64), nullable=True)
    cloudinary_public_id = Column(String(300), nullable=True)
    cloudinary_url       = Column(Text, nullable=True)
    version              = Column(Integer, nullable=True, default=1)
    descargas            = Column(Integer, nullable=True, default=0)

    __table_args__ = (
        Index("idx_documento_archivo_modulo_fecha", modulo_origen, fecha_creacion.desc()),
        Index("idx_documento_archivo_tipo", tipo),
    )
