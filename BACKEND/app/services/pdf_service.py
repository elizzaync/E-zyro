"""
Servicio de generación de PDF mediante Overlay (Estampado).

Flujo:
1. reportlab dibuja los datos sobre un canvas transparente (BytesIO).
2. pypdf fusiona ese canvas sobre la plantilla base (plantilla_permiso.pdf.pdf).
3. Se devuelven los bytes del PDF resultante para subir a Cloudinary.

CALIBRACIÓN DE COORDENADAS:
Las coordenadas X/Y están en puntos PDF (1 pt = 1/72 pulgada).
Origen: esquina inferior-izquierda de la página.
A4 = 595 x 842 pts.
Ajusta los valores en COORDS si la plantilla cambia de maquetación.
"""

import io
import os
import base64
from typing import Optional

from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
import pypdf

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_PATH = os.path.join(BASE_DIR, "assets", "plantilla_permiso.pdf.pdf")

# ── Coordenadas del overlay ──────────────────────────────────────────────────
# Cada entrada es (x, y) en puntos PDF desde la esquina inferior-izquierda.
# Calibrar con la plantilla real si los textos no caen en el campo correcto.

COORDS = {
    # Fila: FECHA | ÁREA | PUESTO
    "fecha":  (105, 718),
    "area":   (285, 718),
    "puesto": (455, 718),

    # Nombre del colaborador
    "nombre": (185, 695),

    # Grid de tipos de permiso — marca 'X' sobre cada checkbox
    # 3 columnas × 3 filas + 1 fila para "otros"
    "chk_permiso_personal":         ( 45, 654),
    "chk_comision_trabajo":         (225, 654),
    "chk_cita_essalud":             (405, 654),
    "chk_permanencia_capacitacion": ( 45, 630),
    "chk_permanencia_extra":        (225, 630),
    "chk_recuperacion":             (405, 630),
    "chk_vacaciones":               ( 45, 606),
    "chk_dias_libres":              (225, 606),
    "chk_transferencia":            (405, 606),
    "chk_otros":                    ( 45, 582),

    # Horario
    "hora_inicio": (135, 558),
    "hora_fin":    (315, 558),

    # Concepto (vacaciones / días libres)
    "total_dias":   ( 90, 534),
    "periodo":      (250, 534),
    "fecha_inicio": ( 85, 510),
    "fecha_fin":    (270, 510),

    # Sustento / motivo
    "motivo": (60, 470),

    # Firma del colaborador (imagen PNG centrada en el espacio)
    "firma_x":      ( 80, 165),
    "firma_w":      110,
    "firma_h":       50,
}

# Tipos que se envían desde el frontend → clave de checkbox en COORDS
TIPO_A_CHK = {
    "permiso_personal":         "chk_permiso_personal",
    "comision_trabajo":         "chk_comision_trabajo",
    "cita_essalud":             "chk_cita_essalud",
    "permanencia_capacitacion": "chk_permanencia_capacitacion",
    "permanencia_extra":        "chk_permanencia_extra",
    "recuperacion":             "chk_recuperacion",
    "vacaciones":               "chk_vacaciones",
    "dias_libres":              "chk_dias_libres",
    "transferencia":            "chk_transferencia",
    "otros":                    "chk_otros",
    # Los tipos que se mapean a 'permiso' en BD también necesitan su checkbox
    "permiso":                  "chk_permiso_personal",
}


def _crear_overlay(datos: dict) -> bytes:
    """Genera un PDF en memoria con los datos escritos sobre un canvas vacío."""
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    c.setFont("Helvetica", 9)

    tipo_original: str = datos.get("tipo_original", datos.get("tipo", ""))

    # Fila de cabecera
    if datos.get("fecha_inicio"):
        c.drawString(*COORDS["fecha"], datos["fecha_inicio"])
    if datos.get("area"):
        c.drawString(*COORDS["area"], str(datos["area"]).upper())
    if datos.get("cargo"):
        c.drawString(*COORDS["puesto"], str(datos["cargo"]).upper())

    # Nombre
    if datos.get("nombre"):
        c.setFont("Helvetica-Bold", 9)
        c.drawString(*COORDS["nombre"], str(datos["nombre"]).upper())
        c.setFont("Helvetica", 9)

    # Marca X en el checkbox del tipo de permiso
    chk_key = TIPO_A_CHK.get(tipo_original)
    if chk_key and chk_key in COORDS:
        c.setFont("Helvetica-Bold", 10)
        c.drawString(*COORDS[chk_key], "X")
        c.setFont("Helvetica", 9)

    # Horario
    if datos.get("hora_inicio"):
        c.drawString(*COORDS["hora_inicio"], datos["hora_inicio"])
    if datos.get("hora_fin"):
        c.drawString(*COORDS["hora_fin"], datos["hora_fin"])

    # Concepto (días / período / fechas)
    if datos.get("total_dias") is not None:
        c.drawString(*COORDS["total_dias"], str(datos["total_dias"]))
    if datos.get("periodo"):
        c.drawString(*COORDS["periodo"], str(datos["periodo"]))
    if datos.get("fecha_inicio"):
        c.drawString(*COORDS["fecha_inicio"], datos["fecha_inicio"])
    if datos.get("fecha_fin"):
        c.drawString(*COORDS["fecha_fin"], datos["fecha_fin"])

    # Sustento (motivo) — truncado para que quepa en el espacio
    motivo = datos.get("motivo") or ""
    if motivo:
        c.drawString(*COORDS["motivo"], motivo[:120])

    # Firma (imagen PNG/JPG en base64)
    firma_b64: Optional[str] = datos.get("firma_base64")
    if firma_b64 and firma_b64.startswith("data:"):
        try:
            _, encoded = firma_b64.split(",", 1)
            img_bytes = base64.b64decode(encoded)
            img_buf = io.BytesIO(img_bytes)
            c.drawImage(
                img_buf,
                x=COORDS["firma_x"][0],
                y=COORDS["firma_x"][1],
                width=COORDS["firma_w"],
                height=COORDS["firma_h"],
                preserveAspectRatio=True,
                mask="auto",
            )
        except Exception:
            pass  # Firma inválida no rompe el PDF

    c.save()
    buf.seek(0)
    return buf.read()


def generar_pdf_solicitud(datos: dict) -> bytes:
    """
    Genera el PDF final estampando los datos sobre la plantilla base.

    Args:
        datos: dict con claves:
            tipo_original, nombre, cargo, area,
            fecha_inicio, fecha_fin, hora_inicio, hora_fin,
            motivo, total_dias, periodo, firma_base64

    Returns:
        bytes del PDF resultante listo para subir a Cloudinary.
    """
    overlay_bytes = _crear_overlay(datos)

    template_reader = pypdf.PdfReader(TEMPLATE_PATH)
    overlay_reader  = pypdf.PdfReader(io.BytesIO(overlay_bytes))

    writer = pypdf.PdfWriter()
    page   = template_reader.pages[0]
    page.merge_page(overlay_reader.pages[0])
    writer.add_page(page)

    output = io.BytesIO()
    writer.write(output)
    output.seek(0)
    return output.read()
