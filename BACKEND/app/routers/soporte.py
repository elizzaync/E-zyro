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
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import tiene_permiso
from ..db.database import get_db
from ..models.ticket_soporte import TicketSoporte
from ..models.ticket_actividad import TicketActividad
from ..models.usuario import Usuario
from ..services.cloudinary_service import subir_e_indexar
from ..services.cloudinary_paths import carpeta_soporte

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
# Tipos de actividad del timeline. 'tomado'/'cambio_estado' los genera el sistema;
# 'comentario'/'avance'/'solucion' los crea el usuario.
_TIPOS_ACTIVIDAD = {"comentario", "avance", "solucion", "cambio_estado", "tomado"}


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
    atendido_por_nombre: Optional[str]
    creado_en:      str
    actualizado_en: Optional[str]


class ActividadOut(BaseModel):
    id:           str
    tipo:         str
    texto:        Optional[str]
    adjunto_url:  Optional[str]
    es_solucion:  bool
    version_solucion: Optional[int]
    autor_id:     str
    autor_nombre: str
    creado_en:    str


class CrearActividadBody(BaseModel):
    tipo:           str = "comentario"
    texto:          Optional[str] = None
    es_solucion:    bool = False
    # Imagen opcional (captura del avance/error) en base64; se sube a Cloudinary.
    adjunto_base64: Optional[str] = None


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
        atendido_por_nombre=_nombre_usuario(db, t.atendido_por) if t.atendido_por else None,
        creado_en=t.created_at.isoformat() if t.created_at else "",
        actualizado_en=t.updated_at.isoformat() if t.updated_at else None,
    )


def _act_out(db: Session, a: TicketActividad) -> ActividadOut:
    return ActividadOut(
        id=str(a.id),
        tipo=a.tipo,
        texto=a.texto,
        adjunto_url=a.adjunto_url,
        es_solucion=bool(a.es_solucion),
        version_solucion=a.version_solucion,
        autor_id=str(a.autor_id),
        autor_nombre=_nombre_usuario(db, a.autor_id),
        creado_en=a.created_at.isoformat() if a.created_at else "",
    )


