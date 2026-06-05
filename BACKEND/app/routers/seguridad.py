"""
Router: /seguridad
Historial de sesiones del usuario (propio y, para admins/personal, de terceros).
"""
from __future__ import annotations

import hashlib
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func, case
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..models.sesion_usuario import SesionUsuario
from ..models.usuario import Usuario
from ..models.usuario_rol import UsuarioRol
from ..models.rol import Rol
from ..models.rol_permiso import RolPermiso
from ..models.permiso import Permiso
from ..models.firma_evento import FirmaEvento
from ..services.firma_seguridad import verificar_evento


router = APIRouter(prefix="/seguridad", tags=["seguridad"])
_http_bearer = HTTPBearer()


# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

def _es_admin(rol: Optional[str]) -> bool:
    r = (rol or "").lower()
    return r in ("superadmin", "admin", "administrador")


def _tiene_permiso_personal(db: Session, usuario_id: str, payload: dict) -> bool:
    """True si es admin o tiene el permiso PERSONAL:GESTIONAR en su rol."""
    if _es_admin(payload.get("rol")):
        return True
    perm = (
        db.query(Permiso.id)
        .join(RolPermiso, RolPermiso.permiso_id == Permiso.id)
        .join(UsuarioRol, UsuarioRol.rol_id == RolPermiso.rol_id)
        .filter(
            UsuarioRol.usuario_id == usuario_id,
            Permiso.modulo == "PERSONAL",
            Permiso.accion == "GESTIONAR",
        )
        .first()
    )
    return perm is not None


def _sesion_dict(s: SesionUsuario, token_hash_actual: Optional[str]) -> dict:
    return {
        "id":                str(s.id),
        "dispositivo":       s.dispositivo or "",
        "ip":                s.ip or "",
        "user_agent":        s.user_agent or "",
        "activa":            bool(s.activa),
        "es_actual":         (token_hash_actual is not None
                              and s.token_hash == token_hash_actual),
        "fecha_inicio":      s.created_at.strftime("%Y-%m-%d %H:%M") if s.created_at else "",
        "fecha_expiracion":  s.fecha_expiracion.strftime("%Y-%m-%d %H:%M") if s.fecha_expiracion else "",
        "fecha_cierre":      s.fecha_cierre.strftime("%Y-%m-%d %H:%M") if s.fecha_cierre else None,
    }


# ──────────────────────────────────────────────────────────────────────────
# GET /seguridad/mis-sesiones
# ──────────────────────────────────────────────────────────────────────────

