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


def _center(page: fitz.Page, x0: float, x1: float, y: float, text: str,
            size: float = 7.5, bold: bool = False) -> None:
    """Inserta texto centrado horizontalmente entre x0 y x1, baseline en y."""
    if not text:
        return
    fn = _PZ_FONT_B if bold else _PZ_FONT
    tw = fitz.get_text_length(text, fontname=fn, fontsize=size)
    x = max(x0 + 1.0, (x0 + x1 - tw) / 2.0)
    page.insert_text(fitz.Point(x, y), text, fontname=fn, fontsize=size, color=_PZ_COLOR)


# ────────────────────────────────────────────────────────────────────
# PROTOCOLO POZO A TIERRA  (plantilla limpia — sin contenido previo)
# ────────────────────────────────────────────────────────────────────
# Coordenadas (pt, A4 = 595×842, origen = esquina sup-izq).
# Ajustar con las constantes _PZ_* si la plantilla cambia de layout.

_PZ_FONT      = "helv"   # Helvetica regular
_PZ_FONT_B    = "hebo"   # Helvetica Bold
_PZ_COLOR     = (0, 0, 0)

# ── Cabecera (coordenadas calibradas con inspect_pozo.py) ─────────────
# "Fecha:" pequeña (sz=6)  y=50-60,  x=437  → fecha_ejecucion a la derecha
_PZ_FECHA_EJEC_X,      _PZ_FECHA_EJEC_Y      = 461,  58
# "Fecha actualización:" y=77-87,  x=363   → fecha_actualizacion a la derecha
_PZ_FECHA_ACT_X,       _PZ_FECHA_ACT_Y       = 431,  86
# "Área / Ubicación:"   y=104-114, x=32    → valor a la derecha del ":"
_PZ_UBICACION_X,       _PZ_UBICACION_Y       = 106, 112

# ── CERTIFICADO Nº — espacio en blanco tras "Nº" (x=330 a x=567, celda y=126-143) ──
_PZ_CERT_RECT             = fitz.Rect(330, 126, 567, 143)
_PZ_CERT_X0, _PZ_CERT_X1 = 330.0, 567.0
_PZ_CERT_Y                = 139

# ── Fila de medición — columnas exactas (extraídas del template con get_drawings) ──
# data row: y=290.09–309.05, baseline≈304
_PZ_DATA_Y     = 304
_PZ_COL_UBIC   = (28.68,  183.89)   # UBICACIÓN
_PZ_COL_NRO    = (184.61, 235.01)   # N° DE POZO
_PZ_COL_FECHA  = (235.73, 376.99)   # FECHA Y HORA
_PZ_COL_RESULT = (377.71, 567.12)   # RESULTADO

# ── Horas — columna "Valor" (header "Valor" en x=169 → columna x=130-235) ──
_PZ_HORA_X0, _PZ_HORA_X1 = 130.0, 235.0
_PZ_H_INICIO_Y            = 492
_PZ_H_TERMINO_Y           = 505

# ── Técnico ejecutor — columna izquierda (x=28-218), baseline=581 → top≈575 = igual a "(Edward Galindo)" ──
_PZ_TEC_X0, _PZ_TEC_X1   = 28.68, 218.0
_PZ_TEC_Y                 = 581

# Firma del técnico — imagen en el área en blanco del técnico ejecutor
_PZ_FIRMA_RECT = fitz.Rect(50, 587, 215, 647)

# ── Evidencia fotográfica — entre "EVIDENCIA GRÁFICA" (y=314-324) y "VERIFICACIÓN" (y=457-467) ──
_PZ_IMG_Y0, _PZ_IMG_Y1 = 326, 455
_PZ_IMG_RECTS = [
    fitz.Rect( 32, _PZ_IMG_Y0, 207, _PZ_IMG_Y1),   # proc 1
    fitz.Rect(211, _PZ_IMG_Y0, 386, _PZ_IMG_Y1),   # proc 4
    fitz.Rect(390, _PZ_IMG_Y0, 563, _PZ_IMG_Y1),   # proc 7
]


