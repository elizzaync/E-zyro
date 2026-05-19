from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..core.security import verificar_token

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
