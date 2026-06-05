import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, Boolean, DateTime, ForeignKey
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class FirmaEvento(Base):
    """
    Ledger de seguridad de firmas (capas 1-3 del modelo de trazabilidad).

    Registra CADA acto de firma — sea dibujada, subida de galería o reutilizada
    de la firma guardada — con su procedencia verificable:

    - Identidad derivada del JWT (firmante_id / firmante_usuario_id), nunca de
      la imagen → copiar una firma no otorga identidad.
    - Huellas de la imagen: `sha256` (exacta) y `phash` (perceptual) → permiten
      detectar reutilización de la firma de otro (mismo dibujo, distinto autor).
    - `sello_hmac`: HMAC-SHA256 server-side sobre los campos canónicos →
      tamper-evidence: nadie altera "quién firmó qué/cuándo" sin romper el sello.

    Tabla append-only: no se actualiza ni borra; cada firma es un evento nuevo.
    """
    __tablename__ = "firma_evento"

    id                  = Column(String(36), primary_key=True, default=_uuid)
    empresa_id          = Column(String(36), ForeignKey("empresa.id"), nullable=False, index=True)
    # Identidad del firmante tomada del token autenticado (no del body)
    firmante_id         = Column(String(36), ForeignKey("empleado.id"), nullable=True, index=True)
    firmante_usuario_id = Column(String(36), ForeignKey("usuario.id"),  nullable=True)
    # Qué se firmó
    entidad_tipo        = Column(String(50),  nullable=False)              # 'requerimiento', 'prestamo', …
    entidad_id          = Column(String(36),  nullable=False, index=True)
    rol_firma           = Column(String(30),  nullable=True)               # 'receptor' | 'entregador' | …
    metodo              = Column(String(20),  nullable=False, default="desconocido")  # incrustada|guardada|desconocido
    # Huellas de la imagen (la imagen NO se guarda aquí, solo sus hashes)
    sha256              = Column(String(64),  nullable=True, index=True)   # hash exacto de los bytes
    phash               = Column(String(32),  nullable=True, index=True)   # dHash perceptual (64 bits → 16 hex)
    firma_ref           = Column(Text,        nullable=True)               # url de firma guardada / nota (sin base64)
    # Contexto de la petición
    ip                  = Column(String(45),  nullable=True)
    user_agent          = Column(String(500), nullable=True)
    # Sello de integridad
    sello_hmac          = Column(String(64),  nullable=True)               # HMAC-SHA256 hex sobre campos canónicos
    # Detección de reutilización
    sospechoso          = Column(Boolean,     nullable=False, default=False, index=True)
    motivo_sospecha     = Column(Text,        nullable=True)
    created_at          = Column(DateTime,    nullable=False, default=datetime.utcnow)