def generar_protocolo_pozo(
    nombre_pozo:         str,       # va en "CERTIFICADO N° …" (ej: "POZO A TIERRA - SALA ELÉCTRICA")
    ubicacion:           str,       # "Área / Ubicación" y columna UBICACIÓN de tabla
    numero_pozo:         str,       # solo columna N° DE POZO de tabla (ej: "PT-01")
    fecha_actualizacion: str,       # hoy (auto)
    fecha_ejecucion:     str,       # "dd/mm/yyyy" — solo fecha
    fecha_hora_medicion: str,       # "dd/mm/yyyy  HH:MM" — fecha y hora
    resultado_medicion:  str,       # "3.45 Ω"
    hora_inicio:         str,       # "HH:MM"
    hora_termino:        str,       # "HH:MM"
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

    fa7  = {"fontname": _PZ_FONT,   "fontsize": 7, "color": _PZ_COLOR}
    fa6  = {"fontname": _PZ_FONT,   "fontsize": 6, "color": _PZ_COLOR}
    fa8b = {"fontname": _PZ_FONT_B, "fontsize": 8, "color": _PZ_COLOR}
    fa7b = {"fontname": _PZ_FONT_B, "fontsize": 7, "color": _PZ_COLOR}

    # ── Cabecera ──────────────────────────────────────────────────────
    # "Fecha:" pequeña (y=50-60): fecha de ejecución
    page.insert_text(fitz.Point(_PZ_FECHA_EJEC_X, _PZ_FECHA_EJEC_Y), fecha_ejecucion,      **fa6)
    # "Fecha actualización:" (y=77-87): fecha de hoy (auto)
    page.insert_text(fitz.Point(_PZ_FECHA_ACT_X,  _PZ_FECHA_ACT_Y),  fecha_actualizacion,  **fa7)
    # "Área / Ubicación:" (y=104-114): valor a la derecha del ":"
    page.insert_text(fitz.Point(_PZ_UBICACION_X,  _PZ_UBICACION_Y),  ubicacion.upper(),    **fa7)

    # ── Nombre del pozo — centrado en espacio tras "Nº" (x=330-567) ────
    _white_rect(page, _PZ_CERT_RECT)
    _center(page, _PZ_CERT_X0, _PZ_CERT_X1, _PZ_CERT_Y, nombre_pozo.upper(), size=8, bold=True)

    # ── Fila de medición — valores centrados en cada columna ─────────
    _center(page, *_PZ_COL_UBIC,   _PZ_DATA_Y, ubicacion.upper())
    _center(page, *_PZ_COL_NRO,    _PZ_DATA_Y, numero_pozo)
    _center(page, *_PZ_COL_FECHA,  _PZ_DATA_Y, fecha_hora_medicion)
    _center(page, *_PZ_COL_RESULT, _PZ_DATA_Y, resultado_medicion, size=8, bold=True)

    # ── Horas (verificación) — centradas en columna "Valor" ──────────
    _center(page, _PZ_HORA_X0, _PZ_HORA_X1, _PZ_H_INICIO_Y,  hora_inicio)
    _center(page, _PZ_HORA_X0, _PZ_HORA_X1, _PZ_H_TERMINO_Y, hora_termino)

    # ── Técnico ejecutor — "(NOMBRE)" centrado bajo "TECNICO EJECUTOR E-SYSTEM" ──
    if nombre_tecnico:
        _center(page, _PZ_TEC_X0, _PZ_TEC_X1, _PZ_TEC_Y,
                f"({nombre_tecnico.upper()})", size=6)

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
    nombre_tablero: str,
    fecha:          str,   # "17/06/2026"
    razon_social:   str,
    ubicacion:      str,
    # parámetros ignorados (conservados por compatibilidad con llamadas antiguas)
    personal_tecnico:  str       = "",
    firma_verificador: str | None = None,
    firma_gerente:     str | None = None,
) -> bytes:
    """
    Inyecta los 4 campos sobre Certificado_Operatividad.pdf.

    Coordenadas calibradas con inspect_pdf.py (A4 = 595×842 pt):
      "Fecha:"        label  y=188-202
      "Razón Social:" label  y=231-246
      "Ubicación:"    label  y=275-290
      "Personal Téc." label  y=319-334  ← hardcodeado en plantilla, no se toca
    Los valores se insertan en los espacios en blanco que siguen a cada etiqueta.
    """
    doc = fitz.open(_CERT_OPE_TPL)
    page = doc[0]

    # ── Nombre del tablero ───────────────────────────────────────────
    # Espacio en blanco ANTES de la etiqueta "Fecha:" (y=188).
    # Cuerpo del texto termina en y≈144; nombre va en y≈152-185.
    _white_rect(page, fitz.Rect(43, 152, 555, 186))
    _insert(page, 45, 176, nombre_tablero.upper(), size=12)

    # ── Fecha ────────────────────────────────────────────────────────
    # Espacio en blanco entre "Fecha:" (bottom y=202) y "Razón Social:" (top y=231).
    _white_rect(page, fitz.Rect(43, 203, 300, 229))
    _insert(page, 45, 222, fecha, size=11)

    # ── Razón Social ─────────────────────────────────────────────────
    # Espacio en blanco entre "Razón Social:" (bottom y=246) y "Ubicación:" (top y=275).
    _white_rect(page, fitz.Rect(43, 247, 555, 273))
    _insert(page, 45, 265, razon_social, size=11)

    # ── Ubicación ────────────────────────────────────────────────────
    # Espacio en blanco entre "Ubicación:" (bottom y=290) y "Personal Téc." (top y=319).
    _white_rect(page, fitz.Rect(43, 291, 555, 317))
    _insert(page, 45, 309, ubicacion, size=11)

    buf = io.BytesIO()
    doc.save(buf, garbage=4, deflate=True)
    doc.close()
    buf.seek(0)
    return buf.read()