def _ticket_visible_o_404(db: Session, payload: dict, ticket_id: str) -> TicketSoporte:
    """Devuelve el ticket si el usuario puede verlo (reportante o equipo de TI)."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    t = db.query(TicketSoporte).filter(
        TicketSoporte.id == ticket_id,
        TicketSoporte.empresa_id == empresa_id,
    ).first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    if str(t.reportado_por) != str(usuario_id) and not _puede_ver_todos(db, payload):
        raise HTTPException(status_code=403, detail="Sin acceso a este ticket")
    return t


def _registrar_actividad(
    db: Session, *, empresa_id: str, ticket_id: str, autor_id: str,
    tipo: str, texto: Optional[str] = None, adjunto_url: Optional[str] = None,
    es_solucion: bool = False, version_solucion: Optional[int] = None,
) -> TicketActividad:
    a = TicketActividad(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        ticket_id=ticket_id,
        autor_id=autor_id,
        tipo=tipo,
        texto=texto,
        adjunto_url=adjunto_url,
        es_solucion=es_solucion,
        version_solucion=version_solucion,
        created_at=datetime.utcnow(),
    )
    db.add(a)
    return a


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

    # Avisar al equipo de soporte (quienes pueden gestionar tickets).
    try:
        from ..services.fcm_service import notificar_usuario
        from ..core.permisos import usuarios_con_permiso
        soporte = usuarios_con_permiso(db, empresa_id, "soporte", "gestionar")
        autor = _nombre_usuario(db, usuario_id)
        titulo = f"Nuevo ticket {t.codigo}"
        mensaje = f"{autor} reportó: {t.titulo} (prioridad {t.prioridad})."
        for uid in soporte:
            if str(uid) == str(usuario_id):
                continue  # no notificar al propio autor si es de TI
            notificar_usuario(
                db, empresa_id=empresa_id, usuario_id=str(uid),
                titulo=titulo, mensaje=mensaje,
                tipo="info", categoria="soporte",
                referencia_id=str(t.id), referencia_tabla="ticket_soporte",
            )
        db.commit()
    except Exception:
        db.rollback()

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

    estado_anterior = t.estado
    if body.estado is not None:
        if body.estado not in _ESTADOS:
            raise HTTPException(status_code=422, detail="Estado inválido")
        t.estado = body.estado
    if body.respuesta_ti is not None:
        t.respuesta_ti = body.respuesta_ti

    t.atendido_por = usuario_id
    t.updated_at = datetime.utcnow()

    # Registrar el cambio de estado en el timeline para trazabilidad.
    if body.estado is not None and body.estado != estado_anterior:
        _registrar_actividad(
            db, empresa_id=empresa_id, ticket_id=t.id, autor_id=usuario_id,
            tipo="cambio_estado",
            texto=f"Estado: {estado_anterior} → {body.estado}",
        )

    db.commit()
    db.refresh(t)
    return _out(db, t)


# ── Tomar / asignarse el ticket ───────────────────────────────────────────────

@router.post("/{ticket_id}/tomar", response_model=TicketSoporteOut)
def tomar_ticket(
    ticket_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """Cualquier miembro de TI se asigna el ticket para atenderlo.

    Si estaba 'abierto' pasa a 'en_proceso'. Permite reasignación (otro TI puede
    tomarlo) y deja constancia en el timeline.
    """
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    if not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI puede tomar tickets")

    t = db.query(TicketSoporte).filter(
        TicketSoporte.id == ticket_id,
        TicketSoporte.empresa_id == empresa_id,
    ).first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")

    ya_era_mio = str(t.atendido_por) == str(usuario_id)
    t.atendido_por = usuario_id
    if t.estado == "abierto":
        t.estado = "en_proceso"
    t.updated_at = datetime.utcnow()

    if not ya_era_mio:
        _registrar_actividad(
            db, empresa_id=empresa_id, ticket_id=t.id, autor_id=usuario_id,
            tipo="tomado", texto="Tomó el ticket para atenderlo",
        )

    db.commit()
    db.refresh(t)

    # Avisar al reportante que su ticket está siendo atendido.
    if not ya_era_mio and str(t.reportado_por) != str(usuario_id):
        try:
            from ..services.fcm_service import notificar_usuario
            tecnico = _nombre_usuario(db, usuario_id)
            notificar_usuario(
                db, empresa_id=empresa_id, usuario_id=str(t.reportado_por),
                titulo=f"Ticket {t.codigo} en proceso",
                mensaje=f"{tecnico} tomó tu ticket '{t.titulo}' y lo está atendiendo.",
                tipo="info", categoria="soporte",
                referencia_id=str(t.id), referencia_tabla="ticket_soporte",
            )
            db.commit()
        except Exception:
            db.rollback()
    return _out(db, t)


# ── Actividades (timeline / soluciones versionadas) ───────────────────────────

@router.get("/{ticket_id}/actividades", response_model=List[ActividadOut])
def listar_actividades(
    ticket_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    _ticket_visible_o_404(db, payload, ticket_id)
    rows = (
        db.query(TicketActividad)
        .filter(TicketActividad.ticket_id == ticket_id)
        .order_by(TicketActividad.created_at.asc())
        .all()
    )
    return [_act_out(db, a) for a in rows]


@router.post("/{ticket_id}/actividades", response_model=ActividadOut, status_code=status.HTTP_201_CREATED)
def crear_actividad(
    ticket_id: str,
    body:      CrearActividadBody,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """Agrega una entrada al timeline: comentario, avance o solución.

    - El reportante y el equipo de TI pueden comentar.
    - Marcar 'solución' (es_solucion) solo lo hace el equipo de TI; cada solución
      se versiona automáticamente (1, 2, 3…) para llevar el control de versiones.
    - Acepta una imagen opcional (base64) que se sube a Cloudinary como adjunto.
    """
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    t = _ticket_visible_o_404(db, payload, ticket_id)

    tipo = body.tipo if body.tipo in _TIPOS_ACTIVIDAD else "comentario"
    # Los tipos de sistema no se crean manualmente.
    if tipo in ("tomado", "cambio_estado"):
        tipo = "comentario"

    es_solucion = bool(body.es_solucion) or tipo == "solucion"
    if es_solucion and not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI registra soluciones")
    if es_solucion:
        tipo = "solucion"

    texto = (body.texto or "").strip() or None
    if not texto and not body.adjunto_base64:
        raise HTTPException(status_code=422, detail="Escribe un texto o adjunta una imagen")

    # Versionado de soluciones: siguiente número correlativo para este ticket.
    version_solucion = None
    if es_solucion:
        max_v = (
            db.query(func.max(TicketActividad.version_solucion))
            .filter(
                TicketActividad.ticket_id == ticket_id,
                TicketActividad.es_solucion.is_(True),
            )
            .scalar()
        )
        version_solucion = (max_v or 0) + 1

    adjunto_url = None
    if body.adjunto_base64:
        act_id = str(_uuid.uuid4())
        rec = subir_e_indexar(
            db, empresa_id=empresa_id, base64_data=body.adjunto_base64,
            folder=carpeta_soporte(empresa_id, ticket_id),
            public_id=f"act_{act_id}",
            entidad_tipo="ticket_actividad", entidad_id=ticket_id,
            creado_por_id=usuario_id,
        )
        adjunto_url = rec.secure_url

    a = _registrar_actividad(
        db, empresa_id=empresa_id, ticket_id=ticket_id, autor_id=usuario_id,
        tipo=tipo, texto=texto, adjunto_url=adjunto_url,
        es_solucion=es_solucion, version_solucion=version_solucion,
    )
    # Una solución marca el ticket como resuelto automáticamente.
    if es_solucion and t.estado not in ("resuelto", "cerrado"):
        t.estado = "resuelto"
        t.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(a)

    # Si responde alguien distinto del reportante, avisarle.
    if str(t.reportado_por) != str(usuario_id):
        try:
            from ..services.fcm_service import notificar_usuario
            if es_solucion:
                titulo = f"Solución a tu ticket {t.codigo}"
                mensaje = f"El equipo de TI registró una solución a tu ticket: {t.titulo}."
            else:
                titulo = f"Respuesta a tu ticket {t.codigo}"
                mensaje = f"Hay una nueva respuesta en tu ticket: {t.titulo}."
            notificar_usuario(
                db, empresa_id=empresa_id, usuario_id=str(t.reportado_por),
                titulo=titulo, mensaje=mensaje,
                tipo="info", categoria="soporte",
                referencia_id=str(t.id), referencia_tabla="ticket_soporte",
            )
            db.commit()
        except Exception:
            db.rollback()

    return _act_out(db, a)


# ── Centro de Seguridad: IPs bloqueadas + Sesiones activas ───────────────────

from ..models.sesion_usuario import SesionUsuario
from ..models.ip_bloqueada import IpBloqueada


class IpBloqueadaOut(BaseModel):
    id: str
    ip: str
    motivo: Optional[str]
    bloqueada_por_nombre: Optional[str]
    activa: bool
    created_at: str
    desbloqueada_en: Optional[str]


class BloquearIpBody(BaseModel):
    ip: str = Field(..., min_length=7, max_length=45)
    motivo: Optional[str] = None


class SesionActivaOut(BaseModel):
    id: str
    usuario_id: str
    usuario_nombre: str
    ip: Optional[str]
    dispositivo: Optional[str]
    user_agent: Optional[str]
    created_at: str
    fecha_expiracion: str


@router.get("/seguridad/ips", response_model=List[IpBloqueadaOut])
def listar_ips(
    mostrar_historial: bool = False,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Lista IPs bloqueadas de la empresa. Solo equipo TI (soporte:gestionar)."""
    if not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI puede ver IPs bloqueadas")

    empresa_id = payload["empresa_id"]
    q = db.query(IpBloqueada).filter(IpBloqueada.empresa_id == empresa_id)
    if not mostrar_historial:
        q = q.filter(IpBloqueada.activa == True)
    rows = q.order_by(IpBloqueada.created_at.desc()).all()

    def _fmt(dt: Optional[datetime]) -> Optional[str]:
        return dt.strftime("%d/%m/%Y %H:%M") if dt else None

    result = []
    for r in rows:
        nombre = _nombre_usuario(db, r.bloqueada_por) if r.bloqueada_por else None
        result.append(IpBloqueadaOut(
            id=str(r.id),
            ip=r.ip,
            motivo=r.motivo,
            bloqueada_por_nombre=nombre,
            activa=bool(r.activa),
            created_at=_fmt(r.created_at) or "",
            desbloqueada_en=_fmt(r.desbloqueada_en),
        ))
    return result


