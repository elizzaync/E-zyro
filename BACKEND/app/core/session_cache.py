"""
Caché en memoria para validar que una sesión (token) sigue activa.

Problema que resuelve
---------------------
`verificar_token` solo validaba la firma y expiración del JWT. Al cerrar una
sesión (logout o cierre remoto) se ponía `SesionUsuario.activa=False`, pero el
JWT seguía siendo aceptado hasta su expiración natural (4 h). Resultado: el
"cerrar sesión" no expulsaba de verdad ("entra y entra").

Solución
--------
`verificar_token` ahora consulta si la sesión sigue activa. Para no meter una
consulta a BD en CADA request (10k usuarios → carga inaceptable), cacheamos el
resultado por `token_hash` con un TTL corto (30 s) y lo invalidamos al instante
cuando se cierra la sesión.

- Caché HIT  → O(1), sin tocar BD.
- Caché MISS → 1 sola consulta a BD por token cada 30 s.
- Logout / cierre remoto → `invalidar()` marca el token como cerrado al instante.

Multi-worker (Railway)
----------------------
La caché es por proceso. Si el cierre lo procesa otro worker, el peor caso de
propagación entre workers es el TTL (30 s), porque al expirar la entrada se
revalida contra BD (que sí es compartida). El WebSocket de sesiones cubre la
expulsión instantánea de UX; esta caché es el respaldo de seguridad real.
Para expulsión instantánea cross-worker se podría añadir Redis pub/sub a futuro
sin cambiar esta interfaz.
"""
from __future__ import annotations

import hashlib
import threading
import time

from app.db.database import SessionLocal
from app.models.sesion_usuario import SesionUsuario

# TTL de la caché en segundos. Equilibra carga de BD vs. ventana de propagación
# de un cierre de sesión entre workers.
_TTL_SEGUNDOS = 30

# Tope defensivo de entradas para evitar crecimiento ilimitado de memoria.
_MAX_ENTRADAS = 100_000

# token_hash -> (es_valido: bool, expira_en: float[monotonic])
_cache: dict[str, tuple[bool, float]] = {}
_lock = threading.Lock()


def hash_token(token: str) -> str:
    """sha256 hex del token (mismo esquema usado al guardar SesionUsuario)."""
    return hashlib.sha256(token.encode()).hexdigest()


def sesion_activa(token_hash: str, usuario_id: str) -> bool:
    """True si existe una SesionUsuario activa para (usuario_id, token_hash).

    Usa caché con TTL; en MISS consulta BD una sola vez y memoiza el resultado.
    """
    ahora = time.monotonic()

    with _lock:
        entrada = _cache.get(token_hash)
        if entrada is not None and entrada[1] > ahora:
            return entrada[0]

    valido = _consultar_bd(token_hash, usuario_id)

    with _lock:
        if len(_cache) >= _MAX_ENTRADAS:
            _podar(ahora)
        _cache[token_hash] = (valido, ahora + _TTL_SEGUNDOS)

    return valido


def marcar_activa(token_hash: str) -> None:
    """Pre-cachea un token como válido (tras login / refresh) para que el primer
    request protegido no pague el MISS contra BD."""
    with _lock:
        _cache[token_hash] = (True, time.monotonic() + _TTL_SEGUNDOS)


def invalidar(token_hash: str) -> None:
    """Marca un token como cerrado al instante (logout / cierre remoto).

    Lo deja en la caché como inválido durante el TTL; al expirar se revalida
    contra BD (que ya tiene activa=False), por lo que sigue siendo inválido.
    """
    with _lock:
        _cache[token_hash] = (False, time.monotonic() + _TTL_SEGUNDOS)


def _consultar_bd(token_hash: str, usuario_id: str) -> bool:
    db = SessionLocal()
    try:
        existe = (
            db.query(SesionUsuario.id)
            .filter(
                SesionUsuario.usuario_id == usuario_id,
                SesionUsuario.token_hash == token_hash,
                SesionUsuario.activa == True,  # noqa: E712
            )
            .first()
        )
        return existe is not None
    except Exception:
        # Si la BD falla, NO bloqueamos al usuario (fail-open) para no tumbar
        # todo el backend ante un incidente transitorio de BD. El TTL hace que
        # la próxima revalidación corrija el estado.
        return True
    finally:
        db.close()


def _podar(ahora: float) -> None:
    """Elimina entradas expiradas. Debe llamarse con `_lock` tomado."""
    expirados = [k for k, (_, exp) in _cache.items() if exp <= ahora]
    for k in expirados:
        _cache.pop(k, None)
    # Si tras podar lo vencido aún estamos al tope, vaciamos por completo:
    # es seguro (solo provoca MISS y revalidación contra BD).
    if len(_cache) >= _MAX_ENTRADAS:
        _cache.clear()
