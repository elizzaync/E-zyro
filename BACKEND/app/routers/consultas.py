"""
Router: /consultas — consulta RUC (SUNAT) y DNI (RENIEC).

Autocompleta razón social / nombre y dirección al dar de alta clientes y
proveedores. Solo lectura contra un servicio externo; requiere usuario
autenticado. El token se configura en APIS_NET_PE_TOKEN y el proveedor se
detecta por su prefijo:
  - sk_...          → decolecta.com
  - cualquier otro  → apis.net.pe
"""
from __future__ import annotations

import os
from typing import Optional

import requests
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..core.security import verificar_token

router = APIRouter(prefix="/consultas", tags=["consultas"])

_TIMEOUT = 10
# (base_url, path_ruc, path_dni) por proveedor
_PROVEEDORES = {
    "decolecta":  ("https://api.decolecta.com/v1", "sunat/ruc", "reniec/dni"),
    "apisnetpe":  ("https://api.apis.net.pe/v2",   "sunat/ruc", "reniec/dni"),
}


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


def _token() -> str:
    # Tolerante a errores de pegado: comillas, espacios o el prefijo "Bearer".
    token = os.getenv("APIS_NET_PE_TOKEN", "").strip().strip('"').strip("'")
    if token.lower().startswith("bearer "):
        token = token[7:].strip()
    if not token:
        raise HTTPException(
            status_code=503,
            detail="Consulta no configurada: falta APIS_NET_PE_TOKEN en el servidor.",
        )
    return token


def _consultar(tipo: str, numero: str) -> dict:
    """tipo: 'ruc' | 'dni'. Detecta el proveedor por el prefijo del token."""
    token = _token()
    proveedor = "decolecta" if token.startswith("sk_") else "apisnetpe"
    base, path_ruc, path_dni = _PROVEEDORES[proveedor]
    path = path_ruc if tipo == "ruc" else path_dni
    try:
        r = requests.get(
            f"{base}/{path}", params={"numero": numero},
            headers={"Authorization": f"Bearer {token}"}, timeout=_TIMEOUT,
        )
    except requests.RequestException:
        raise HTTPException(status_code=502, detail="Servicio de consulta no disponible.")
    if r.status_code in (401, 403):
        raise HTTPException(
            status_code=502,
            detail=f"Token rechazado por {proveedor}: verifica que esté vigente "
                   "y pegado sin comillas ni espacios.",
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
    d = _consultar("ruc", ruc)

    def g(*claves):  # primer valor presente entre variantes snake/camel
        for k in claves:
            if d.get(k):
                return d[k]
        return None

    return RucOut(
        ruc=g("numeroDocumento", "numero_documento") or ruc,
        razon_social=g("razonSocial", "razon_social", "nombre") or "",
        direccion=g("direccion", "direccion_completa"),
        estado=g("estado"),
        condicion=g("condicion"),
        distrito=g("distrito"),
        provincia=g("provincia"),
        departamento=g("departamento"),
    )


@router.get("/dni/{dni}", response_model=DniOut)
def consultar_dni(dni: str, payload: dict = Depends(verificar_token)):
    """Nombres y apellidos de un DNI (RENIEC)."""
    dni = dni.strip()
    if not (dni.isdigit() and len(dni) == 8):
        raise HTTPException(status_code=422, detail="El DNI debe tener 8 dígitos.")
    d = _consultar("dni", dni)
    nombres = d.get("nombres") or d.get("first_name") or ""
    ap = d.get("apellidoPaterno") or d.get("first_last_name") or ""
    am = d.get("apellidoMaterno") or d.get("second_last_name") or ""
    completo = d.get("full_name") or " ".join(x for x in (nombres, ap, am) if x)
    return DniOut(
        dni=d.get("numeroDocumento") or d.get("document_number") or dni,
        nombres=nombres,
        apellido_paterno=ap or None,
        apellido_materno=am or None,
        nombre_completo=completo,
    )
