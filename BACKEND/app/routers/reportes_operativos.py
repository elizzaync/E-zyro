"""
Router: /reportes-operativos — HU-54.

Data operativa consolidada (horas hombre + materiales consumidos) por
proyecto, para auditorías internas de la administración. Capa de solo
lectura; la agregación pesada vive en reportes_operativos_service.
"""
from __future__ import annotations

from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..services import reportes_operativos_service as rep

router = APIRouter(prefix="/reportes-operativos", tags=["reportes-operativos"])

# ponytail: horas hombre concilia entrada/salida en Python (no es agregable
# 100% en SQL) — sin tope, un rango de años trae miles de filas a memoria,
# justo lo que la HU pide evitar. Subir el tope si un caso real lo necesita.
_RANGO_MAX_DIAS = 366


def _validar_rango(desde: date, hasta: date) -> None:
    if hasta < desde:
        raise HTTPException(status_code=422, detail="'hasta' no puede ser anterior a 'desde'")
    if (hasta - desde).days > _RANGO_MAX_DIAS:
        raise HTTPException(
            status_code=422,
            detail=f"Rango máximo permitido: {_RANGO_MAX_DIAS} días. Acota las fechas o filtra por proyecto.",
        )


@router.get("/por-proyecto")
def reporte_por_proyecto(
    desde: date = Query(...),
    hasta: date = Query(...),
    proyecto_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "reportes", "ver")
    _validar_rango(desde, hasta)
    return rep.reporte_operativo_por_proyecto(db, payload["empresa_id"], desde, hasta, proyecto_id)


@router.get("/por-proyecto/excel")
def reporte_por_proyecto_excel(
    desde: date = Query(...),
    hasta: date = Query(...),
    proyecto_id: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Genera el XLSX consolidado, lo sube a Cloudinary y devuelve {url}."""
    from ..models.empresa import Empresa
    from ..services import excel_reportes_service as xls

    exigir_permiso(db, payload, "reportes", "ver")
    _validar_rango(desde, hasta)
    empresa_id = payload["empresa_id"]
    filas = rep.reporte_operativo_por_proyecto(db, empresa_id, desde, hasta, proyecto_id)
    empresa = db.query(Empresa.razon_social).filter(Empresa.id == empresa_id).first()
    xlsx = xls.xlsx_reporte_operativo(
        filas, empresa.razon_social if empresa else "", desde.isoformat(), hasta.isoformat(),
    )
    return {"url": xls.subir_xlsx(xlsx, f"reporte-operativo-{desde.isoformat()}_{hasta.isoformat()}")}
