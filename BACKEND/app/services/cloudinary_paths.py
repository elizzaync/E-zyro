"""
Taxonomía ÚNICA de carpetas en Cloudinary. Nadie debe escribir `folder="..."`
a mano: siempre usar estos helpers. Raíz única `e-zyro/{empresa_id}/...` para
aislar también por empresa en la nube.

(Fase 1 — plan migración ERP. El refactor de los call-sites antiguos
—'e_zyro/...', 'evidencias/...', etc.— es una tarea aparte; este helper rige
para todo el código nuevo.)
"""
from __future__ import annotations

ROOT = "e-zyro"


def _emp(empresa_id: str) -> str:
    return f"{ROOT}/{empresa_id}"


def carpeta_perfil(empresa_id: str) -> str:
    return f"{_emp(empresa_id)}/perfiles"


def carpeta_firma(empresa_id: str, contexto: str) -> str:
    return f"{_emp(empresa_id)}/firmas/{contexto}"


def carpeta_asistencia(empresa_id: str, empleado_id: str, periodo_ym: str) -> str:
    return f"{_emp(empresa_id)}/asistencia/{empleado_id}/{periodo_ym}"


def carpeta_biometrico(empresa_id: str, usuario_id: str) -> str:
    return f"{_emp(empresa_id)}/biometrico/{usuario_id}"


def carpeta_evidencia(empresa_id: str, proyecto_id: str, servicio_id: str) -> str:
    return f"{_emp(empresa_id)}/evidencias/{proyecto_id}/{servicio_id}"


def carpeta_mantenimiento(empresa_id: str, equipo_id: str) -> str:
    return f"{_emp(empresa_id)}/mantenimiento/{equipo_id}"


def carpeta_epp(empresa_id: str, epp_id: str) -> str:
    return f"{_emp(empresa_id)}/epp/{epp_id}"


def carpeta_epp_entrega(empresa_id: str, entrega_id: str) -> str:
    return f"{_emp(empresa_id)}/epp-entregas/{entrega_id}"


def carpeta_calibracion(empresa_id: str, equipo_id: str) -> str:
    return f"{_emp(empresa_id)}/calibraciones/{equipo_id}"


def carpeta_itse(empresa_id: str, inspeccion_id: str) -> str:
    return f"{_emp(empresa_id)}/itse/{inspeccion_id}"


def carpeta_correctivo(empresa_id: str, correctivo_id: str) -> str:
    return f"{_emp(empresa_id)}/correctivos/{correctivo_id}"


def carpeta_galeria(empresa_id: str, aaaa: str | int, mm: str | int) -> str:
    return f"{_emp(empresa_id)}/galeria/{aaaa}/{int(mm):02d}" if str(mm).isdigit() else f"{_emp(empresa_id)}/galeria/{aaaa}/{mm}"
