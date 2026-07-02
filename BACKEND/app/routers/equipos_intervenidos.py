"""
Router: /equipos-intervenidos
Equipos del cliente que E-System TIC instala o mantiene, vinculados a proyecto y ubicacion.
Lecturas: cualquier autenticado de la empresa.
Escrituras: permiso 'equipo_intervenido:crear' / 'editar' / 'eliminar'.
"""
from __future__ import annotations

import calendar
import uuid
from datetime import date, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.equipo_intervenido import EquipoIntervenido, EquipoIntervenidoMantenimiento
from ..models.proyecto import Proyecto
from ..models.cliente import Cliente
from ..models.ubicacion import Ubicacion
from ..models.usuario import Usuario
from ..models.zona import Zona
from ..models.area import Area
from ..models.tipo_equipo import TipoEquipo
from ..models.procedimiento import Procedimiento
from ..models.evidencia_procedimiento import EvidenciaProcedimiento
from ..schemas.equipo_intervenido import (
    EquipoIntervenidoIn,
    EquipoIntervenidoOut,
    MantenimientoEquipoIn,
    MantenimientoEquipoOut,
)
from ..schemas.operaciones import ProcedimientoOut, EvidenciaOut

router = APIRouter(prefix="/equipos-intervenidos", tags=["equipos-intervenidos"])

ESTADOS_VALIDOS = {"operativo", "inoperativo", "mantenimiento", "en_revision"}
TIPOS_MANTENIMIENTO = {"preventivo", "correctivo", "inspeccion", "otro"}


def _sumar_meses(d: date, meses: int) -> date:
    """Suma N meses respetando fin de mes (31 ene + 1 mes = 28/29 feb)."""
    mes0 = d.month - 1 + meses
    anio = d.year + mes0 // 12
    mes = mes0 % 12 + 1
    dia = min(d.day, calendar.monthrange(anio, mes)[1])
    return date(anio, mes, dia)

# Prefijo de 3 letras por tipo de equipo, para el codigo unico {PROV}-{TIPO}-{NNN}
TIPO_PREFIJO = {
    "POZOS": "POZ", "POZO A TIERRA": "POZ", "TABLEROS": "TAB", "TABLERO ELECTRICO": "TAB",
    "UPS": "UPS", "TRANS. AISLAMIENTO": "TRA", "PARARRAYOS": "PAR",
    "LUMINARIAS": "LUM", "TOMACORRIENTES": "TOM",
}


def _prefijo_tipo(nombre_tipo: Optional[str]) -> str:
    if not nombre_tipo:
        return "EQ"
    return TIPO_PREFIJO.get(nombre_tipo.strip().upper(), nombre_tipo.strip().upper()[:3])


def generar_codigo(db: Session, empresa_id: str, ubicacion_id: Optional[str],
                   tipo_equipo_id: Optional[str]) -> str:
    """Genera un codigo unico {PROV}-{TIPO}-{NNN} dentro de la empresa."""
    prov = "GEN"
    if ubicacion_id:
        u = db.query(Ubicacion).filter(Ubicacion.id == ubicacion_id).first()
        if u and u.nombre:
            prov = "".join(ch for ch in u.nombre.upper() if ch.isalnum())[:3] or "GEN"
    tipo_nombre = None
    if tipo_equipo_id:
        t = db.query(TipoEquipo).filter(TipoEquipo.id == tipo_equipo_id).first()
        tipo_nombre = t.nombre if t else None
    pref = f"{prov}-{_prefijo_tipo(tipo_nombre)}-"
    existentes = (
        db.query(EquipoIntervenido.codigo)
        .filter(EquipoIntervenido.empresa_id == empresa_id,
                EquipoIntervenido.codigo.like(f"{pref}%"))
        .all()
    )
    maxn = 0
    for (cod,) in existentes:
        try:
            maxn = max(maxn, int((cod or "").rsplit("-", 1)[-1]))
        except (ValueError, IndexError):
            continue
    return f"{pref}{maxn + 1:03d}"


