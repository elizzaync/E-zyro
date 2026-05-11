from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..core.security import verificar_token

router = APIRouter(prefix="/comunicados", tags=["comunicados"])


class ComunicadoResponse(BaseModel):
    id: str
    titulo: str
    contenido: str
    fecha: str
    leido: bool = False


@router.get("", response_model=List[ComunicadoResponse])
def listar_comunicados(
    payload: dict = Depends(verificar_token),
):
    # TODO: conectar con tabla Comunicado en BD
    return []


@router.post("/{comunicado_id}/leer")
def marcar_leido(
    comunicado_id: str,
    payload: dict = Depends(verificar_token),
):
    # TODO: registrar en ComunicadoLeido
    return {"ok": True, "comunicado_id": comunicado_id}
