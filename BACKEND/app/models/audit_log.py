"""
Audit log de EVENTOS HTTP/seguridad (módulo Gestión de TIC).

Complementa a `auditoria` (que ya captura los CRUD vía listener ORM): aquí se
registran los eventos que el ORM no ve — login/logout, intentos fallidos,
descargas/exportaciones, permisos denegados (403), rate limiting, backups y
alertas de seguridad.

Sin FK a usuario: usuario.id es uuid nativo en BD (una FK varchar→uuid falla)
y además este rastro debe sobrevivir aunque el usuario se elimine.
"""
import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, Index, String
from sqlalchemy.dialects.postgresql import JSONB

from app.db.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


class AuditLog(Base):
    __tablename__ = "audit_log"

    id             = Column(String(36), primary_key=True, default=_uuid)
    fecha          = Column(DateTime, nullable=False, default=datetime.utcnow)
    usuario_id     = Column(String(36), nullable=True)
    usuario_nombre = Column(String(150), nullable=True)
    rol            = Column(String(50), nullable=True)
    empresa_id     = Column(String(36), nullable=True)
    # LOGIN | LOGIN_FALLIDO | LOGOUT | DOWNLOAD | EXPORT | PERMISSION_DENIED
    # | RATE_LIMITED | BACKUP | SECURITY | VIEW_SENSITIVE
    accion         = Column(String(30), nullable=False)
    entidad        = Column(String(60), nullable=True)
    entidad_id     = Column(String(64), nullable=True)
    metodo_http    = Column(String(8), nullable=True)
    ruta           = Column(String(300), nullable=True)
    ip             = Column(String(45), nullable=True)
    user_agent     = Column(String(255), nullable=True)
    resultado      = Column(String(10), nullable=False, default="exito")  # exito|fallo|denegado
    detalle        = Column(JSONB, nullable=True)

    __table_args__ = (
        Index("idx_audit_log_fecha", fecha.desc()),
        Index("idx_audit_log_accion_fecha", accion, fecha.desc()),
        Index("idx_audit_log_usuario_fecha", usuario_id, fecha.desc()),
        Index("idx_audit_log_ip_fecha", ip, fecha.desc()),
    )
