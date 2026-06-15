"""
Router: /logistica/inventario — valuación de inventario (Fase 5).

REPORTE (solo lectura). El inventario se mueve únicamente desde Logística
(compras, despachos, retornos, ajustes), que valoriza al costo promedio y genera
el asiento automático. Aquí se exponen el kardex valorizado y el costo promedio
vigente; ya NO se registran ingresos/salidas manuales (eso causaba doble entrada).
"""
from __future__ import annotations

from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..services import costeo_inventario_service as costeo

router = APIRouter(prefix="/logistica/inventario", tags=["inventario-valorizado"])


class CostoPromedioOut(BaseModel):
    material_id: str
    almacen_id: str
    cantidad_actual: Decimal
    costo_promedio_actual: Decimal
    valor_actual: Decimal


class KardexFilaOut(BaseModel):
    material_id: str
    almacen_id: Optional[str] = None
    saldo_valorizado: Decimal


# Los ingresos/salidas ya NO se registran aquí: el inventario se mueve solo desde
# Logística (compras, despachos, retornos, ajustes), que valoriza y contabiliza
# automáticamente. Este módulo queda como REPORTE (solo lectura).
@router.get("/valorizacion", response_model=List[KardexFilaOut])
def valorizacion(
    almacen: Optional[str] = Query(None),
    material: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "inventario_valorizado", "ver")
    return [KardexFilaOut(**f) for f in costeo.kardex_valorizado(db, payload["empresa_id"], almacen, material)]


@router.get("/costo-promedio/{material_id}", response_model=CostoPromedioOut)
def costo_promedio(
    material_id: str,
    almacen_id: str = Query(...),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "inventario_valorizado", "ver")
    return CostoPromedioOut(**costeo.costo_promedio(db, payload["empresa_id"], material_id, almacen_id))
