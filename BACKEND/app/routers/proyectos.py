from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..models.proyecto import Proyecto
from ..models.ubicacion import Ubicacion
from ..models.proyecto_servicio import ProyectoServicio

router = APIRouter(prefix="/proyectos", tags=["proyectos"])


class ServicioAsignado(BaseModel):
    id: str
    empresa: str
    tipo_servicio: str
    ubicacion: str
    estado: str
    supervisor: Optional[str] = None
    fecha_inicio: Optional[str] = None
    fecha_fin: Optional[str] = None
    telefono: Optional[str] = None
    urgente: bool = False


class MisServiciosResponse(BaseModel):
    servicios: List[ServicioAsignado]
    total: int


@router.get("/mis-servicios", response_model=MisServiciosResponse)
def mis_servicios(
    payload: dict = Depends(verificar_token),
):
    # TODO: conectar con ProyectoServicio en BD
    return MisServiciosResponse(servicios=[], total=0)


# ──────────────────────────────────────────────────────────────────────────
# Ubicaciones del proyecto (DERIVADAS de sus servicios)
# La geografía la posee el servicio (proyecto_servicio.ubicacion_id/zona_id);
# el nivel proyecto se obtiene agregando las ubicaciones de sus servicios. Esto
# habilita dashboards/gráficos por proyecto sin tablas que se desincronicen.
# ──────────────────────────────────────────────────────────────────────────
class UbicacionProyectoOut(BaseModel):
    ubicacion_id:  str
    nombre:        str
    region:        Optional[str] = None
    num_servicios: int


def _get_proyecto_o_404(db: Session, proyecto_id: str, empresa_id: str) -> Proyecto:
    p = db.query(Proyecto).filter(
        Proyecto.id == proyecto_id, Proyecto.empresa_id == empresa_id
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Proyecto no encontrado")
    return p


@router.get("/{proyecto_id}/ubicaciones", response_model=List[UbicacionProyectoOut])
def listar_ubicaciones_proyecto(
    proyecto_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Ubicaciones usadas por los servicios del proyecto, con conteo de servicios."""
    empresa_id = payload["empresa_id"]
    _get_proyecto_o_404(db, proyecto_id, empresa_id)
    from sqlalchemy import func
    rows = (
        db.query(Ubicacion, func.count(ProyectoServicio.id))
        .join(ProyectoServicio, ProyectoServicio.ubicacion_id == Ubicacion.id)
        .filter(
            ProyectoServicio.proyecto_id == proyecto_id,
            ProyectoServicio.empresa_id == empresa_id,
        )
        .group_by(Ubicacion.id)
        .order_by(Ubicacion.nombre)
        .all()
    )
    return [
        UbicacionProyectoOut(
            ubicacion_id=str(u.id), nombre=u.nombre, region=u.region, num_servicios=n
        )
        for u, n in rows
    ]
