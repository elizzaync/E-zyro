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
# PROTOCOLO POZO A TIERRA  (plantilla limpia — sin contenido previo)
# ────────────────────────────────────────────────────────────────────
# Coordenadas (pt, A4 = 595×842, origen = esquina sup-izq).
# Ajustar con las constantes _PZ_* si la plantilla cambia de layout.

_PZ_FONT      = "helv"   # Helvetica regular
_PZ_FONT_B    = "hebo"   # Helvetica Bold
_PZ_SZ        = 9        # tamaño base
_PZ_COLOR     = (0, 0, 0)

# Cabecera
_PZ_UBICACION_X,       _PZ_UBICACION_Y       = 150, 155
_PZ_FECHA_ACT_X,       _PZ_FECHA_ACT_Y       = 450, 140
_PZ_FECHA_EJEC_X,      _PZ_FECHA_EJEC_Y      = 450, 168

# Fila de medición (tabla central)
_PZ_NRO_X,             _PZ_NRO_Y             = 130, 360
_PZ_FECHA_MED_X,       _PZ_FECHA_MED_Y       = 280, 360
_PZ_RESULTADO_X,       _PZ_RESULTADO_Y       = 450, 360

# Horas de trabajo
_PZ_H_INICIO_X,        _PZ_H_INICIO_Y        = 130, 620
_PZ_H_TERMINO_X,       _PZ_H_TERMINO_Y       = 130, 635

# Técnico ejecutor
_PZ_TECNICO_X,         _PZ_TECNICO_Y         = 100, 750

# Firma del técnico (rectángulo sobre el nombre)
_PZ_FIRMA_RECT = fitz.Rect(90, 700, 200, 740)

# Evidencia fotográfica — 3 imágenes en fila
_PZ_IMG_Y0, _PZ_IMG_Y1 = 400, 520
_PZ_IMG_RECTS = [
    fitz.Rect( 50, _PZ_IMG_Y0, 200, _PZ_IMG_Y1),   # proc 1
    fitz.Rect(220, _PZ_IMG_Y0, 370, _PZ_IMG_Y1),   # proc 4
    fitz.Rect(390, _PZ_IMG_Y0, 540, _PZ_IMG_Y1),   # proc 7
]


def generar_protocolo_pozo(
    ubicacion:           str,
    numero_pozo:         str,
    fecha_actualizacion: str,       # hoy (auto)
    fecha_ejecucion:     str,       # cuándo se realizó el trabajo
    fecha_hora_medicion: str,       # "07/06/2026  08:30"
    resultado_medicion:  str,       # "3.45 Ω"
    hora_inicio:         str,
    hora_termino:        str,
    nombre_tecnico:      str,
    firma_tecnico:       str | None = None,
    fotos_procedimientos: list | None = None,
) -> bytes:
    """
    Inyecta campos en la plantilla limpia Protocolo_Pozo_444.pdf.
    fotos_procedimientos: lista con 3 elementos (URL Cloudinary o base64)
    correspondientes a los procedimientos 1, 4 y 7 de la inspección.
    """
    doc  = fitz.open(_POZO_TPL)
    page = doc[0]

    fa = {"fontname": _PZ_FONT, "fontsize": _PZ_SZ, "color": _PZ_COLOR}

    # ── Cabecera ──────────────────────────────────────────────────────
    page.insert_text(fitz.Point(_PZ_UBICACION_X,  _PZ_UBICACION_Y),  ubicacion.upper(),           **fa)
    page.insert_text(fitz.Point(_PZ_FECHA_ACT_X,  _PZ_FECHA_ACT_Y),  fecha_actualizacion,         **fa)
    page.insert_text(fitz.Point(_PZ_FECHA_EJEC_X, _PZ_FECHA_EJEC_Y), fecha_ejecucion,             **fa)

    # ── Fila de medición ──────────────────────────────────────────────
    page.insert_text(fitz.Point(_PZ_NRO_X,        _PZ_NRO_Y),        numero_pozo,                 **fa)
    page.insert_text(fitz.Point(_PZ_FECHA_MED_X,  _PZ_FECHA_MED_Y),  fecha_hora_medicion,         **fa)
    page.insert_text(fitz.Point(_PZ_RESULTADO_X,  _PZ_RESULTADO_Y),  resultado_medicion,
                     fontname=_PZ_FONT_B, fontsize=_PZ_SZ + 1, color=_PZ_COLOR)

    # ── Horas ─────────────────────────────────────────────────────────
    page.insert_text(fitz.Point(_PZ_H_INICIO_X,   _PZ_H_INICIO_Y),   hora_inicio,                 **fa)
    page.insert_text(fitz.Point(_PZ_H_TERMINO_X,  _PZ_H_TERMINO_Y),  hora_termino,                **fa)

    # ── Técnico ejecutor ──────────────────────────────────────────────
    page.insert_text(fitz.Point(_PZ_TECNICO_X,    _PZ_TECNICO_Y),    nombre_tecnico.upper(),
                     fontname=_PZ_FONT_B, fontsize=8, color=_PZ_COLOR)

    # ── Firma del técnico ─────────────────────────────────────────────
    raw_firma = _img_bytes(firma_tecnico)
    if raw_firma:
        try:
            page.insert_image(_PZ_FIRMA_RECT, stream=raw_firma, keep_proportion=True)
        except Exception as e:
            logger.warning("[pozo] No se pudo insertar firma técnico: %s", e)

    # ── Evidencia fotográfica (3 fotos en fila) ───────────────────────
    fotos = list(fotos_procedimientos or [])
    for i, rect in enumerate(_PZ_IMG_RECTS):
        raw = _img_bytes(fotos[i]) if i < len(fotos) else None
        if raw:
            try:
                page.insert_image(rect, stream=raw, keep_proportion=True)
            except Exception as e:
                logger.warning("[pozo] No se pudo insertar foto %d: %s", i + 1, e)

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
