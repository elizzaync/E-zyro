"""
Router: /tributario — régimen tributario e IGV (Fase 6).

Catálogo de regímenes, configuración por empresa (régimen + cuentas de IGV) y
registros auxiliares de compras/ventas del periodo. RBAC (modulo='tributario').
"""
from __future__ import annotations

from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.tributario import RegimenTributarioCatalogo, ConfiguracionTributariaEmpresa
from ..schemas.tributario import (
    RegimenOut, ConfiguracionOut, ConfiguracionUpdate, RegistroFila,
)
from ..services import tributario_service as tributario

router = APIRouter(prefix="/tributario", tags=["tributario"])


@router.get("/regimenes", response_model=List[RegimenOut])
def listar_regimenes(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "tributario", "ver")
    return [
        RegimenOut(id=str(r.id), codigo=r.codigo, nombre=r.nombre, tasa_igv=r.tasa_igv,
                   tasa_renta_referencial=r.tasa_renta_referencial, activo=bool(r.activo))
        for r in db.query(RegimenTributarioCatalogo).order_by(RegimenTributarioCatalogo.codigo).all()
    ]


def _config_out(db: Session, cfg: ConfiguracionTributariaEmpresa) -> ConfiguracionOut:
    reg = db.query(RegimenTributarioCatalogo).filter(RegimenTributarioCatalogo.id == cfg.regimen_id).first()
    return ConfiguracionOut(
        regimen_id=str(cfg.regimen_id), regimen_codigo=(reg.codigo if reg else "—"),
        tasa_igv=(reg.tasa_igv if reg else __import__("decimal").Decimal("0")),
        cuenta_igv_credito_fiscal_id=(str(cfg.cuenta_igv_credito_fiscal_id) if cfg.cuenta_igv_credito_fiscal_id else None),
        cuenta_igv_debito_fiscal_id=(str(cfg.cuenta_igv_debito_fiscal_id) if cfg.cuenta_igv_debito_fiscal_id else None),
    )


@router.get("/configuracion", response_model=ConfiguracionOut)
def obtener_configuracion(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "tributario", "ver")
    cfg = db.query(ConfiguracionTributariaEmpresa).filter(
        ConfiguracionTributariaEmpresa.empresa_id == payload["empresa_id"]).first()
    if not cfg:
        raise HTTPException(status_code=404, detail="La empresa no tiene configuración tributaria.")
    return _config_out(db, cfg)


@router.put("/configuracion", response_model=ConfiguracionOut)
def actualizar_configuracion(
    body: ConfiguracionUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "tributario", "configurar")
    cfg = db.query(ConfiguracionTributariaEmpresa).filter(
        ConfiguracionTributariaEmpresa.empresa_id == payload["empresa_id"]).first()
    if not cfg:
        raise HTTPException(status_code=404, detail="La empresa no tiene configuración tributaria.")
    if body.regimen_id is not None:
        cfg.regimen_id = body.regimen_id
    if body.cuenta_igv_credito_fiscal_id is not None:
        cfg.cuenta_igv_credito_fiscal_id = body.cuenta_igv_credito_fiscal_id
    if body.cuenta_igv_debito_fiscal_id is not None:
        cfg.cuenta_igv_debito_fiscal_id = body.cuenta_igv_debito_fiscal_id
    db.commit()
    db.refresh(cfg)
    return _config_out(db, cfg)


@router.get("/registro-compras", response_model=List[RegistroFila])
def registro_compras(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "tributario", "ver")
    return [RegistroFila(**f) for f in tributario.registro_compras(db, payload["empresa_id"], periodo)]


@router.get("/registro-ventas", response_model=List[RegistroFila])
def registro_ventas(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "tributario", "ver")
    return [RegistroFila(**f) for f in tributario.registro_ventas(db, payload["empresa_id"], periodo)]
