"""
Router: /soporte
Tickets de soporte interno para el equipo de TI.

- Cualquier usuario autenticado crea tickets y ve los suyos.
- El equipo de TI (permiso soporte:ver / soporte:gestionar, p.ej. rol "TI" o
  Administrador) ve todos los de su empresa y los gestiona (cambiar estado,
  responder, asignarse).
"""
from __future__ import annotations

import re
import uuid as _uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import tiene_permiso
from ..db.database import get_db
from ..models.ticket_soporte import TicketSoporte
from ..models.usuario import Usuario

router = APIRouter(prefix="/soporte", tags=["soporte"])


def _puede_ver_todos(db: Session, payload: dict) -> bool:
    """Equipo de TI: puede ver los tickets de toda la empresa."""
    return tiene_permiso(db, payload, "soporte", "ver")


def _puede_gestionar(db: Session, payload: dict) -> bool:
    """Equipo de TI: puede gestionar (cambiar estado / responder) tickets."""
    return tiene_permiso(db, payload, "soporte", "gestionar")

_CATEGORIAS = {"app_movil", "sistema_web", "acceso", "datos", "otro"}
_PRIORIDADES = {"baja", "media", "alta", "urgente"}
_ESTADOS = {"abierto", "en_proceso", "resuelto", "cerrado"}


# ── Schemas ───────────────────────────────────────────────────────────────────

class CrearTicketBody(BaseModel):
    titulo:      str = Field(..., max_length=200)
    descripcion: str
    categoria:   str = "otro"
    prioridad:   str = "media"
    pantalla:    Optional[str] = None
    dispositivo: Optional[str] = None
    adjunto_url: Optional[str] = None


class GestionarTicketBody(BaseModel):
    estado:       Optional[str] = None
    respuesta_ti: Optional[str] = None


class TicketSoporteOut(BaseModel):
    id:             str
    codigo:         str
    titulo:         str
    descripcion:    str
    categoria:      str
    prioridad:      str
    estado:         str
    pantalla:       Optional[str]
    dispositivo:    Optional[str]
    adjunto_url:    Optional[str]
    respuesta_ti:   Optional[str]
    reportado_por:  str
    reportante_nombre: str
    atendido_por:   Optional[str]
    creado_en:      str
    actualizado_en: Optional[str]


# ── Helpers ─────────────────────────────────────────────────────────────────

def _siguiente_codigo(db: Session, empresa_id: str) -> str:
    rows = db.query(TicketSoporte.codigo).filter(
        TicketSoporte.empresa_id == empresa_id,
        TicketSoporte.codigo.ilike("TI-%"),
    ).all()
    max_n = 0
    pat = re.compile(r"^TI-(\d+)$", re.IGNORECASE)
    for (c,) in rows:
        if c:
            m = pat.match(c.strip())
            if m:
                max_n = max(max_n, int(m.group(1)))
    return f"TI-{(max_n + 1):04d}"


def _nombre_usuario(db: Session, usuario_id: str) -> str:
    u = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if not u:
        return "Usuario"
    nombre = f"{u.nombre or ''} {u.apellido or ''}".strip()
    return nombre or (u.username or "Usuario")


def _out(db: Session, t: TicketSoporte) -> TicketSoporteOut:
    return TicketSoporteOut(
        id=str(t.id),
        codigo=t.codigo,
        titulo=t.titulo,
        descripcion=t.descripcion,
        categoria=t.categoria,
        prioridad=t.prioridad,
        estado=t.estado,
        pantalla=t.pantalla,
        dispositivo=t.dispositivo,
        adjunto_url=t.adjunto_url,
        respuesta_ti=t.respuesta_ti,
        reportado_por=str(t.reportado_por),
        reportante_nombre=_nombre_usuario(db, t.reportado_por),
        atendido_por=str(t.atendido_por) if t.atendido_por else None,
        creado_en=t.created_at.isoformat() if t.created_at else "",
        actualizado_en=t.updated_at.isoformat() if t.updated_at else None,
    )


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
def crear_ticket(
    body:    CrearTicketBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    if not body.titulo.strip():
        raise HTTPException(status_code=422, detail="El título es obligatorio")
    if not body.descripcion.strip():
        raise HTTPException(status_code=422, detail="Describe el problema")

    categoria = body.categoria if body.categoria in _CATEGORIAS else "otro"
    prioridad = body.prioridad if body.prioridad in _PRIORIDADES else "media"

    t = TicketSoporte(
        id            = str(_uuid.uuid4()),
        empresa_id    = empresa_id,
        codigo        = _siguiente_codigo(db, empresa_id),
        reportado_por = usuario_id,
        titulo        = body.titulo.strip(),
        descripcion   = body.descripcion.strip(),
        categoria     = categoria,
        prioridad     = prioridad,
        estado        = "abierto",
        pantalla      = body.pantalla,
        dispositivo   = body.dispositivo,
        adjunto_url   = body.adjunto_url,
        created_at    = datetime.utcnow(),
    )
    db.add(t)
    db.commit()
    db.refresh(t)
    return _out(db, t)


@router.get("", response_model=List[TicketSoporteOut])
def listar_tickets(
    estado:  str = "",
    alcance: str = "mios",  # mios | todos (todos solo para TI/admin)
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    q = db.query(TicketSoporte).filter(TicketSoporte.empresa_id == empresa_id)

    # 'todos' solo lo puede usar el equipo de TI; el resto ve los suyos.
    if alcance == "todos" and _puede_ver_todos(db, payload):
        pass
    else:
        q = q.filter(TicketSoporte.reportado_por == usuario_id)

    if estado and estado in _ESTADOS:
        q = q.filter(TicketSoporte.estado == estado)

    rows = q.order_by(TicketSoporte.created_at.desc()).all()
    return [_out(db, t) for t in rows]


@router.get("/{ticket_id}", response_model=TicketSoporteOut)
def detalle_ticket(
    ticket_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    t = db.query(TicketSoporte).filter(
        TicketSoporte.id == ticket_id,
        TicketSoporte.empresa_id == empresa_id,
    ).first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    # Solo el reportante o el equipo de TI pueden verlo
    if str(t.reportado_por) != str(usuario_id) and not _puede_ver_todos(db, payload):
        raise HTTPException(status_code=403, detail="Sin acceso a este ticket")
    return _out(db, t)


@router.patch("/{ticket_id}", response_model=TicketSoporteOut)
def gestionar_ticket(
    ticket_id: str,
    body:      GestionarTicketBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """Gestión por el equipo de TI: cambiar estado y/o responder."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    if not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI gestiona tickets")

    t = db.query(TicketSoporte).filter(
        TicketSoporte.id == ticket_id,
        TicketSoporte.empresa_id == empresa_id,
    ).first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")

    if body.estado is not None:
        if body.estado not in _ESTADOS:
            raise HTTPException(status_code=422, detail="Estado inválido")
        t.estado = body.estado
    if body.respuesta_ti is not None:
        t.respuesta_ti = body.respuesta_ti

    t.atendido_por = usuario_id
    t.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(t)
    return _out(db, t)
