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
_PZ_COLOR     = (0, 0, 0)

# ── Cabecera (coordenadas calibradas con inspect_pozo.py) ─────────────
# "Fecha:" pequeña (sz=6)  y=50-60,  x=437  → fecha_ejecucion a la derecha
_PZ_FECHA_EJEC_X,      _PZ_FECHA_EJEC_Y      = 461,  58
# "Fecha actualización:" y=77-87,  x=363   → fecha_actualizacion a la derecha
_PZ_FECHA_ACT_X,       _PZ_FECHA_ACT_Y       = 431,  86
# "Área / Ubicación:"   y=104-114, x=32    → valor a la derecha del ":"
_PZ_UBICACION_X,       _PZ_UBICACION_Y       = 106, 112

# "CERTIFICADO Nº ___" — el template tiene "Nº" en x=321-329; insertamos DESPUÉS del espacio a x=332
# White rect cubre solo el área del placeholder (x=332 en adelante), sin pisar "Nº" del template
_PZ_NRO_CERT_RECT = fitz.Rect(332, 126, 567, 143)
_PZ_NRO_CERT_X,   _PZ_NRO_CERT_Y   = 333, 140

# ── Fila de medición — blank row entre headers y=282-291 y "EVIDENCIA GRÁFICA" y=314 ──
# Columnas (headers inspeccionados): UBICACIÓN x=87 | N°POZO x=190 | FECHA x=257 | RESULTADO x=424
_PZ_UBIC_MED_X,        _PZ_UBIC_MED_Y        =  90, 305   # columna UBICACIÓN
_PZ_NRO_X,             _PZ_NRO_Y             = 195, 305   # columna N° DE POZO
_PZ_FECHA_MED_X,       _PZ_FECHA_MED_Y       = 260, 305   # columna FECHA Y HORA
_PZ_RESULTADO_X,       _PZ_RESULTADO_Y       = 427, 305   # columna RESULTADO

# ── Horas — blank entre label y marca "C" (x=254) ─────────────────────
# "Hora de inicio"   y=484-494 → valor en x=150-250
# "Hora de termino"  y=497-507 → valor en x=150-250
_PZ_H_INICIO_X,        _PZ_H_INICIO_Y        = 150, 492
_PZ_H_TERMINO_X,       _PZ_H_TERMINO_Y       = 150, 505

# ── Técnico ejecutor — área en blanco tras "TECNICO EJECUTOR E-SYSTEM" y=567-576 ──
# Blank: y=586-654 (antes del pie de página "Fecha de Impresión" y=655-663)
_PZ_TECNICO_X,         _PZ_TECNICO_Y         = 55, 651

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

    # ── Nombre del pozo — se inserta después de "Nº" (x=332) sin pisar el template ──
    _white_rect(page, _PZ_NRO_CERT_RECT)
    page.insert_text(fitz.Point(_PZ_NRO_CERT_X, _PZ_NRO_CERT_Y), nombre_pozo.upper(), **fa8b)

    # ── Fila de medición (blank row y≈291-313, tras headers y=282-291) ─
    # Columnas: UBICACIÓN(x=87-190) | N°POZO(x=190-257) | FECHA Y HORA(x=257-424) | RESULTADO(x=424+)
    page.insert_text(fitz.Point(_PZ_UBIC_MED_X,   _PZ_UBIC_MED_Y),   ubicacion.upper(),    **fa7)
    page.insert_text(fitz.Point(_PZ_NRO_X,        _PZ_NRO_Y),        numero_pozo,          **fa7)
    page.insert_text(fitz.Point(_PZ_FECHA_MED_X,  _PZ_FECHA_MED_Y),  fecha_hora_medicion,  **fa7)
    page.insert_text(fitz.Point(_PZ_RESULTADO_X,  _PZ_RESULTADO_Y),  resultado_medicion,   **fa8b)

    # ── Horas (verificación) ──────────────────────────────────────────
    page.insert_text(fitz.Point(_PZ_H_INICIO_X,   _PZ_H_INICIO_Y),   hora_inicio,          **fa7)
    page.insert_text(fitz.Point(_PZ_H_TERMINO_X,  _PZ_H_TERMINO_Y),  hora_termino,         **fa7)

    # ── Técnico ejecutor ──────────────────────────────────────────────
    page.insert_text(fitz.Point(_PZ_TECNICO_X, _PZ_TECNICO_Y), nombre_tecnico.upper(), **fa7b)

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
