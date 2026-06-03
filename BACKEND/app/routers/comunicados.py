from __future__ import annotations

import json
import uuid as _uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..core.security import verificar_token, es_superadmin
from ..core.permisos import tiene_permiso
from ..db.database import get_db
from ..models.auditoria import Auditoria
from ..models.comunicado import ComunicadoProyecto, ComunicadoLeido
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.proyecto import Proyecto
from ..models.proyecto_miembro import ProyectoMiembro
from ..services.fcm_service import enviar_push_a_usuario

router = APIRouter(prefix="/comunicados", tags=["comunicados"])


class ComunicadoResponse(BaseModel):
    id: str
    titulo: str
    contenido: str
    fecha: str
    autor: str = ""
    leido: bool = False


class ComunicadoProyectoOut(BaseModel):
    id: str
    proyecto_id: str
    titulo: str
    mensaje: str
    autor: str
    fecha: str
    adjunto_url: Optional[str]
    leido: bool


def _get_empleado(db: Session, usuario_id: str, empresa_id: str) -> Optional[Empleado]:
    return db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id,
        Empleado.empresa_id == empresa_id,
    ).first()


# ── GET /comunicados ──────────────────────────────────────────────────────────

@router.get("", response_model=List[ComunicadoResponse])
def listar_comunicados(
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    """Tablón global: comunicados de todos los proyectos donde el usuario
    participa (es miembro activo o jefe de operaciones). Alimenta la pantalla
    Más → Comunicados."""
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    empleado = _get_empleado(db, usuario_id, empresa_id)
    if not empleado:
        return []

    # Proyectos donde es miembro activo
    proyecto_ids: set[str] = {
        str(r.proyecto_id)
        for r in db.query(ProyectoMiembro.proyecto_id).filter(
            ProyectoMiembro.empleado_id == empleado.id,
            ProyectoMiembro.activo == True,  # noqa: E712
        ).all()
    }
    # Proyectos donde es jefe de operaciones
    for r in db.query(Proyecto.id).filter(
        Proyecto.empresa_id == empresa_id,
        Proyecto.jefe_operaciones_id == empleado.id,
    ).all():
        proyecto_ids.add(str(r.id))

    # Admin ve todos los comunicados de su empresa
    if es_superadmin(payload):
        comunicados = (
            db.query(ComunicadoProyecto)
            .filter(ComunicadoProyecto.empresa_id == empresa_id)
            .order_by(ComunicadoProyecto.created_at.desc())
            .all()
        )
    elif proyecto_ids:
        comunicados = (
            db.query(ComunicadoProyecto)
            .filter(
                ComunicadoProyecto.empresa_id == empresa_id,
                ComunicadoProyecto.proyecto_id.in_([_uuid.UUID(p) for p in proyecto_ids]),
            )
            .order_by(ComunicadoProyecto.created_at.desc())
            .all()
        )
    else:
        return []

    if not comunicados:
        return []

    # Marcas de leído de este empleado
    leidos_ids = {
        str(r.comunicado_id)
        for r in db.query(ComunicadoLeido.comunicado_id).filter(
            ComunicadoLeido.empleado_id == empleado.id,
            ComunicadoLeido.comunicado_id.in_([c.id for c in comunicados]),
        ).all()
    }

    # Mapa autor_id → nombre completo (nombre/apellido viven en Usuario)
    autor_ids = [str(c.autor_id) for c in comunicados if c.autor_id]
    empleados_map: dict[str, str] = {}
    if autor_ids:
        try:
            for emp, usr in (
                db.query(Empleado, Usuario)
                .join(Usuario, Usuario.id == Empleado.usuario_id)
                .filter(Empleado.id.in_(autor_ids))
                .all()
            ):
                nombre   = (usr.nombre   or "") if usr else ""
                apellido = (usr.apellido or "") if usr else ""
                empleados_map[str(emp.id)] = f"{nombre} {apellido}".strip() or "Usuario"
        except Exception:
            empleados_map = {}

    def _fecha(c: ComunicadoProyecto) -> str:
        try:
            return c.created_at.strftime("%d/%m/%Y %H:%M") if c.created_at else "—"
        except Exception:
            return "—"

    return [
        ComunicadoResponse(
            id=str(c.id),
            titulo=c.titulo or "(Sin título)",
            contenido=c.mensaje or "",
            fecha=_fecha(c),
            autor=empleados_map.get(str(c.autor_id) if c.autor_id else "", "Sistema"),
            leido=(str(c.id) in leidos_ids),
        )
        for c in comunicados
    ]


# ── GET /comunicados/proyecto/{proyecto_id} ───────────────────────────────────
# HU-13: Canal de difusión por proyecto

@router.get("/proyecto/{proyecto_id}", response_model=List[ComunicadoProyectoOut])
def listar_comunicados_proyecto(
    proyecto_id: str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    empleado = _get_empleado(db, usuario_id, empresa_id)

    comunicados = (
        db.query(ComunicadoProyecto)
        .filter(
            ComunicadoProyecto.proyecto_id == proyecto_id,
            ComunicadoProyecto.empresa_id  == empresa_id,
        )
        .order_by(ComunicadoProyecto.created_at.desc())
        .all()
    )

    leidos_ids: set[str] = set()
    if empleado and comunicados:
        leidos_rows = db.query(ComunicadoLeido.comunicado_id).filter(
            ComunicadoLeido.empleado_id == empleado.id,
            ComunicadoLeido.comunicado_id.in_([c.id for c in comunicados]),
        ).all()
        leidos_ids = {r.comunicado_id for r in leidos_rows}

    # ── Construir mapa autor_id (str) → nombre completo ──────────────────────
    # Empleado NO tiene nombre/apellido; esos campos viven en Usuario.
    # Hacemos JOIN Empleado ↔ Usuario y normalizamos todo a str para evitar
    # mismatches UUID-object vs str en el .in_() de SQLAlchemy.
    autor_ids: list[str] = [str(c.autor_id) for c in comunicados if c.autor_id]
    empleados_map: dict[str, str] = {}
    if autor_ids:
        try:
            autores = (
                db.query(Empleado, Usuario)
                .join(Usuario, Usuario.id == Empleado.usuario_id)
                .filter(Empleado.id.in_(autor_ids))
                .all()
            )
            for emp, usr in autores:
                if emp is None:
                    continue
                nombre   = (usr.nombre   or "") if usr else ""
                apellido = (usr.apellido or "") if usr else ""
                nombre_completo = f"{nombre} {apellido}".strip() or "Usuario Desconocido"
                empleados_map[str(emp.id)] = nombre_completo
        except Exception:
            # Si la consulta falla por cualquier razón, continuamos con mapa vacío
            empleados_map = {}

    def _safe_fecha(c: ComunicadoProyecto) -> str:
        try:
            return c.created_at.strftime("%d/%m/%Y %H:%M") if c.created_at else "—"
        except Exception:
            return "—"

    return [
        ComunicadoProyectoOut(
            id=str(c.id),
            proyecto_id=str(c.proyecto_id),
            titulo=c.titulo or "(Sin título)",
            mensaje=c.mensaje or "",
            autor=empleados_map.get(str(c.autor_id) if c.autor_id else "", "Sistema"),
            fecha=_safe_fecha(c),
            adjunto_url=c.adjunto_url,
            leido=(str(c.id) in {str(x) for x in leidos_ids}),
        )
        for c in comunicados
    ]


# ── PUT /comunicados/{comunicado_id}/marcar-leido ─────────────────────────────
# HU-13: Marcar comunicado como leído

@router.put("/{comunicado_id}/marcar-leido")
def marcar_leido_proyecto(
    comunicado_id: str,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    empleado = _get_empleado(db, usuario_id, empresa_id)
    if not empleado:
        return {"ok": True}

    existe = db.query(ComunicadoLeido).filter(
        ComunicadoLeido.comunicado_id == comunicado_id,
        ComunicadoLeido.empleado_id   == empleado.id,
    ).first()

    if not existe:
        db.add(ComunicadoLeido(
            comunicado_id=comunicado_id,
            empleado_id=empleado.id,
            leido_at=datetime.utcnow(),
        ))
        db.commit()

    return {"ok": True, "comunicado_id": comunicado_id}


# ── POST /comunicados/{id}/leer (legacy) ─────────────────────────────────────

@router.post("/{comunicado_id}/leer")
def marcar_leido_legacy(
    comunicado_id: str,
    payload: dict = Depends(verificar_token),
):
    return {"ok": True, "comunicado_id": comunicado_id}


# ── POST /comunicados/proyecto/{proyecto_id} ──────────────────────────────────
# Crear un nuevo comunicado — solo admin / jefe_operaciones

class CrearComunicadoIn(BaseModel):
    titulo: str = Field(..., max_length=200)
    mensaje: str
    adjunto_url: Optional[str] = None


@router.post("/proyecto/{proyecto_id}/nuevo", status_code=status.HTTP_201_CREATED)
def crear_comunicado_proyecto(
    proyecto_id: str,
    body: CrearComunicadoIn,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    proyecto = db.query(Proyecto).filter(
        Proyecto.id == proyecto_id,
        Proyecto.empresa_id == empresa_id,
    ).first()
    if not proyecto:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")

    empleado_autor = _get_empleado(db, usuario_id, empresa_id)

    # RBAC: requiere el permiso 'comunicados:enviar' (Admin lo tiene por bypass;
    # Jefe de Operaciones por la matriz rol→permiso).
    if not tiene_permiso(db, payload, "comunicados", "enviar"):
        raise HTTPException(status_code=403, detail="Sin permiso para enviar comunicados")

    comunicado = ComunicadoProyecto(
        id          = _uuid.uuid4(),
        empresa_id  = _uuid.UUID(empresa_id),
        proyecto_id = _uuid.UUID(proyecto_id),
        autor_id    = _uuid.UUID(str(empleado_autor.id)) if empleado_autor else None,
        titulo      = body.titulo,
        mensaje     = body.mensaje,
        adjunto_url = body.adjunto_url,
        created_at  = datetime.utcnow(),
    )
    db.add(comunicado)

    db.add(Auditoria(
        id             = str(_uuid.uuid4()),
        empresa_id     = empresa_id,
        usuario_id     = usuario_id,
        tabla_afectada = "comunicado_proyecto",
        registro_id    = str(comunicado.id),
        # 'accion' está limitado por chk_auditoria_accion a un set fijo
        # (INSERT/UPDATE/DELETE/...). El detalle va en 'descripcion'/'modulo'.
        accion         = "INSERT",
        modulo         = "comunicados",
        descripcion    = f"Comunicado '{body.titulo}' enviado al proyecto {proyecto_id}",
        datos_nuevos   = {"titulo": body.titulo, "proyecto_id": proyecto_id},
        fecha          = datetime.utcnow(),
    ))

    db.commit()

    # ── Notificar a los miembros del proyecto (push FCM) ──────────────────────
    # El comunicado llega a todos los miembros activos del proyecto + el jefe de
    # operaciones. No se notifica al autor. Cualquier fallo de envío es silencioso
    # para no afectar la respuesta de creación.
    try:
        destinatarios: set[str] = {
            str(r.usuario_id)
            for r in (
                db.query(Empleado.usuario_id)
                .join(ProyectoMiembro, ProyectoMiembro.empleado_id == Empleado.id)
                .filter(
                    ProyectoMiembro.proyecto_id == proyecto_id,
                    ProyectoMiembro.activo == True,  # noqa: E712
                )
                .all()
            )
        }
        if proyecto.jefe_operaciones_id:
            jefe_emp = db.query(Empleado).filter(
                Empleado.id == proyecto.jefe_operaciones_id
            ).first()
            if jefe_emp:
                destinatarios.add(str(jefe_emp.usuario_id))

        destinatarios.discard(str(usuario_id))  # no notificar al autor

        for uid in destinatarios:
            try:
                enviar_push_a_usuario(
                    usuario_id=uid,
                    titulo=f"📢 {body.titulo}",
                    mensaje=body.mensaje,
                    db=db,
                    tipo="comunicado_proyecto",
                    referencia_id=proyecto_id,
                    referencia_tabla="proyecto",
                )
            except Exception:
                pass
    except Exception:
        pass

    return {"ok": True, "id": str(comunicado.id)}
