import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UniqueConstraint
from app.db.database import Base


def _uuid():
    return str(uuid.uuid4())


class PreferenciaNotificacion(Base):
    """Preferencia por usuario y categoría (grupo) de notificación.

    Categorías (grupos): general | almuerzo | alertas | comunicados | servicios | chat.
    Si no existe fila para (usuario, categoria) se aplica el default del código
    (todo ON salvo 'chat', que es OFF por defecto).
    """
    __tablename__ = "preferencia_notificacion"

    id         = Column(String(36), primary_key=True, default=_uuid)
    usuario_id = Column(String(36), ForeignKey("usuario.id"), nullable=False, index=True)
    categoria  = Column(String(30), nullable=False)
    activo     = Column(Boolean, nullable=False, default=True)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("usuario_id", "categoria", name="uq_pref_notif_usuario_cat"),
    )
