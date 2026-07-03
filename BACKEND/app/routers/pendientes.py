"""
Router: /pendientes — bandeja unificada "Mis pendientes".

SOLO LECTURA: agrega en una sola respuesta lo que espera acción del usuario,
consultando fuentes que ya existen. Cada sección se incluye únicamente si el
usuario tiene el permiso correspondiente (mismo gating que el módulo origen).
"""
from __future__ import annotations

from datetime import date, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import es_tecnico, tiene_permiso
from ..db.database import get_db
from ..models.cliente import Cliente
from ..models.cuentas_por_cobrar import FacturaCliente
from ..models.cuentas_por_pagar import FacturaProveedor
from ..models.empleado import Empleado
from ..models.proveedor import Proveedor
from ..models.proyecto import Proyecto
from ..models.requerimiento import Requerimiento
from ..models.solicitud_laboral import SolicitudLaboral
from ..models.usuario import Usuario
from ..models.vacaciones import SolicitudVacaciones

router = APIRouter(prefix="/pendientes", tags=["pendientes"])

DIAS_AVISO_VENCIMIENTO = 7


class PendienteItem(BaseModel):
    id: str
    titulo: str
    subtitulo: Optional[str] = None
    fecha: Optional[date] = None


class PendienteSeccion(BaseModel):
    id: str          # requerimientos | cxc_vencer | cxp_vencer | vacaciones | solicitudes
    titulo: str
    total: int
    items: List[PendienteItem]   # muestra (máx. 5); `total` es el conteo real


def _nombre_empleado(db: Session, empleado_id) -> str:
    fila = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == str(empleado_id))
        .first()
    )
    return f"{fila.nombre} {fila.apellido}" if fila else "—"


@router.get("", response_model=List[PendienteSeccion])
def mis_pendientes(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Secciones de pendientes visibles según los permisos del usuario."""
    empresa_id = payload["empresa_id"]
    hoy = date.today()
    limite = hoy + timedelta(days=DIAS_AVISO_VENCIMIENTO)
    secciones: list[PendienteSeccion] = []

    def agregar(sid: str, titulo: str, filas: list[PendienteItem], total: int):
        if total:
            secciones.append(PendienteSeccion(id=sid, titulo=titulo, total=total, items=filas))

    # ── Requerimientos por atender (Logística) ───────────────────────────────
    if tiene_permiso(db, payload, "requerimientos", "ver"):
        q = (
            db.query(Requerimiento, Proyecto.nombre_proyecto)
            .join(Proyecto, Requerimiento.proyecto_id == Proyecto.id)
            .filter(Requerimiento.empresa_id == empresa_id,
                    Requerimiento.estado == "pendiente")
            .order_by(Requerimiento.fecha)
        )
        total = q.count()
        agregar("requerimientos", "Requerimientos por atender", [
            PendienteItem(
                id=str(r.id), titulo=nombre_proyecto,
                subtitulo=f"Tipo: {r.tipo}", fecha=r.fecha,
            ) for r, nombre_proyecto in q.limit(5)
        ], total)

    # ── Facturas de clientes por vencer / vencidas (CxC) ─────────────────────
    if tiene_permiso(db, payload, "cxc", "ver"):
        q = (
            db.query(FacturaCliente, Cliente.razon_social)
            .join(Cliente, FacturaCliente.cliente_id == Cliente.id)
            .filter(FacturaCliente.empresa_id == empresa_id,
                    FacturaCliente.estado.in_(("pendiente", "cobrada_parcial")),
                    FacturaCliente.fecha_vencimiento.isnot(None),
                    FacturaCliente.fecha_vencimiento <= limite)
            .order_by(FacturaCliente.fecha_vencimiento)
        )
        total = q.count()
        agregar("cxc_vencer", "Cobros por vencer", [
            PendienteItem(
                id=str(f.id),
                titulo=f"{f.numero_documento} — {razon}",
                subtitulo=f"S/ {f.total}" + (" · VENCIDA" if f.fecha_vencimiento < hoy else ""),
                fecha=f.fecha_vencimiento,
            ) for f, razon in q.limit(5)
        ], total)

    # ── Facturas de proveedores por vencer / vencidas (CxP) ──────────────────
    if tiene_permiso(db, payload, "cxp", "ver"):
        q = (
            db.query(FacturaProveedor, Proveedor.razon_social)
            .join(Proveedor, FacturaProveedor.proveedor_id == Proveedor.id)
            .filter(FacturaProveedor.empresa_id == empresa_id,
                    FacturaProveedor.estado.in_(("pendiente", "pagada_parcial")),
                    FacturaProveedor.fecha_vencimiento <= limite)
            .order_by(FacturaProveedor.fecha_vencimiento)
        )
        total = q.count()
        agregar("cxp_vencer", "Pagos por vencer", [
            PendienteItem(
                id=str(f.id),
                titulo=f"{f.numero_documento} — {razon}",
                subtitulo=f"S/ {f.total}" + (" · VENCIDA" if f.fecha_vencimiento < hoy else ""),
                fecha=f.fecha_vencimiento,
            ) for f, razon in q.limit(5)
        ], total)

    # ── Vacaciones por aprobar ────────────────────────────────────────────────
    if tiene_permiso(db, payload, "vacaciones", "aprobar"):
        q = (
            db.query(SolicitudVacaciones)
            .filter(SolicitudVacaciones.empresa_id == empresa_id,
                    SolicitudVacaciones.estado == "pendiente")
            .order_by(SolicitudVacaciones.fecha_inicio)
        )
        total = q.count()
        agregar("vacaciones", "Vacaciones por aprobar", [
            PendienteItem(
                id=str(s.id),
                titulo=_nombre_empleado(db, s.empleado_id),
                subtitulo=f"{s.dias} días · {s.fecha_inicio} → {s.fecha_fin}",
                fecha=s.fecha_inicio,
            ) for s in q.limit(5)
        ], total)

    # ── Solicitudes laborales por evaluar (mismo gating que rrhh_solicitudes) ─
    if not es_tecnico(payload):
        q = (
            db.query(SolicitudLaboral)
            .filter(SolicitudLaboral.empresa_id == empresa_id,
                    SolicitudLaboral.estado == "pendiente")
            .order_by(SolicitudLaboral.created_at)
        )
        total = q.count()
        agregar("solicitudes", "Solicitudes laborales por evaluar", [
            PendienteItem(
                id=str(s.id),
                titulo=_nombre_empleado(db, s.empleado_id),
                subtitulo=s.tipo,
                fecha=s.fecha_inicio,
            ) for s in q.limit(5)
        ], total)

    return secciones
