"""
Biblioteca de Formatos (Documentos normados de la empresa).

Repositorio de formatos PDF oficiales (ATS, PETAR, checklists, SCRT, etc.)
con versionado inmutable: un formato NUNCA se elimina; cada actualización
crea una fila nueva en `formato_documento_version` y avanza `version_actual`.
Toda alta/actualización/descarga queda registrada en audit_log (trazabilidad).

IDs uuid como String(36) y SIN FK física a usuario/empresa (patrón
ticket_soporte): evita el choque VARCHAR(36) ↔ uuid de las PK reales en
producción y deja que Base.metadata.create_all cree las tablas.
"""
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Integer, String, Text

from app.db.database import Base


class FormatoDocumento(Base):
    __tablename__ = "formato_documento"

    id            = Column(String(36), primary_key=True, index=True)
    empresa_id    = Column(String(36), nullable=False, index=True)
    nombre        = Column(String(150), nullable=False)
    tipo_formato  = Column(String(50), nullable=True)     # SST / Operaciones / RRHH / ...
    version_actual = Column(Integer, nullable=False, default=1)
    activo        = Column(Boolean, nullable=False, default=True)

    creado_por_id      = Column(String(36), nullable=True)
    actualizado_por_id = Column(String(36), nullable=True)
    created_at    = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at    = Column(DateTime, nullable=True)


class FormatoDocumentoVersion(Base):
    __tablename__ = "formato_documento_version"

    id             = Column(String(36), primary_key=True, index=True)
    formato_id     = Column(String(36), nullable=False, index=True)
    numero_version = Column(Integer, nullable=False)

    archivo_url       = Column(String(500), nullable=False)
    archivo_public_id = Column(String(300), nullable=True)
    nombre_archivo    = Column(String(255), nullable=True)
    tamano_bytes      = Column(Integer, nullable=True)

    nota   = Column(Text, nullable=True)            # motivo del cambio / observación
    origen = Column(String(30), nullable=False, default="sistema")  # sistema | erp_legacy

    subido_por_id     = Column(String(36), nullable=True)
    subido_por_nombre = Column(String(150), nullable=True)
    created_at        = Column(DateTime, default=datetime.utcnow, nullable=False)
