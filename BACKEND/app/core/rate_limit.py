"""
Rate limiting en memoria — ventana deslizante, sin dependencias externas.

Suficiente para el deploy actual (un solo proceso en Railway). Si algún día
hay varios workers, cada uno lleva su propia ventana: el límite efectivo se
multiplica, pero sigue conteniendo abuso por IP/usuario.
"""
from __future__ import annotations

import threading
import time

_LOCK = threading.Lock()
_VENTANAS: dict[str, list[float]] = {}
_ultima_limpieza: float = 0.0
_INTERVALO_LIMPIEZA_SEG = 300.0   # barrido de claves muertas cada 5 min
_TTL_CLAVE_SEG = 3600.0           # clave sin actividad en 1 h → se descarta


def verificar_limite(clave: str, max_intentos: int, ventana_seg: int) -> bool:
    """True si el intento está permitido (y lo cuenta); False si excede el
    límite dentro de la ventana deslizante."""
    global _ultima_limpieza
    ahora = time.monotonic()
    with _LOCK:
        marcas = _VENTANAS.setdefault(clave, [])
        corte = ahora - ventana_seg
        while marcas and marcas[0] < corte:
            marcas.pop(0)
        permitido = len(marcas) < max_intentos
        if permitido:
            marcas.append(ahora)

        # Autolimpieza periódica de claves sin actividad reciente
        if ahora - _ultima_limpieza > _INTERVALO_LIMPIEZA_SEG:
            _ultima_limpieza = ahora
            muertas = [k for k, v in _VENTANAS.items()
                       if not v or v[-1] < ahora - _TTL_CLAVE_SEG]
            for k in muertas:
                _VENTANAS.pop(k, None)
        return permitido