def buscar_duplicado(db: Session, empresa_id: str, nombre: str,
                     ubicacion_id: Optional[str], zona_id: Optional[str],
                     tipo_equipo_id: Optional[str], excluir_id: Optional[str] = None):
    """Devuelve un equipo existente con misma ubicacion+zona+tipo+nombre (case-insensitive)."""
    if not nombre:
        return None
    q = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.empresa_id == empresa_id,
        EquipoIntervenido.activo == True,
        func.lower(func.trim(EquipoIntervenido.nombre)) == nombre.strip().lower(),
    )
    q = q.filter(EquipoIntervenido.ubicacion_id == ubicacion_id) if ubicacion_id \
        else q.filter(EquipoIntervenido.ubicacion_id.is_(None))
    q = q.filter(EquipoIntervenido.zona_id == zona_id) if zona_id \
        else q.filter(EquipoIntervenido.zona_id.is_(None))
    if tipo_equipo_id:
        q = q.filter(EquipoIntervenido.tipo_equipo_id == tipo_equipo_id)
    if excluir_id:
        q = q.filter(EquipoIntervenido.id != excluir_id)
    return q.first()


def _procedimientos_de(e: EquipoIntervenido, db: Session) -> List[ProcedimientoOut]:
    """Procedimientos designados (pasos fijos avance/informe) del servicio al
    que está vinculado este equipo intervenido, con sus evidencias. Ids/FKs
    casteados a str explícitamente: columnas declaradas String(36) en el
    modelo pueden ser uuid nativo en la BD real (ver [[ezyro-plan-erp-crecimiento]]
    2026-07-02, mismo patrón que rompió ItemMaterialOut.equipo_id)."""
    if not e.proyecto_servicio_id:
        return []
    filas = (
        db.query(Procedimiento)
        .filter(Procedimiento.proyecto_servicio_id == e.proyecto_servicio_id)
        .order_by(Procedimiento.orden.asc())
        .all()
    )
    if not filas:
        return []
    proc_ids = [str(p.id) for p in filas]
    evidencias_por_proc: dict[str, list[EvidenciaOut]] = {}
    for ev in (
        db.query(EvidenciaProcedimiento)
        .filter(EvidenciaProcedimiento.procedimiento_id.in_(proc_ids))
        .order_by(EvidenciaProcedimiento.fecha_captura.asc())
        .all()
    ):
        evidencias_por_proc.setdefault(str(ev.procedimiento_id), []).append(
            EvidenciaOut(
                id=str(ev.id),
                url_cloudinary=ev.url_cloudinary,
                descripcion=ev.descripcion,
                etapa=ev.etapa,
                fecha_captura=ev.fecha_captura.isoformat(),
            )
        )
    return [
        ProcedimientoOut(
            id=str(p.id),
            nombre=p.nombre,
            descripcion=p.descripcion,
            orden=p.orden,
            estado=p.estado,
            evidencias=evidencias_por_proc.get(str(p.id), []),
        )
        for p in filas
    ]


def _to_out(e: EquipoIntervenido, db: Session, incluir_procedimientos: bool = False) -> EquipoIntervenidoOut:
    proyecto_nombre   = None
    cliente_nombre    = None
    ubicacion_nombre  = None
    zona_nombre       = None
    area_nombre       = None
    tipo_equipo_nombre = None

    if e.proyecto_id:
        p = db.query(Proyecto).filter(Proyecto.id == e.proyecto_id).first()
        if p:
            proyecto_nombre = p.nombre_proyecto
    if e.cliente_id:
        c = db.query(Cliente).filter(Cliente.id == e.cliente_id).first()
        if c:
            cliente_nombre = c.razon_social
    if e.ubicacion_id:
        u = db.query(Ubicacion).filter(Ubicacion.id == e.ubicacion_id).first()
        if u:
            ubicacion_nombre = u.nombre
    if e.zona_id:
        z = db.query(Zona).filter(Zona.id == e.zona_id).first()
        if z:
            zona_nombre = z.nombre
    if e.area_id:
        a = db.query(Area).filter(Area.id == e.area_id).first()
        if a:
            area_nombre = a.nombre
    if e.tipo_equipo_id:
        t = db.query(TipoEquipo).filter(TipoEquipo.id == e.tipo_equipo_id).first()
        if t:
            tipo_equipo_nombre = t.nombre

    return EquipoIntervenidoOut(
        id=str(e.id), empresa_id=str(e.empresa_id),
        proyecto_id=str(e.proyecto_id) if e.proyecto_id else None,
        cliente_id=str(e.cliente_id) if e.cliente_id else None,
        ubicacion_id=str(e.ubicacion_id) if e.ubicacion_id else None,
        zona_id=str(e.zona_id) if e.zona_id else None,
        area_id=str(e.area_id) if e.area_id else None,
        area_descripcion=e.area_descripcion,
        nombre=e.nombre, codigo=e.codigo,
        ubicacion_referencia=e.ubicacion_referencia,
        tipo_equipo_id=str(e.tipo_equipo_id) if e.tipo_equipo_id else None,
        marca=e.marca, modelo=e.modelo, numero_serie=e.numero_serie,
        estado=e.estado, fecha_instalacion=e.fecha_instalacion,
        ultimo_mantenimiento=e.ultimo_mantenimiento,
        proximo_mantenimiento=e.proximo_mantenimiento,
        frecuencia_meses=e.frecuencia_meses,
        ficha_tecnica=e.ficha_tecnica, observaciones=e.observaciones,
        activo=e.activo, created_at=e.created_at, updated_at=e.updated_at,
        proyecto_nombre=proyecto_nombre, cliente_nombre=cliente_nombre,
        ubicacion_nombre=ubicacion_nombre, zona_nombre=zona_nombre,
        area_nombre=area_nombre,
        tipo_equipo_nombre=tipo_equipo_nombre,
        procedimientos=_procedimientos_de(e, db) if incluir_procedimientos else [],
    )


