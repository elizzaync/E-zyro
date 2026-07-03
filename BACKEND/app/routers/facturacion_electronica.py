"""
Router: /facturacion-electronica — configuración del CPE por empresa.

Feature opcional activable por empresa: apagada, el sistema factura solo
internamente; encendida, cada factura/boleta de CxC se emite también como
comprobante electrónico vía el PSE configurado (Nubefact).
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.facturacion_electronica import ConfiguracionFacturacionElectronica
from ..services import facturacion_electronica_service as fe

router = APIRouter(prefix="/facturacion-electronica", tags=["facturacion-electronica"])


class ConfigOut(BaseModel):
    habilitado: bool
    proveedor: str
    api_url: Optional[str] = None
    token_configurado: bool     # nunca devolvemos el token
    serie_factura: str
    serie_boleta: str


class ConfigIn(BaseModel):
    habilitado: Optional[bool] = None
    api_url: Optional[str] = None
    api_token: Optional[str] = None
    serie_factura: Optional[str] = None
    serie_boleta: Optional[str] = None


def _out(cfg: ConfiguracionFacturacionElectronica | None) -> ConfigOut:
    if cfg is None:
        return ConfigOut(habilitado=False, proveedor="nubefact",
                         token_configurado=False,
                         serie_factura="F001", serie_boleta="B001")
    return ConfigOut(
        habilitado=bool(cfg.habilitado), proveedor=cfg.proveedor,
        api_url=cfg.api_url, token_configurado=bool(cfg.api_token),
        serie_factura=cfg.serie_factura, serie_boleta=cfg.serie_boleta,
    )


@router.get("/configuracion", response_model=ConfigOut)
def obtener_configuracion(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "cxc", "ver")
    return _out(fe.get_config(db, payload["empresa_id"]))


@router.put("/configuracion", response_model=ConfigOut)
def actualizar_configuracion(
    body: ConfigIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "configurar")
    cfg = fe.get_config(db, payload["empresa_id"])
    if cfg is None:
        cfg = ConfiguracionFacturacionElectronica(empresa_id=payload["empresa_id"])
        db.add(cfg)
    if body.habilitado is not None:
        cfg.habilitado = body.habilitado
    if body.api_url is not None:
        cfg.api_url = body.api_url.strip() or None
    if body.api_token is not None:
        cfg.api_token = body.api_token.strip() or None
    if body.serie_factura is not None:
        cfg.serie_factura = body.serie_factura.strip() or "F001"
    if body.serie_boleta is not None:
        cfg.serie_boleta = body.serie_boleta.strip() or "B001"
    db.commit()
    db.refresh(cfg)
    return _out(cfg)