@router.get("/mis-sesiones")
def mis_sesiones(
    limit:       int = Query(30, ge=1, le=100),
    credentials: HTTPAuthorizationCredentials = Security(_http_bearer),
    payload:     dict    = Depends(verificar_token),
    db:          Session = Depends(get_db),
):
    """Devuelve las últimas N sesiones del usuario logueado (más recientes primero).
    Marca con `es_actual=true` la sesión correspondiente al token de esta llamada."""
    usuario_id = payload["id"]
    token_hash = hashlib.sha256(credentials.credentials.encode()).hexdigest()

    rows = (
        db.query(SesionUsuario)
        .filter(SesionUsuario.usuario_id == usuario_id)
        .order_by(SesionUsuario.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_sesion_dict(s, token_hash) for s in rows]


# ──────────────────────────────────────────────────────────────────────────
# GET /seguridad/usuarios  (admin / PERSONAL:GESTIONAR)
# ──────────────────────────────────────────────────────────────────────────

@router.get("/usuarios")
def listar_usuarios(
    q:       str = Query("", description="texto en nombre/apellido/email"),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Listado de usuarios de la empresa con rol, foto, último acceso y sesiones activas."""
    if not _tiene_permiso_personal(db, payload["id"], payload):
        raise HTTPException(status_code=403, detail="Sin permiso para ver personal")
    empresa_id = payload["empresa_id"]

    # Rol por usuario. Un usuario puede tener VARIOS roles; para no duplicar la
    # fila en el listado tomamos UNO solo, prefiriendo el rol admin (mismo
    # criterio que el claim `rol` del token en /login).
    _rank = case(
        (
            func.replace(func.lower(Rol.nombre), " ", "").in_(
                ("superadmin", "admin", "administrador")
            ),
            0,
        ),
        else_=1,
    )
    _rn = func.row_number().over(
        partition_by=UsuarioRol.usuario_id,
        order_by=[_rank, Rol.nombre.asc()],
    ).label("rn")
    rol_ranked = (
        db.query(
            UsuarioRol.usuario_id.label("uid"),
            Rol.nombre.label("rol"),
            _rn,
        )
        .join(Rol, Rol.id == UsuarioRol.rol_id)
        .subquery()
    )
    rol_sub = (
        db.query(rol_ranked.c.uid, rol_ranked.c.rol)
        .filter(rol_ranked.c.rn == 1)
        .subquery()
    )

    # Sesiones activas por usuario.
    activas_sub = (
        db.query(
            SesionUsuario.usuario_id.label("uid"),
            func.count(SesionUsuario.id).label("n"),
        )
        .filter(SesionUsuario.activa.is_(True))
        .group_by(SesionUsuario.usuario_id)
        .subquery()
    )

    base = (
        db.query(
            Usuario.id, Usuario.nombre, Usuario.apellido, Usuario.email,
            Usuario.foto_url, Usuario.activo, Usuario.ultimo_acceso,
            rol_sub.c.rol,
            activas_sub.c.n,
        )
        .outerjoin(rol_sub,      rol_sub.c.uid == Usuario.id)
        .outerjoin(activas_sub,  activas_sub.c.uid == Usuario.id)
        .filter(Usuario.empresa_id == empresa_id)
    )
    if q.strip():
        like = f"%{q.lower().strip()}%"
        base = base.filter(
            (func.lower(Usuario.nombre).like(like))
            | (func.lower(Usuario.apellido).like(like))
            | (func.lower(Usuario.email).like(like))
        )

    rows = base.order_by(Usuario.nombre, Usuario.apellido).all()
    return [
        {
            "id":                     str(r.id),
            "nombre":                 r.nombre or "",
            "apellido":               r.apellido or "",
            "email":                  r.email or "",
            "rol":                    r.rol or "Sin rol",
            "foto_url":               r.foto_url,
            "activo":                 bool(r.activo),
            "ultimo_acceso":          r.ultimo_acceso.strftime("%Y-%m-%d %H:%M") if r.ultimo_acceso else None,
            "sesiones_activas":       int(r.n or 0),
        }
        for r in rows
    ]


# ──────────────────────────────────────────────────────────────────────────
# GET /seguridad/usuarios/{usuario_id}/sesiones  (admin / PERSONAL:GESTIONAR)
# ──────────────────────────────────────────────────────────────────────────

@router.get("/usuarios/{usuario_id}/sesiones")
def sesiones_de_usuario(
    usuario_id: str,
    limit:      int = Query(50, ge=1, le=200),
    payload:    dict    = Depends(verificar_token),
    db:         Session = Depends(get_db),
):
    """Historial de conexiones de un usuario específico (mismo empresa_id)."""
    if not _tiene_permiso_personal(db, payload["id"], payload):
        raise HTTPException(status_code=403, detail="Sin permiso para ver sesiones de otros")
    empresa_id = payload["empresa_id"]

    # Verificar que el usuario pertenece a la misma empresa
    u = db.query(Usuario).filter(
        Usuario.id == usuario_id, Usuario.empresa_id == empresa_id
    ).first()
    if not u:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    rows = (
        db.query(SesionUsuario)
        .filter(SesionUsuario.usuario_id == usuario_id)
        .order_by(SesionUsuario.created_at.desc())
        .limit(limit)
        .all()
    )
    # No se conoce el token actual del otro usuario → es_actual siempre false
    return [_sesion_dict(s, None) for s in rows]


# ──────────────────────────────────────────────────────────────────────────
# Trazabilidad de firmas (ledger firma_evento) — genérico para cualquier
# entidad: requerimientos, solicitudes laborales (trámites), firma guardada.
# ──────────────────────────────────────────────────────────────────────────

def _firma_evento_dict(ev: FirmaEvento) -> dict:
    return {
        "id":                  str(ev.id),
        "entidad_tipo":        ev.entidad_tipo,
        "entidad_id":          str(ev.entidad_id),
        "rol_firma":           ev.rol_firma,
        "firmante_id":         ev.firmante_id,
        "firmante_usuario_id": ev.firmante_usuario_id,
        "metodo":              ev.metodo,
        "sha256":              ev.sha256,
        "phash":               ev.phash,
        "ip":                  ev.ip,
        "user_agent":          ev.user_agent,
        "sospechoso":          bool(ev.sospechoso),
        "motivo_sospecha":     ev.motivo_sospecha,
        "fecha":               ev.created_at.strftime("%Y-%m-%d %H:%M:%S") if ev.created_at else "",
        "integridad_ok":       verificar_evento(ev),
    }


@router.get("/firmas")
def listar_firmas(
    entidad_tipo: str = Query(..., description="requerimiento | solicitud_laboral | firma_guardada …"),
    entidad_id:   str = Query(..., description="id de la entidad firmada"),
    payload:      dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    """Ledger de firmas de una entidad concreta (misma empresa): procedencia,
    huellas, flags de reutilización y verificación del sello por evento."""
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(FirmaEvento)
        .filter(
            FirmaEvento.empresa_id == empresa_id,
            FirmaEvento.entidad_tipo == entidad_tipo,
            FirmaEvento.entidad_id == entidad_id,
        )
        .order_by(FirmaEvento.created_at.asc())
        .all()
    )
    return [_firma_evento_dict(ev) for ev in rows]


@router.get("/firmas/sospechosas")
def listar_firmas_sospechosas(
    limit:   int = Query(100, ge=1, le=500),
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Tablero de seguridad: firmas marcadas como reutilización sospechosa en la
    empresa. Requiere permiso de gestión de personal (o admin)."""
    if not _tiene_permiso_personal(db, payload["id"], payload):
        raise HTTPException(status_code=403, detail="Sin permiso para auditar firmas")
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(FirmaEvento)
        .filter(
            FirmaEvento.empresa_id == empresa_id,
            FirmaEvento.sospechoso.is_(True),
        )
        .order_by(FirmaEvento.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_firma_evento_dict(ev) for ev in rows]


@router.get("/firmas/{evento_id}/verificar")
def verificar_firma(
    evento_id: str,
    payload:   dict    = Depends(verificar_token),
    db:        Session = Depends(get_db),
):
    """Verifica el sello HMAC de un evento de firma puntual (tamper-evidence)."""
    empresa_id = payload["empresa_id"]
    ev = db.query(FirmaEvento).filter(
        FirmaEvento.id == evento_id, FirmaEvento.empresa_id == empresa_id
    ).first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evento de firma no encontrado")
    return _firma_evento_dict(ev)
