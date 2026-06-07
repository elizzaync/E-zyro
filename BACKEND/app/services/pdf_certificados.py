"""
Generación de certificados PDF mediante inyección sobre plantillas existentes.

Plantillas en assets/:
  - Protocolo_Pozo_444.pdf      → pozos a tierra
  - Certificado_Operatividad.pdf → tableros eléctricos

Coordenadas verificadas con PyMuPDF (A4 = 595×842 pt).
"""
from __future__ import annotations

import base64
import io
import logging
import os

import fitz  # PyMuPDF

logger = logging.getLogger(__name__)

_ASSETS = os.path.abspath("assets")
_POZO_TPL       = os.path.join(_ASSETS, "Protocolo_Pozo_444.pdf")
_CERT_OPE_TPL   = os.path.join(_ASSETS, "Certificado_Operatividad.pdf")

# ────────────────────────────────────────────────────────────────────
# Helpers internos
# ────────────────────────────────────────────────────────────────────

def _img_bytes(source: str | None) -> bytes | None:
    """
    Acepta URL de Cloudinary o string base64 (con o sin prefijo data-URI).
    Devuelve los bytes de la imagen, o None si el source está vacío.
    """
    if not source:
        return None
    if source.startswith("http://") or source.startswith("https://"):
        import requests
        try:
            resp = requests.get(source, timeout=10)
            resp.raise_for_status()
            return resp.content
        except Exception as e:
            logger.warning("No se pudo descargar imagen desde %s: %s", source, e)
            return None
    # Base64
    payload = source.split(",", 1)[1] if "," in source else source
    try:
        return base64.b64decode(payload)
    except Exception as e:
        logger.warning("Base64 inválido: %s", e)
        return None


def _white_rect(page: fitz.Page, rect: fitz.Rect) -> None:
    """Cubre un área con un rectángulo blanco para borrar texto/imágenes previos."""
    page.draw_rect(rect, fill=(1, 1, 1), color=(1, 1, 1))


def _insert(page: fitz.Page, x: float, y: float, text: str, size: float = 7.5) -> None:
    """Inserta texto con baseline en (x, y)."""
    page.insert_text(fitz.Point(x, y), text or "", fontname="helv", fontsize=size, color=(0, 0, 0))


# ────────────────────────────────────────────────────────────────────
# PROTOCOLO POZO A TIERRA
# ────────────────────────────────────────────────────────────────────
# Slots detectados (coordenadas en pt, origen = esquina sup-izq):
#
# Encabezado:
#   Área/Ubicación value  : x=102, y≈115  (row y0=111)
#
# Tabla VALORES DE MEDICIÓN (fila de datos y≈315):
#   UBICACIÓN             : x≈82,  baseline≈319
#   N° DE POZO            : x≈198, baseline≈319
#   FECHA Y HORA          : x≈263, baseline≈319
#   RESULTADO             : x≈432, baseline≈319
#
# Verificación:
#   Hora inicio           : x≈142, baseline≈509
#   Hora fin              : x≈142, baseline≈523
#
# EVIDENCIA GRÁFICA (3 slots):
#   rect1 : Rect(31,  349, 207, 468)
#   rect2 : Rect(213, 349, 388, 468)
#   rect3 : Rect(394, 349, 570, 468)
#
# Técnico ejecutor name:
#   y≈605, x≈71

