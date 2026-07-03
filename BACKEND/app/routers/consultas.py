"""
Router: /consultas — consulta RUC (SUNAT) y DNI (RENIEC) vía apis.net.pe.

Autocompleta razón social / nombre y dirección al dar de alta clientes y
proveedores. Solo lectura contra un servicio externo; requiere usuario
autenticado. El token del proveedor se configura en APIS_NET_PE_TOKEN
(https://apis.net.pe — plan gratuito disponible).
"""
from __future__ import annotations

import os
from typing import Optional

import requests
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..core.security import verificar_token

router = APIRouter(prefix="/consultas", tags=["consultas"])

_BASE = "https://api.apis.net.pe/v2"
_TIMEOUT = 10


class RucOut(BaseModel):
    ruc: str
    razon_social: str
    direccion: Optional[str] = None
    estado: Optional[str] = None       # ACTIVO | BAJA ...
    condicion: Optional[str] = None    # HABIDO | NO HABIDO ...
    distrito: Optional[str] = None
    provincia: Optional[str] = None
    departamento: Optional[str] = None


class DniOut(BaseModel):
    dni: str
    nombres: str
    apellido_paterno: Optional[str] = None
    apellido_materno: Optional[str] = None
    nombre_completo: str


def _consultar(path: str, numero: str) -> dict:
    # Tolerante a errores de pegado: comillas, espacios o el prefijo "Bearer".
    token = os.getenv("APIS_NET_PE_TOKEN", "").strip().strip('"').strip("'")
    if token.lower().startswith("bearer "):
        token = token[7:].strip()
    if not token:
        raise HTTPException(
            status_code=503,
            detail="Consulta no configurada: falta APIS_NET_PE_TOKEN en el servidor.",
        )
    try:
        r = requests.get(
            f"{_BASE}/{path}", params={"numero": numero},
            headers={"Authorization": f"Bearer {token}"}, timeout=_TIMEOUT,
        )
    except requests.RequestException:
        raise HTTPException(status_code=502, detail="Servicio de consulta no disponible.")
    if r.status_code in (401, 403):
        raise HTTPException(
            status_code=502,
            detail="Token rechazado por apis.net.pe: verifica que el token sea de "
                   "apis.net.pe (no de otro proveedor) y esté pegado sin comillas.",
        )
    if r.status_code == 404:
        raise HTTPException(status_code=404, detail="Número no encontrado.")
    if r.status_code == 422:
        raise HTTPException(status_code=422, detail="Número inválido.")
    if r.status_code == 429:
        raise HTTPException(status_code=502,
                            detail="Límite de consultas del plan alcanzado.")
    if r.status_code != 200:
        raise HTTPException(status_code=502,
                            detail=f"Servicio de consulta respondió {r.status_code}.")
    return r.json()


@router.get("/ruc/{ruc}", response_model=RucOut)
def consultar_ruc(ruc: str, payload: dict = Depends(verificar_token)):
    """Razón social y domicilio fiscal de un RUC (SUNAT)."""
    ruc = ruc.strip()
    if not (ruc.isdigit() and len(ruc) == 11):
        raise HTTPException(status_code=422, detail="El RUC debe tener 11 dígitos.")
    d = _consultar("sunat/ruc", ruc)
    return RucOut(
        ruc=d.get("numeroDocumento", ruc),
        razon_social=d.get("razonSocial") or d.get("nombre") or "",
        direccion=d.get("direccion"),
        estado=d.get("estado"),
        condicion=d.get("condicion"),
        distrito=d.get("distrito"),
        provincia=d.get("provincia"),
        departamento=d.get("departamento"),
    )


@router.get("/dni/{dni}", response_model=DniOut)
def consultar_dni(dni: str, payload: dict = Depends(verificar_token)):
    """Nombres y apellidos de un DNI (RENIEC)."""
    dni = dni.strip()
    if not (dni.isdigit() and len(dni) == 8):
        raise HTTPException(status_code=422, detail="El DNI debe tener 8 dígitos.")
    d = _consultar("reniec/dni", dni)
    nombres = d.get("nombres", "")
    ap = d.get("apellidoPaterno", "")
    am = d.get("apellidoMaterno", "")
    return DniOut(
        dni=d.get("numeroDocumento", dni),
        nombres=nombres,
        apellido_paterno=ap or None,
        apellido_materno=am or None,
        nombre_completo=" ".join(x for x in (nombres, ap, am) if x),
    )
