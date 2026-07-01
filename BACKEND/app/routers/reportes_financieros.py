"""
Router: /reportes-financieros — estados financieros (Fase 9).

Capa de solo lectura sobre el libro mayor: balance de comprobación, balance
general, estado de resultados, flujo de efectivo y libros auxiliares. Ningún
endpoint modifica datos. RBAC: reutiliza el permiso 'contabilidad.ver'.
"""
from __future__ import annotations

from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..services import reportes_financieros_service as rep

router = APIRouter(prefix="/reportes-financieros", tags=["reportes-financieros"])


@router.get("/resumen")
def resumen_financiero(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Dashboard de Finanzas: disponible, CxC/CxP con vencidos, resultado del
    mes, top gastos, flujo 6 meses y caja proyectada 30/60/90. Permiso propio
    (`finanzas_resumen.ver`) porque expone la foto económica completa de la
    empresa: cada rol decide si lo ve, independiente de los submódulos."""
    exigir_permiso(db, payload, "finanzas_resumen", "ver")
    return rep.resumen_financiero(db, payload["empresa_id"])


@router.get("/balance-comprobacion")
def balance_comprobacion(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return rep.balance_comprobacion(db, payload["empresa_id"], periodo)


@router.get("/balance-general")
def balance_general(
    fecha: date = Query(...),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return rep.balance_general(db, payload["empresa_id"], fecha)


@router.get("/estado-resultados")
def estado_resultados(
    desde: date = Query(...), hasta: date = Query(...),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return rep.estado_resultados(db, payload["empresa_id"], desde, hasta)


@router.get("/flujo-efectivo")
def flujo_efectivo(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return rep.flujo_efectivo(db, payload["empresa_id"], periodo)


@router.get("/libro-diario")
def libro_diario(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return rep.libro_diario(db, payload["empresa_id"], periodo)


@router.get("/libro-mayor/{cuenta_id}")
def libro_mayor(
    cuenta_id: str,
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return rep.libro_mayor(db, payload["empresa_id"], cuenta_id, periodo)