@router.post("/seguridad/ips", status_code=201)
def bloquear_ip(
    body: BloquearIpBody,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Bloquea una IP para la empresa. Solo equipo TI (soporte:gestionar)."""
    if not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI puede bloquear IPs")

    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]
    ip = body.ip.strip()

    # Validar que no esté ya bloqueada activamente
    existente = db.query(IpBloqueada).filter(
        IpBloqueada.empresa_id == empresa_id,
        IpBloqueada.ip == ip,
        IpBloqueada.activa == True,
    ).first()
    if existente:
        raise HTTPException(status_code=409, detail=f"La IP {ip} ya está bloqueada")

    nueva = IpBloqueada(
        id=str(_uuid.uuid4()),
        empresa_id=empresa_id,
        ip=ip,
        motivo=body.motivo,
        bloqueada_por=usuario_id,
        activa=True,
        created_at=datetime.utcnow(),
    )
    db.add(nueva)
    db.commit()
    db.refresh(nueva)

    return {
        "id": str(nueva.id),
        "ip": nueva.ip,
        "motivo": nueva.motivo,
        "activa": nueva.activa,
        "created_at": nueva.created_at.strftime("%d/%m/%Y %H:%M"),
    }


@router.delete("/seguridad/ips/{ip_id}")
def desbloquear_ip(
    ip_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Desbloquea una IP (activa = False). Solo equipo TI (soporte:gestionar)."""
    if not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI puede desbloquear IPs")

    empresa_id = payload["empresa_id"]
    registro = db.query(IpBloqueada).filter(
        IpBloqueada.id == ip_id,
        IpBloqueada.empresa_id == empresa_id,
    ).first()
    if not registro:
        raise HTTPException(status_code=404, detail="Registro de IP no encontrado")
    if not registro.activa:
        raise HTTPException(status_code=409, detail="La IP ya estaba desbloqueada")

    registro.activa = False
    registro.desbloqueada_en = datetime.utcnow()
    db.commit()
    return {"detail": f"IP {registro.ip} desbloqueada correctamente"}


@router.get("/seguridad/sesiones-activas", response_model=List[SesionActivaOut])
def sesiones_activas(
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Lista sesiones activas de la empresa. Solo equipo TI (soporte:gestionar)."""
    from ..core.security import es_superadmin
    es_admin = payload.get("rol", "").lower() in ("administrador", "admin", "superadmin")
    if not es_superadmin(payload) and not es_admin and not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Sin permiso para ver sesiones activas")

    empresa_id = payload["empresa_id"]
    ahora = datetime.utcnow()

    rows = (
        db.query(SesionUsuario)
        .join(Usuario, Usuario.id == SesionUsuario.usuario_id)
        .filter(
            Usuario.empresa_id == empresa_id,
            SesionUsuario.activa == True,
            SesionUsuario.fecha_expiracion > ahora,
        )
        .order_by(SesionUsuario.created_at.desc())
        .all()
    )

    def _fmt(dt: Optional[datetime]) -> str:
        return dt.strftime("%d/%m/%Y %H:%M") if dt else ""

    result = []
    for s in rows:
        nombre = _nombre_usuario(db, s.usuario_id)
        result.append(SesionActivaOut(
            id=str(s.id),
            usuario_id=str(s.usuario_id),
            usuario_nombre=nombre,
            ip=s.ip,
            dispositivo=s.dispositivo,
            user_agent=s.user_agent,
            created_at=_fmt(s.created_at),
            fecha_expiracion=_fmt(s.fecha_expiracion),
        ))
    return result


@router.post("/seguridad/sesiones/{sesion_id}/cerrar")
def cerrar_sesion_remota(
    sesion_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Cierra remotamente una sesión de usuario. Solo equipo TI (soporte:gestionar)."""
    if not _puede_gestionar(db, payload):
        raise HTTPException(status_code=403, detail="Solo el equipo de TI puede cerrar sesiones remotas")

    empresa_id = payload["empresa_id"]

    # Verificar que la sesión pertenece a un usuario de la empresa
    sesion = (
        db.query(SesionUsuario)
        .join(Usuario, Usuario.id == SesionUsuario.usuario_id)
        .filter(
            SesionUsuario.id == sesion_id,
            Usuario.empresa_id == empresa_id,
        )
        .first()
    )
    if not sesion:
        raise HTTPException(status_code=404, detail="Sesión no encontrada")
    if not sesion.activa:
        raise HTTPException(status_code=409, detail="La sesión ya estaba cerrada")

    sesion.activa = False
    sesion.fecha_cierre = datetime.utcnow()
    db.commit()
    return {"detail": "Sesión cerrada correctamente"}


# ── Monitoreo: Sesiones de usuarios ───────────────────────────────────────────

class SesionOut(BaseModel):
    id: str
    usuario_id: str
    usuario_nombre: str
    dispositivo: Optional[str]
    ip: Optional[str]
    activa: bool
    fecha_expiracion: str
    fecha_cierre: Optional[str]
    created_at: str


@router.get("/monitoreo/sesiones", response_model=List[SesionOut])
def listar_sesiones(
    usuario_id:   Optional[str] = None,
    fecha_desde:  Optional[str] = None,
    fecha_hasta:  Optional[str] = None,
    page:         int = 1,
    page_size:    int = 50,
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    """Monitoreo de sesiones de la empresa. Solo equipo TI (soporte:gestionar) o admin/superadmin."""
    from ..core.security import es_superadmin
    es_admin = payload.get("rol", "").lower() in ("administrador", "admin", "superadmin")
    if not es_superadmin(payload) and not es_admin and not tiene_permiso(db, payload, "soporte", "gestionar"):
        raise HTTPException(status_code=403, detail="Sin permiso para ver sesiones")

    empresa_id = payload["empresa_id"]

    q = (
        db.query(SesionUsuario)
        .join(Usuario, Usuario.id == SesionUsuario.usuario_id)
        .filter(Usuario.empresa_id == empresa_id)
    )

    if usuario_id:
        q = q.filter(SesionUsuario.usuario_id == usuario_id)

    if fecha_desde:
        try:
            fd = datetime.strptime(fecha_desde, "%Y-%m-%d")
            q = q.filter(SesionUsuario.created_at >= fd)
        except ValueError:
            pass

    if fecha_hasta:
        try:
            fh = datetime.strptime(fecha_hasta, "%Y-%m-%d")
            fh = fh.replace(hour=23, minute=59, second=59)
            q = q.filter(SesionUsuario.created_at <= fh)
        except ValueError:
            pass

    offset = (max(page, 1) - 1) * page_size
    rows = q.order_by(SesionUsuario.created_at.desc()).offset(offset).limit(page_size).all()

    def _fmt(dt: Optional[datetime]) -> Optional[str]:
        if not dt:
            return None
        return dt.strftime("%d/%m/%Y %H:%M")

    result = []
    for s in rows:
        nombre = _nombre_usuario(db, s.usuario_id)
        result.append(SesionOut(
            id=str(s.id),
            usuario_id=str(s.usuario_id),
            usuario_nombre=nombre,
            dispositivo=s.dispositivo,
            ip=s.ip,
            activa=bool(s.activa),
            fecha_expiracion=_fmt(s.fecha_expiracion) or "",
            fecha_cierre=_fmt(s.fecha_cierre),
            created_at=_fmt(s.created_at) or "",
        ))
    return result