def generar_protocolo_pozo(
    ubicacion:    str,
    nro_pozo:     str,
    fecha_hora:   str,   # "2026-06-07  08:30:00"
    resultado:    str,   # "3.45 Ω"
    hora_inicio:  str,
    hora_fin:     str,
    tecnico:      str,
    foto1:        str | None = None,
    foto2:        str | None = None,
    foto3:        str | None = None,
) -> bytes:
    """
    Inyecta campos en Protocolo_Pozo_444.pdf y devuelve bytes del PDF final.
    foto1/2/3: URL de Cloudinary o string base64 correspondientes a los
               procedimientos 1, 4 y 7 de la inspección.
    """
    doc = fitz.open(_POZO_TPL)
    page = doc[0]

    # ── Área/Ubicación en el encabezado ──────────────────────────────
    _white_rect(page, fitz.Rect(100, 105, 380, 118))
    _insert(page, 102, 115, f": {ubicacion.upper()}")

    # ── Tabla VALORES DE MEDICIÓN: fila de datos ──────────────────────
    _white_rect(page, fitz.Rect(78, 306, 575, 325))
    _insert(page, 82,  319, ubicacion.upper())
    _insert(page, 198, 319, nro_pozo)
    _insert(page, 263, 319, fecha_hora)
    _insert(page, 432, 319, resultado, size=9)  # resultado en 9pt igual que plantilla

    # ── Verificación: horas ──────────────────────────────────────────
    _white_rect(page, fitz.Rect(138, 499, 250, 512))
    _insert(page, 142, 509, hora_inicio)
    _white_rect(page, fitz.Rect(138, 513, 250, 526))
    _insert(page, 142, 523, hora_fin)

    # ── Técnico ejecutor ─────────────────────────────────────────────
    _white_rect(page, fitz.Rect(68, 598, 237, 610))
    _insert(page, 71, 607, f"({tecnico.upper()})", size=6)

    # ── EVIDENCIA GRÁFICA: 3 slots ────────────────────────────────────
    slots = [
        (fitz.Rect(31,  349, 207, 468), foto1),
        (fitz.Rect(213, 349, 388, 468), foto2),
        (fitz.Rect(394, 349, 570, 468), foto3),
    ]
    for rect, src in slots:
        raw = _img_bytes(src)
        if raw:
            _white_rect(page, rect)
            try:
                page.insert_image(rect, stream=raw, keep_proportion=True)
            except Exception as e:
                logger.warning("No se pudo insertar imagen en slot %s: %s", rect, e)

    buf = io.BytesIO()
    doc.save(buf, garbage=4, deflate=True)
    doc.close()
    buf.seek(0)
    return buf.read()


# ────────────────────────────────────────────────────────────────────
# CERTIFICADO DE OPERATIVIDAD (TABLEROS)
# ────────────────────────────────────────────────────────────────────
# Campos detectados (coordenadas en pt):
#
#   Nombre tablero       : x=45, y≈190  (fila y0=184)
#   Fecha                : x=45, y≈236  (fila y0=230)
#   Razón Social         : x=45, y≈275  (fila y0=269)
#   Ubicación            : x=45, y≈315  (fila y0=309, puede ser multilinea)
#   Personal Técnico     : x=45, y≈372  (fila y0=366)
#
#   Firma VERIFICADOR    : Rect(90, 720, 230, 763)
#   Firma GERENTE        : Rect(285, 720, 465, 763)

def generar_certificado_operatividad(
    nombre_tablero:  str,
    fecha:           str,          # "07/06/2026"
    razon_social:    str,
    ubicacion:       str,
    personal_tecnico: str,
    firma_verificador: str | None = None,   # URL o base64
    firma_gerente:     str | None = None,   # URL o base64
) -> bytes:
    """
    Inyecta campos en Certificado_Operatividad.pdf y devuelve bytes del PDF.
    """
    doc = fitz.open(_CERT_OPE_TPL)
    page = doc[0]

    # ── Nombre del tablero ───────────────────────────────────────────
    _white_rect(page, fitz.Rect(43, 178, 400, 196))
    _insert(page, 45, 191, nombre_tablero.upper(), size=12)

    # ── Fecha ────────────────────────────────────────────────────────
    _white_rect(page, fitz.Rect(43, 224, 250, 238))
    _insert(page, 45, 236, fecha, size=11)

    # ── Razón Social ─────────────────────────────────────────────────
    _white_rect(page, fitz.Rect(43, 263, 555, 277))
    _insert(page, 45, 275, razon_social, size=11)

    # ── Ubicación (puede ser larga, max 2 líneas) ─────────────────────
    _white_rect(page, fitz.Rect(43, 303, 555, 334))
    _insert(page, 45, 315, ubicacion, size=11)

    # ── Personal Técnico ─────────────────────────────────────────────
    _white_rect(page, fitz.Rect(43, 360, 555, 374))
    _insert(page, 45, 372, personal_tecnico, size=11)

    # ── Firmas ───────────────────────────────────────────────────────
    firma_ver_rect = fitz.Rect(90,  720, 230, 763)
    firma_ger_rect = fitz.Rect(285, 720, 465, 763)

    for rect, src in [(firma_ver_rect, firma_verificador), (firma_ger_rect, firma_gerente)]:
        raw = _img_bytes(src)
        if raw:
            _white_rect(page, rect)
            try:
                page.insert_image(rect, stream=raw, keep_proportion=True)
            except Exception as e:
                logger.warning("No se pudo insertar firma en %s: %s", rect, e)

    buf = io.BytesIO()
    doc.save(buf, garbage=4, deflate=True)
    doc.close()
    buf.seek(0)
    return buf.read()