# ── GET /equipos-intervenidos ─────────────────────────────────────────────────
@router.get("", response_model=List[EquipoIntervenidoOut])
def listar(
    proyecto_id:  Optional[str] = Query(None),
    cliente_id:   Optional[str] = Query(None),
    ubicacion_id: Optional[str] = Query(None),
    zona_id:      Optional[str] = Query(None),
    area_id:      Optional[str] = Query(None),
    estado:       Optional[str] = Query(None),
    activo:       Optional[bool] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    q = db.query(EquipoIntervenido).filter(EquipoIntervenido.empresa_id == empresa_id)
    if proyecto_id:
        q = q.filter(EquipoIntervenido.proyecto_id == proyecto_id)
    if cliente_id:
        q = q.filter(EquipoIntervenido.cliente_id == cliente_id)
    # Filtros geográficos (jerarquía ubicacion → zona → area)
    if ubicacion_id:
        q = q.filter(EquipoIntervenido.ubicacion_id == ubicacion_id)
    if zona_id:
        q = q.filter(EquipoIntervenido.zona_id == zona_id)
    if area_id:
        q = q.filter(EquipoIntervenido.area_id == area_id)
    if estado:
        q = q.filter(EquipoIntervenido.estado == estado)
    if activo is not None:
        q = q.filter(EquipoIntervenido.activo == activo)
    return [_to_out(e, db) for e in q.order_by(EquipoIntervenido.nombre).all()]


# ── GET /equipos-intervenidos/{id} ───────────────────────────────────────────
@router.get("/{equipo_id}", response_model=EquipoIntervenidoOut)
def detalle(
    equipo_id: str,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")
    return _to_out(e, db, incluir_procedimientos=True)


# ── GET /equipos-intervenidos/{id}/mantenimientos ────────────────────────────
@router.get("/{equipo_id}/mantenimientos", response_model=List[MantenimientoEquipoOut])
def listar_mantenimientos(
    equipo_id: str,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    """Historial de mantenimientos del equipo, mas reciente primero."""
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")
    rows = (
        db.query(EquipoIntervenidoMantenimiento)
        .filter(EquipoIntervenidoMantenimiento.empresa_id == empresa_id,
                EquipoIntervenidoMantenimiento.equipo_intervenido_id == equipo_id)
        .order_by(EquipoIntervenidoMantenimiento.fecha.desc(),
                  EquipoIntervenidoMantenimiento.created_at.desc())
        .all()
    )
    return [
        MantenimientoEquipoOut(
            id=str(m.id),
            equipo_intervenido_id=str(m.equipo_intervenido_id),
            fecha=m.fecha, tipo=m.tipo, descripcion=m.descripcion,
            realizado_por=m.realizado_por, proximo_calculado=m.proximo_calculado,
            created_at=m.created_at,
        )
        for m in rows
    ]


# ── POST /equipos-intervenidos/{id}/mantenimiento ────────────────────────────
@router.post("/{equipo_id}/mantenimiento", response_model=EquipoIntervenidoOut, status_code=201)
def registrar_mantenimiento(
    equipo_id: str,
    body: MantenimientoEquipoIn,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    """Registra un mantenimiento ejecutado: guarda el evento en el historial y
    actualiza el snapshot del equipo (ultimo_mantenimiento = fecha,
    proximo_mantenimiento = fecha + frecuencia_meses)."""
    exigir_permiso(db, payload, "equipo_intervenido", "editar")
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")

    tipo = (body.tipo or "preventivo").strip().lower()
    if tipo not in TIPOS_MANTENIMIENTO:
        raise HTTPException(status_code=422,
                            detail=f"Tipo invalido. Usar: {TIPOS_MANTENIMIENTO}")

    fecha = body.fecha or date.today()
    if fecha > date.today():
        raise HTTPException(status_code=422,
                            detail="La fecha del mantenimiento no puede ser futura")

    # Frecuencia: override opcional del body, si no la del equipo, si no 6 meses
    if body.frecuencia_meses is not None:
        if body.frecuencia_meses <= 0:
            raise HTTPException(status_code=422, detail="frecuencia_meses debe ser > 0")
        e.frecuencia_meses = body.frecuencia_meses
    frecuencia = e.frecuencia_meses or 6

    # Snapshot del plan en el equipo
    e.ultimo_mantenimiento  = fecha
    e.proximo_mantenimiento = _sumar_meses(fecha, frecuencia)
    if e.estado == "mantenimiento":
        e.estado = "operativo"
    e.updated_at = datetime.utcnow()

    # Quien lo realizo: texto libre o el usuario autenticado
    realizado_por = (body.realizado_por or "").strip() or None
    if not realizado_por:
        u = db.query(Usuario).filter(Usuario.id == payload.get("id")).first()
        if u:
            realizado_por = f"{u.nombre} {u.apellido}".strip()

    ev = EquipoIntervenidoMantenimiento(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        equipo_intervenido_id=str(e.id),
        fecha=fecha,
        tipo=tipo,
        descripcion=(body.descripcion or "").strip() or None,
        realizado_por=realizado_por,
        proximo_calculado=e.proximo_mantenimiento,
        registrado_por_id=payload.get("id"),
    )
    db.add(ev)
    db.commit()
    db.refresh(e)
    return _to_out(e, db)


# ── POST /equipos-intervenidos ────────────────────────────────────────────────
@router.post("", response_model=EquipoIntervenidoOut, status_code=201)
def crear(
    body: EquipoIntervenidoIn,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    exigir_permiso(db, payload, "equipo_intervenido", "crear")
    empresa_id = payload["empresa_id"]

    if body.estado and body.estado not in ESTADOS_VALIDOS:
        raise HTTPException(status_code=422, detail=f"Estado invalido. Usar: {ESTADOS_VALIDOS}")

    # Anti-duplicado: no recrear un equipo que ya existe en la misma ubicacion+zona+tipo.
    # Asi evitamos la duplicidad historica (recrear el equipo en cada mantenimiento).
    dup = buscar_duplicado(db, empresa_id, body.nombre, body.ubicacion_id,
                           body.zona_id, body.tipo_equipo_id)
    if dup:
        raise HTTPException(
            status_code=409,
            detail=f"Ya existe el equipo '{dup.nombre}' (codigo {dup.codigo}) en esta "
                   f"ubicacion y zona. Registra un mantenimiento sobre el existente "
                   f"en vez de crearlo de nuevo.",
        )

    datos = body.model_dump(exclude_none=True)
    e = EquipoIntervenido(
        id=str(uuid.uuid4()),
        empresa_id=empresa_id,
        **datos,
    )
    # Codigo unico autogenerado si no se envio
    if not e.codigo:
        e.codigo = generar_codigo(db, empresa_id, body.ubicacion_id, body.tipo_equipo_id)
    db.add(e)
    db.commit()
    db.refresh(e)
    return _to_out(e, db)


# ── PATCH /equipos-intervenidos/{id} ─────────────────────────────────────────
@router.patch("/{equipo_id}", response_model=EquipoIntervenidoOut)
def actualizar(
    equipo_id: str,
    body: EquipoIntervenidoIn,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    exigir_permiso(db, payload, "equipo_intervenido", "editar")
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")

    if body.estado and body.estado not in ESTADOS_VALIDOS:
        raise HTTPException(status_code=422, detail=f"Estado invalido. Usar: {ESTADOS_VALIDOS}")

    for campo, valor in body.model_dump(exclude_unset=True).items():
        setattr(e, campo, valor)
    e.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(e)
    return _to_out(e, db)


# ── DELETE /equipos-intervenidos/{id} ────────────────────────────────────────
@router.delete("/{equipo_id}", status_code=204)
def eliminar(
    equipo_id: str,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    exigir_permiso(db, payload, "equipo_intervenido", "eliminar")
    empresa_id = payload["empresa_id"]
    e = db.query(EquipoIntervenido).filter(
        EquipoIntervenido.id == equipo_id,
        EquipoIntervenido.empresa_id == empresa_id,
    ).first()
    if not e:
        raise HTTPException(status_code=404, detail="Equipo intervenido no encontrado")
    db.delete(e)
    db.commit()
