"""
Auditoría de backups del sistema (módulo Backups · Gestión de TIC).
Cada corrida (automática u horaria silenciosa, o manual disparada por un
usuario de Soporte) deja una fila con su rastro completo: quién, cuándo,
qué contenido, tamaño, hash de integridad, ubicación del artefacto y estado.

El artefacto vive en BACKUP_DIR (variable de entorno; en Railway debe apuntar
a un volumen persistente, en cualquier otro servidor a un directorio durable).
La copia durable de largo plazo es la que Soporte descarga a su disco externo.
"""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, BigInteger, Text, Date, DateTime
from app.db.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


class BackupJob(Base):
    __tablename__ = "backup_job"

    id            = Column(String(36), primary_key=True, default=_uuid)
    tipo          = Column(String(10), nullable=False)                    # auto | manual
    # bd_horario | bd_diario | archivos_incremental | archivos_full | reconciliacion
    nivel         = Column(String(25), nullable=False)
    # Sin FK: usuario.id es uuid nativo en la BD y este es un rastro de
    # auditoría que debe sobrevivir aunque el usuario desaparezca.
    disparado_por = Column(String(36), nullable=True)                     # usuario.id | NULL = sistema
    fecha_inicio  = Column(DateTime, nullable=False, default=datetime.utcnow)
    fecha_fin     = Column(DateTime, nullable=True)
    estado        = Column(String(12), nullable=False, default="pendiente")  # pendiente|en_proceso|completado|fallido
    contenido     = Column(String(60), nullable=False)                    # csv: bd,pdfs,cloudinary
    tamano_bytes  = Column(BigInteger, nullable=True)
    ubicacion     = Column(Text, nullable=True)                           # ruta del artefacto en BACKUP_DIR
    hash_sha256   = Column(String(64), nullable=True)
    error_detalle = Column(Text, nullable=True)
    retencion     = Column(String(10), nullable=True)                     # horario|diario|semanal|mensual
    expira_en     = Column(Date, nullable=True)                           # rotación GFS automática
