"""
Seguridad y trazabilidad de firmas (capas 1-3).

Capa 1 — Procedencia: la identidad del firmante viene del JWT; se guarda un
         evento inmutable por cada acto de firma.
Capa 2 — Anti-reutilización: SHA-256 (exacto) + dHash perceptual para detectar
         que la firma de alguien fue recortada/copiada y subida por otro.
Capa 3 — Tamper-evidence: sello HMAC-SHA256 server-side sobre los campos
         canónicos del evento; cualquier alteración posterior rompe el sello.

Diseño defensivo: NINGUNA función aquí debe tumbar el flujo de negocio. La
decodificación de imagen y el dHash dependen de OpenCV y degradan con gracia
(devuelven None) si la imagen no se puede procesar. El SHA-256 y el HMAC solo
usan la stdlib, así que siempre están disponibles.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import uuid as _uuid
from datetime import datetime
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from app.models.firma_evento import FirmaEvento

logger = logging.getLogger("app.firma_seguridad")

# Clave dedicada para el sello; si no está configurada, cae al SECRET_KEY del
# backend (domain-separado por _DOMAIN para no colisionar con los JWT).
_HMAC_KEY: bytes = (os.getenv("FIRMA_HMAC_KEY") or os.getenv("SECRET_KEY") or "").encode()
_DOMAIN: bytes = b"ezyro.firma.sello.v1"

# Umbral de cercanía perceptual (distancia de Hamming sobre 64 bits). <= 10 ≈
# "el mismo trazo" tolerando reescalado/recorte/recompresión leve.
_PHASH_HAMMING_MAX = 10
# Cota de candidatos a comparar por phash (rendimiento). El SHA-256 exacto se
# resuelve por índice; el barrido perceptual se limita a los más recientes.
_PHASH_SCAN_LIMIT = 500


# ── Decodificación / huellas ────────────────────────────────────────────────

# Firmas mágicas de formatos de imagen comunes (para validar base64 crudo).
_MAGIC = (b"\x89PNG", b"\xff\xd8\xff", b"GIF8", b"BM", b"RIFF")


def _decode_firma(firma: Optional[str]) -> Tuple[Optional[bytes], str, Optional[str]]:
    """Devuelve (bytes_imagen | None, metodo, ref).

    - data-url base64  → bytes + metodo 'incrustada'.
    - base64 crudo     → bytes + metodo 'incrustada' (lo usa /guardar-firma).
    - http(s) url      → metodo 'guardada' (no se descarga: ref = url).
    - otro / vacío     → 'desconocido'.
    """
    if not firma:
        return None, "desconocido", None
    if firma.startswith("data:"):
        try:
            b64 = firma.split(",", 1)[1]
            return base64.b64decode(b64), "incrustada", None
        except Exception:
            return None, "incrustada", None
    if firma.startswith("http"):
        return None, "guardada", firma[:500]
    # Intentar base64 crudo (sin prefijo data:) — solo si decodifica a una imagen
    try:
        raw = base64.b64decode(firma, validate=True)
        if raw[:4] in _MAGIC or raw[:2] == b"BM" or raw[:3] == b"\xff\xd8\xff":
            return raw, "incrustada", None
    except Exception:
        pass
    return None, "desconocido", firma[:500]


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _dhash(data: bytes) -> Optional[str]:
    """dHash perceptual de 64 bits → 16 hex. None si la imagen no decodifica."""
    try:
        import cv2          # opencv-python-headless (en requirements)
        import numpy as np

        arr = np.frombuffer(data, dtype=np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
        if img is None:
            return None
        # 9x8 → 8 comparaciones por fila = 64 bits
        small = cv2.resize(img, (9, 8), interpolation=cv2.INTER_AREA)
        diff = small[:, 1:] > small[:, :-1]
        bits = 0
        for v in diff.flatten():
            bits = (bits << 1) | int(bool(v))
        return f"{bits:016x}"
    except Exception as exc:  # cv2 ausente o imagen corrupta → degradar
        logger.debug("dHash no disponible: %s", exc)
        return None


def hamming_hex(a: str, b: str) -> int:
    try:
        return bin(int(a, 16) ^ int(b, 16)).count("1")
    except Exception:
        return 64


# ── Sello de integridad (capa 3) ────────────────────────────────────────────

def _campos_sello(*, ev_id, empresa_id, firmante_id, firmante_usuario_id,
                  entidad_tipo, entidad_id, rol_firma, metodo, sha256, phash,
                  ts_iso) -> dict:
    return {
        "v": "1",
        "id": ev_id,
        "empresa_id": empresa_id,
        "firmante_id": firmante_id,
        "firmante_usuario_id": firmante_usuario_id,
        "entidad_tipo": entidad_tipo,
        "entidad_id": entidad_id,
        "rol_firma": rol_firma,
        "metodo": metodo,
        "sha256": sha256,
        "phash": phash,
        "ts": ts_iso,
    }


def sellar(campos: dict) -> str:
    payload = json.dumps(campos, sort_keys=True, separators=(",", ":"),
                         default=str).encode()
    return hmac.new(_HMAC_KEY, _DOMAIN + b"|" + payload, hashlib.sha256).hexdigest()


# ── API pública ─────────────────────────────────────────────────────────────

def registrar_firma(
    db: Session,
    *,
    empresa_id: str,
    firmante_id: Optional[str],
    firmante_usuario_id: Optional[str],
    entidad_tipo: str,
    entidad_id: str,
    rol_firma: Optional[str],
    firma: Optional[str],
    ip: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Optional[FirmaEvento]:
    """Crea (db.add, sin commit) el evento de firma con procedencia, huellas,
    detección de reutilización y sello HMAC. Devuelve el evento o None si algo
    inesperado falla (nunca propaga: la firma de negocio no debe romperse)."""
    try:
        raw, metodo, ref = _decode_firma(firma)
        sha = sha256_hex(raw) if raw else None
        ph = _dhash(raw) if raw else None

        sospechoso = False
        motivo: Optional[str] = None

        # La identidad para "otro firmante" se mide por usuario autenticado,
        # que está presente en TODOS los flujos (logística, permisos, trámites).
        # Capa 2a — duplicado EXACTO de otro firmante (índice por sha256)
        if sha and firmante_usuario_id:
            previo = (
                db.query(FirmaEvento)
                .filter(
                    FirmaEvento.empresa_id == empresa_id,
                    FirmaEvento.sha256 == sha,
                    FirmaEvento.firmante_usuario_id.isnot(None),
                    FirmaEvento.firmante_usuario_id != firmante_usuario_id,
                )
                .first()
            )
            if previo:
                sospechoso = True
                motivo = (f"Imagen idéntica (sha256) a la firma de otro "
                          f"usuario (evento {previo.id}).")

        # Capa 2b — casi-duplicado PERCEPTUAL de otro firmante
        if not sospechoso and ph and firmante_usuario_id:
            candidatos = (
                db.query(FirmaEvento)
                .filter(
                    FirmaEvento.empresa_id == empresa_id,
                    FirmaEvento.phash.isnot(None),
                    FirmaEvento.firmante_usuario_id.isnot(None),
                    FirmaEvento.firmante_usuario_id != firmante_usuario_id,
                )
                .order_by(FirmaEvento.created_at.desc())
                .limit(_PHASH_SCAN_LIMIT)
                .all()
            )
            for c in candidatos:
                if hamming_hex(ph, c.phash) <= _PHASH_HAMMING_MAX:
                    sospechoso = True
                    motivo = (f"Firma visualmente casi idéntica a la de otro "
                              f"firmante (evento {c.id}, hamming≤{_PHASH_HAMMING_MAX}).")
                    break

        ev_id = str(_uuid.uuid4())
        ts = datetime.utcnow()
        sello = sellar(_campos_sello(
            ev_id=ev_id, empresa_id=empresa_id, firmante_id=firmante_id,
            firmante_usuario_id=firmante_usuario_id,
            entidad_tipo=entidad_tipo, entidad_id=entidad_id, rol_firma=rol_firma,
            metodo=metodo, sha256=sha, phash=ph, ts_iso=ts.isoformat(),
        ))

        ev = FirmaEvento(
            id=ev_id, empresa_id=empresa_id,
            firmante_id=firmante_id, firmante_usuario_id=firmante_usuario_id,
            entidad_tipo=entidad_tipo, entidad_id=entidad_id, rol_firma=rol_firma,
            metodo=metodo, sha256=sha, phash=ph, firma_ref=ref,
            ip=ip, user_agent=(user_agent or "")[:500] or None,
            sello_hmac=sello, sospechoso=sospechoso, motivo_sospecha=motivo,
            created_at=ts,
        )
        db.add(ev)
        if sospechoso:
            logger.warning("Firma sospechosa empresa=%s entidad=%s/%s firmante=%s: %s",
                           empresa_id, entidad_tipo, entidad_id, firmante_id, motivo)
        return ev
    except Exception:
        logger.exception("registrar_firma falló (se omite el evento, la firma "
                          "de negocio continúa)")
        return None


def verificar_evento(ev: FirmaEvento) -> bool:
    """Recalcula el sello sobre los campos almacenados y lo compara en tiempo
    constante. False = el registro fue alterado (o no tenía sello)."""
    if not ev or not ev.sello_hmac:
        return False
    esperado = sellar(_campos_sello(
        ev_id=ev.id, empresa_id=ev.empresa_id, firmante_id=ev.firmante_id,
        firmante_usuario_id=ev.firmante_usuario_id,
        entidad_tipo=ev.entidad_tipo, entidad_id=ev.entidad_id,
        rol_firma=ev.rol_firma, metodo=ev.metodo, sha256=ev.sha256,
        phash=ev.phash, ts_iso=ev.created_at.isoformat() if ev.created_at else "",
    ))
    return hmac.compare_digest(esperado, ev.sello_hmac)
