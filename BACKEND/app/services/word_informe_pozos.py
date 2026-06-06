"""
Generación del Informe General de Pozos a Tierra en formato Word (.docx).
Réplica exacta del sistema heredado.
"""
from __future__ import annotations

import io
import logging
import os
from datetime import date
from typing import Optional

import requests
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt, RGBColor, Cm
from PIL import Image as PILImage

logger = logging.getLogger(__name__)

# Ruta absoluta resuelta en tiempo de importación, relativa a este mismo archivo.
# assets/ vive en BACKEND/assets/ — dos niveles arriba de este archivo
_LOGO_HEADER = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "headerLogo.png")
)

_MESES_ES = [
    "", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
]

# Header column widths (cm) — 55 % / 20 % / 25 % of 17.6 cm
_H_COL0 = 9.68    # ~55 %
_H_COL1 = 3.52    # ~20 %
_H_COL2 = 4.40    # ~25 %

# Logo image width — fits inside merged cell (cols 1+2 = 7.92 cm)
_LOGO_W = Cm(4.0)   # headerLogo.png 445×274 → height ≈ 2.46 cm at this width

# Body table full width (cm)
_BW = 17.6


# ─────────────────────────────────────────────────────────────────────────────
# Low-level XML helpers
# ─────────────────────────────────────────────────────────────────────────────

def _set_cell_bg(cell, hex_color: str) -> None:
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def _cm_to_twips(cm: float) -> int:
    """1 cm = 567 twips (1440 twips/in ÷ 2.54 cm/in)."""
    return int(cm * 567)


def _set_col_width(cell, width_cm: float) -> None:
    """Set exact cell width in cm, removing any pre-existing <w:tcW>."""
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    for old in tcPr.findall(qn("w:tcW")):   # remove duplicates Word would ignore
        tcPr.remove(old)
    tcW = OxmlElement("w:tcW")
    tcW.set(qn("w:w"), str(_cm_to_twips(width_cm)))
    tcW.set(qn("w:type"), "dxa")
    tcPr.append(tcW)


def _set_tbl_grid(table, col_widths_cm: list[float]) -> None:
    """Inject a proper <w:tblGrid> so Word knows the column layout."""
    tbl = table._tbl
    for old in tbl.findall(qn("w:tblGrid")):
        tbl.remove(old)
    tblGrid = OxmlElement("w:tblGrid")
    for w in col_widths_cm:
        gc = OxmlElement("w:gridCol")
        gc.set(qn("w:w"), str(_cm_to_twips(w)))
        tblGrid.append(gc)
    tblPr = tbl.find(qn("w:tblPr"))
    if tblPr is not None:
        tblPr.addnext(tblGrid)
    else:
        tbl.insert(0, tblGrid)


def _no_borders(table) -> None:
    """Remove all visible borders from a table."""
    tbl = table._tbl
    tblPr = tbl.tblPr
    if tblPr is None:
        tblPr = OxmlElement("w:tblPr")
        tbl.insert(0, tblPr)
    tblBorders = OxmlElement("w:tblBorders")
    for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
        bd = OxmlElement(f"w:{side}")
        bd.set(qn("w:val"), "none")
        bd.set(qn("w:sz"), "0")
        bd.set(qn("w:space"), "0")
        bd.set(qn("w:color"), "auto")
        tblBorders.append(bd)
    tblPr.append(tblBorders)


def _single_borders(table, color="000000", sz=6) -> None:
    tbl = table._tbl
    tblPr = tbl.tblPr
    if tblPr is None:
        tblPr = OxmlElement("w:tblPr")
        tbl.insert(0, tblPr)
    tblBorders = OxmlElement("w:tblBorders")
    for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
        bd = OxmlElement(f"w:{side}")
        bd.set(qn("w:val"), "single")
        bd.set(qn("w:sz"), str(sz))
        bd.set(qn("w:space"), "0")
        bd.set(qn("w:color"), color)
        tblBorders.append(bd)
    tblPr.append(tblBorders)


def _set_table_width(table, width_cm: float) -> None:
    tbl = table._tbl
    tblPr = tbl.tblPr
    if tblPr is None:
        tblPr = OxmlElement("w:tblPr")
        tbl.insert(0, tblPr)
    for old in tblPr.findall(qn("w:tblW")):
        tblPr.remove(old)
    tblW = OxmlElement("w:tblW")
    tblW.set(qn("w:w"), str(_cm_to_twips(width_cm)))
    tblW.set(qn("w:type"), "dxa")
    tblPr.append(tblW)


def _run(para, text: str, bold=False, size_pt: float = 11,
         color: Optional[RGBColor] = None, italic=False):
    r = para.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.size = Pt(size_pt)
    if color:
        r.font.color.rgb = color
    return r


def _para_heading(doc: Document, text: str, size_pt: float, bold=True) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(p, text, bold=bold, size_pt=size_pt)


def _para_body(doc: Document, text: str, justify=True) -> None:
    p = doc.add_paragraph()
    if justify:
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    _run(p, text, size_pt=11)


def _para_bullet(doc: Document, text: str) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.left_indent = Cm(0.5)
    _run(p, "• " + text, size_pt=11)


def _gray_header_row(row, texts: list[str], size_pt=11) -> None:
    """Fill a table row with gray background and bold text."""
    for cell, txt in zip(row.cells, texts):
        _set_cell_bg(cell, "F2F2F2")
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(p, txt, bold=True, size_pt=size_pt)


# ─────────────────────────────────────────────────────────────────────────────
# Image helpers
# ─────────────────────────────────────────────────────────────────────────────

def _url_to_jpeg(url: str, timeout=15) -> Optional[io.BytesIO]:
    try:
        resp = requests.get(url, timeout=timeout)
        if resp.status_code != 200 or not resp.content:
            return None
        img = PILImage.open(io.BytesIO(resp.content))
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGBA")
            bg = PILImage.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg
        else:
            img = img.convert("RGB")
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85)
        buf.seek(0)
        return buf
    except Exception as exc:
        logger.warning("[word_pozos] imagen URL no descargada %s: %s", url, exc)
        return None


def _add_logo(para, path: str, width_cm: float) -> None:
    try:
        para.add_run().add_picture(path, width=Cm(width_cm))
    except Exception:
        para.add_run(path.split("/")[-1])


# ─────────────────────────────────────────────────────────────────────────────
# 1. HEADER (replicated in every page)
# ─────────────────────────────────────────────────────────────────────────────

def _build_header(doc: Document, oc: str, provincia: str) -> None:
    """
    Header table: 4 rows × 3 cols, repeats on every page.

    Col widths: 55 % / 20 % / 25 %  (≈ 9.68 / 3.52 / 4.40 cm = 17.6 cm total)

    Row 0: [Title text]          | [logo merged → cols 1+2]
    Row 1: [UBICACIÓN]           | "Elaborado por:" | "Oficina de proyectos"
    Row 2: [ESPECIALIDAD]        | "Revisado por:"  | "Oficina de proyectos"
    Row 3: [merged ↑ with row2] | "Aprobado por:"  | "Oficina de proyectos"
    """
    sec = doc.sections[0]
    sec.header_distance = Cm(0.5)
    header = sec.header

    for p in header.paragraphs:
        p.clear()

    # ── Create 4×3 table ────────────────────────────────────────────────────
    tbl = header.add_table(rows=4, cols=3, width=Cm(_H_COL0 + _H_COL1 + _H_COL2))
    _no_borders(tbl)
    tbl.alignment = WD_TABLE_ALIGNMENT.LEFT

    _set_tbl_grid(tbl, [_H_COL0, _H_COL1, _H_COL2])

    for ri in range(4):
        _set_col_width(tbl.cell(ri, 0), _H_COL0)
        _set_col_width(tbl.cell(ri, 1), _H_COL1)
        _set_col_width(tbl.cell(ri, 2), _H_COL2)

    oc_label   = oc or "SIN-OC"
    prov_label = (provincia or "").upper()

    # ── ROW 0: Title | Logo (merged cols 1+2) ───────────────────────────────
    tbl.cell(0, 1).merge(tbl.cell(0, 2))   # cols 1+2 → 7.92 cm combined

    c00 = tbl.cell(0, 0)
    c00.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    p00 = c00.paragraphs[0]
    p00.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p00,
         f"INFORME OC - {oc_label} MANTENIMIENTO PREVENTIVO POZO A TIERRA {prov_label}",
         bold=True, size_pt=8)

    logo_cell = tbl.cell(0, 1)
    logo_cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    # Clear any empty paragraph python-docx may have left after the merge
    for p in logo_cell.paragraphs:
        p.clear()
    p_logo = logo_cell.paragraphs[0]
    p_logo.alignment = WD_ALIGN_PARAGRAPH.CENTER
    if not os.path.exists(_LOGO_HEADER):
        raise FileNotFoundError(f"CRÍTICO: Python no encuentra el logo en el disco duro: {_LOGO_HEADER}")
    p_logo.add_run().add_picture(_LOGO_HEADER, width=_LOGO_W)

    # ── ROW 1: UBICACIÓN | Elaborado por | Oficina ───────────────────────────
    c10 = tbl.cell(1, 0)
    c10.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c10.paragraphs[0], f"UBICACIÓN: TALMA - {prov_label}", bold=True, size_pt=8)

    c11 = tbl.cell(1, 1)
    c11.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c11.paragraphs[0], "Elaborado por:", size_pt=8)

    c12 = tbl.cell(1, 2)
    c12.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c12.paragraphs[0], "Oficina de proyectos", size_pt=8)

    # ── ROW 2: ESPECIALIDAD | Revisado por | Oficina ─────────────────────────
    c20 = tbl.cell(2, 0)
    c20.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c20.paragraphs[0], "ESPECIALIDAD: INSTALACIONES ELÉCTRICAS", bold=True, size_pt=8)

    c21 = tbl.cell(2, 1)
    c21.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c21.paragraphs[0], "Revisado por:", size_pt=8)

    c22 = tbl.cell(2, 2)
    c22.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c22.paragraphs[0], "Oficina de proyectos", size_pt=8)

    # ── ROW 3: col 0 merged with row 2 | Aprobado por | Oficina ─────────────
    tbl.cell(2, 0).merge(tbl.cell(3, 0))   # vertical merge col 0 rows 2+3

    c31 = tbl.cell(3, 1)
    c31.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c31.paragraphs[0], "Aprobado por:", size_pt=8)

    c32 = tbl.cell(3, 2)
    c32.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _run(c32.paragraphs[0], "Oficina de proyectos", size_pt=8)


# ─────────────────────────────────────────────────────────────────────────────
# 2. PORTADA
# ─────────────────────────────────────────────────────────────────────────────

def _build_portada(doc: Document, oc: str, provincia: str, fecha_str: str) -> None:
    oc_label = oc or "SIN-OC"
    prov_label = (provincia or "").upper()

    doc.add_paragraph()
    doc.add_paragraph()
    doc.add_paragraph()

    for text, size in [
        (f"INFORME OC - {oc_label}", 18),
        ("MANTENIMIENTO PREVENTIVO POZO A TIERRA", 16),
        (f"TALMA - {prov_label}", 16),
    ]:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(p, text, bold=True, size_pt=size)

    doc.add_paragraph()
    doc.add_paragraph()

    today = date.today()
    p_fecha = doc.add_paragraph()
    p_fecha.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_fecha, f"{_MESES_ES[today.month]} – {today.year}", bold=True, size_pt=14)

    doc.add_paragraph()
    doc.add_paragraph()
    doc.add_paragraph()

    # Execution table
    tbl = doc.add_table(rows=2, cols=3)
    _single_borders(tbl)
    _set_table_width(tbl, _BW)
    _set_tbl_grid(tbl, [1.8, 8.8, 7.0])
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    for ri in range(2):
        _set_col_width(tbl.cell(ri, 0), 1.8)
        _set_col_width(tbl.cell(ri, 1), 8.8)
        _set_col_width(tbl.cell(ri, 2), 7.0)

    _gray_header_row(tbl.rows[0], ["N°", "DESCRIPCIÓN", "FECHA"])
    row1 = tbl.rows[1]
    for cell, txt in zip(row1.cells, ["01", "Fecha de ejecución de trabajo", "          /          /          "]):
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(p, txt, size_pt=11)

    doc.add_page_break()


# ─────────────────────────────────────────────────────────────────────────────
# 3. ÍNDICE
# ─────────────────────────────────────────────────────────────────────────────

_INDICE_ITEMS = [
    (0, "01. GENERALIDADES"),
    (0, "02. ALCANCE"),
    (0, "03. MARCO NORMATIVO"),
    (1, "03.1. NORMATIVA NACIONAL"),
    (2, "03.1.1. NORMA TÉCNICA DE CALIDAD DE LOS SERVICIOS ELÉCTRICOS"),
    (2, "03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006"),
    (2, "03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013"),
    (2, "03.1.4. NTP 370.052:1999 MATERIALES QUE CONSTITUYEN EL POZO DE PUESTA A TIERRA"),
    (1, "03.2. NORMATIVA INTERNACIONAL"),
    (2, "03.2.1. NORMA PARA LA SEGURIDAD ELÉCTRICA EN LUGARES DE TRABAJO (NFPA 70E)"),
    (2, "03.2.2. PRACTICAS RECOMENDADAS DE MANTENIMIENTO ELÉCTRICO (NFPA 70B)"),
    (2, "03.2.3. ANSI/NETA 2021: Standard for Acceptance Testing Specifications"),
    (2, "03.2.4. IEEE Std 81 - 2012: Guide for Measuring Earth Resistivity"),
    (0, "04. OBJETIVOS"),
    (0, "05. PROCEDIMIENTO SST IMPLÍCITOS"),
    (1, "05.1. USO DEL EPP DE ACUERDO AL TIPO DE TRABAJO"),
    (1, "05.2. PROCEDIMIENTO DE BLOQUEO Y ETIQUETADO LOTO"),
    (0, "06. PERSONAL COMPROMETIDO"),
    (0, "07. LISTA DE MATERIALES, HERRAMIENTAS Y EQUIPOS EMPLEADOS"),
    (0, "08. PROCEDIMIENTOS DE EJECUCIÓN"),
    (1, "08.1. PREPARATIVOS PREVIOS A LA EJECUCIÓN"),
    (1, "08.2. EJECUCIÓN DE TRABAJO"),
    (0, "09. EVIDENCIA FOTOGRÁFICA"),
    (0, "10. CONCLUSIONES"),
    (0, "11. OBSERVACIONES"),
    (0, "12. RECOMENDACIONES"),
]

_INDENT_MAP = {0: Cm(0), 1: Cm(0.5), 2: Cm(1.0)}


def _build_indice(doc: Document) -> None:
    p_title = doc.add_paragraph()
    _run(p_title, "Contenido", bold=True, size_pt=14)

    for level, text in _INDICE_ITEMS:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = _INDENT_MAP[level]
        _run(p, text, size_pt=11)

    doc.add_page_break()


# ─────────────────────────────────────────────────────────────────────────────
# Static section texts
# ─────────────────────────────────────────────────────────────────────────────

def _sec_generalidades(doc: Document, provincia: str) -> None:
    prov = (provincia or "").upper()
    _para_body(doc,
        "Los sistemas de puesta a tierra son una parte importante de un sistema eléctrico, "
        "la importancia de este trabajo es ayudar a proporcionar una mayor seguridad a los "
        "usuarios del local al direccionar cualquier contacto indirecto de energía eléctrica "
        "a la puesta a tierra más cercana."
    )
    _para_body(doc,
        "Este mantenimiento comprende al conjunto de actividades técnicas programadas "
        "destinadas a verificar, conservar y optimizar las condiciones operativas del "
        "sistema de puesta a tierra, garantizando que su resistencia eléctrica se mantenga "
        "dentro de los parámetros establecidos por la normativa vigente y por los "
        "requerimientos de seguridad de la instalación."
    )
    _para_body(doc,
        "Este procedimiento tiene como finalidad asegurar la correcta disipación de "
        "corrientes de falla y descargas."
    )
    _para_body(doc,
        f"El siguiente informe redacta de manera detallada los procedimientos empleados en "
        f"el mantenimiento preventivo de pozo a tierra en TALMA - {prov}. Los criterios de "
        f"ejecución, el personal comprometido, entre otros detalles considerados relevantes "
        f"para el conocimiento del cliente."
    )


def _sec_alcance(doc: Document, provincia: str) -> None:
    prov = (provincia or "").upper()
    _para_body(doc,
        f"El mantenimiento preventivo de pozo a tierra en TALMA - {prov} abarca la ejecución "
        f"de actividades que garanticen el correcto funcionamiento del sistema, así mismo, el "
        f"presente informe pretende explicar los procedimientos, materiales y equipos, así como "
        f"la normativa aplicada para el desarrollo satisfactorio del trabajo realizado."
    )


def _sec_marco_normativo(doc: Document) -> None:
    _para_heading(doc, "03.1. NORMATIVA NACIONAL", 12)
    norms_nacional = [
        ("03.1.1. NORMA TÉCNICA DE CALIDAD DE LOS SERVICIOS ELÉCTRICOS",
         "Con el fin de asegurar un nivel satisfactorio en la prestación de servicios eléctricos "
         "y garantizar a los usuarios un suministro eléctrico continuo, adecuado, confiable y "
         "oportuno, se aprobó la Norma Técnica de Calidad de los Servicios Eléctricos mediante "
         "Decreto Supremo N° 020-97-EM."),
        ("03.1.2. CÓDIGO NACIONAL DE ELECTRICIDAD – UTILIZACIÓN 2006",
         "El código bajo comentario contiene reglas preventivas frente a los peligros derivados "
         "del uso de la electricidad a fin de salvaguardar las condiciones de seguridad de las "
         "personas, flora, fauna, propiedad, ambiente y patrimonio cultural de la Nación."),
        ("03.1.3. REGLAMENTO DE SEGURIDAD Y SALUD EN EL TRABAJO CON ELECTRICIDAD 2013",
         "El presente reglamento es de aplicación obligatoria a todas las personas que participan "
         "en el desarrollo de las actividades relacionadas con el uso de la electricidad y/o con "
         "las instalaciones eléctricas."),
        ("03.1.4. NTP 370.052:1999 MATERIALES QUE CONSTITUYEN EL POZO DE PUESTA A TIERRA",
         "Establece las condiciones que deben cumplir los materiales a ser utilizados en los pozos "
         "a tierra de protección que emplean electrodos de cobre. Comprende material circundante, "
         "elementos químicos para reducir la resistencia y recomendaciones para medición."),
    ]
    for heading, body in norms_nacional:
        _para_heading(doc, heading, 11)
        _para_body(doc, body)

    _para_heading(doc, "03.2. NORMATIVA INTERNACIONAL", 12)
    norms_inter = [
        ("03.2.1. NORMA PARA LA SEGURIDAD ELÉCTRICA EN LUGARES DE TRABAJO (NFPA 70E)",
         "Norma sobre las prácticas de trabajo relacionadas con la seguridad eléctrica, "
         "requerimientos de mantenimiento relacionados con la seguridad y otros controles "
         "administrativos en los lugares de trabajo a fin de prevenir riesgos de la energía "
         "eléctrica."),
        ("03.2.2. PRACTICAS RECOMENDADAS DE MANTENIMIENTO ELÉCTRICO (NFPA 70B)",
         "Tienen como propósito reducir peligros a la vida y propiedad que resulten de la falla "
         "o malfuncionamiento del sistema y equipo eléctrico."),
        ("03.2.3. ANSI/NETA 2021: Standard for Acceptance Testing Specifications",
         "El propósito de estas especificaciones es asegurar que todo equipo eléctrico probado "
         "este operativo dentro de las tolerancias de la industria y del fabricante e instaladas "
         "de acuerdo con las especificaciones de diseño."),
        ("03.2.4. IEEE Std 81 - 2012: Guide for Measuring Earth Resistivity...",
         "Mediante esta guía se pretende obtener e interpretar datos precisos y confiables para "
         "las mediciones de campo relacionados a los sistemas de puesta a tierra."),
    ]
    for heading, body in norms_inter:
        _para_heading(doc, heading, 11)
        _para_body(doc, body)


def _sec_objetivos(doc: Document) -> None:
    bullets = [
        "Descartar valores elevados (fueras de rango).",
        "Disminuir el riesgo de descargas eléctricas hacia el personal.",
        "Verificar la calidad de la tierra y el estado de los conectores CU.",
        "Verificar el Ohmiaje obtenido responda a la normativa del código nacional de "
        "electricidad de acuerdo a la función del local (MAX 15 OHM).",
        "Cumplir con los estándares de seguridad y salud en el trabajo a fin de garantizar "
        "la ejecución responsable de las actividades.",
        "Mantener un área despejada finalizando el mantenimiento.",
    ]
    for b in bullets:
        _para_body(doc, b)


def _sec_epp_intro(doc: Document) -> None:
    _para_body(doc,
        "Cada trabajador cuenta con el EPP correspondiente a la tarea encargada de acuerdo "
        "al cuadro de puestos y funciones. Así mismo, se hace entrega de los EPPs indicados "
        "en la plataforma SST, los cuales son los indicados según el tipo de trabajo a realizar."
    )


def _sec_loto(doc: Document) -> None:
    _para_body(doc,
        "ESTE PASO DEBE REALIZARSE DE CARÁCTER OBLIGATORIO PARA CUALQUIER TRABAJO QUE IMPLIQUE "
        "RIESGO ELECTRICO."
    )
    for b in [
        "Aislar los circuitos a trabajar.",
        "Aplicación del dispositivo de bloqueo de fuentes de energía.",
        "Eliminar la energía almacenada a través de la línea tierra.",
    ]:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.5)
        _run(p, b, size_pt=11)


def _sec_personal_intro(doc: Document) -> None:
    _para_body(doc,
        "Se detalla el personal empleado para la ejecución del servicio, cargo y funciones "
        "acorde a las tareas que desarrollará."
    )


def _sec_preparativos(doc: Document) -> None:
    bullets = [
        "Verificar los permisos y autorizaciones.",
        "Elaboración de ATS.",
        "Verificar la zona de trabajo.",
        "Delimitar la zona de trabajo. Previa coordinación.",
        "Realizar un check list de la zona de trabajo.",
        "Revisar y elaborar el check list respectivo de las herramientas y equipos a utilizar en la tarea.",
    ]
    for b in bullets:
        _para_body(doc, b)


def _sec_ejecucion(doc: Document) -> None:
    bullets = [
        "Identificación del área del trabajo.",
        "Delimitar y señalizar lugar de trabajo.",
        "Realizar la limpieza de los mismos verificando que la caja de registro se encuentre en óptimas condiciones.",
        "Revisión de cables y verificación de estado de conductores.",
        "Realizar las mediciones correspondientes para obtener el valor inicial con el que se encontraron los pozos.",
        "De ser el caso, se procede a realizar el cambio del conector de Cu 3/4\".",
        "Preparación de solución química THORGEL.",
        "Aplicar dosis química de THORGEL, esperar que la tierra absorba la primera dosis y luego aplicar la segunda dosis.",
        "Medir el valor final del pozo a tierra y anotarlo para plasmarlo en los protocolos correspondientes.",
        "Limpieza y pintado de la tapa de registro dejando señalizado con el código de cada puesta a tierra.",
        "Cambiar a una señalética fotoluminiscente del sistema de puesta a tierra.",
        "Anotar las mediciones y observaciones para la realización posterior del Informe Técnico.",
        "Orden y limpieza en la zona de trabajo.",
    ]
    for b in bullets:
        _para_body(doc, b)


def _sec_conclusiones(doc: Document) -> None:
    bullets = [
        "Se ejecutó el mantenimiento preventivo según lo indicado en el presente informe.",
        "Se efectúa la limpieza y lijado del electrodo y los cables para asegurar su buen desempeño.",
        "Se reemplazó al conector para así lograr tener un mejor agarre entre el cable y la varilla "
        "que se encuentra en el pozo a tierra.",
        "Se optimizó la conexión entre la varilla y los cables para asegurar su buen desempeño.",
        "Se evaluó el estado de las instalaciones y condicionantes de trabajo previamente a cualquier "
        "intervención realizado por E-SYSTEM TIC determinando que permita dichas actividades.",
    ]
    for b in bullets:
        _para_body(doc, b)


def _sec_observaciones(doc: Document) -> None:
    _para_body(doc,
        "No se encontraron observaciones operativas que impidan el funcionamiento habitual del sistema."
    )


def _sec_recomendaciones(doc: Document) -> None:
    _para_body(doc,
        "Se recomienda realizar el mantenimiento preventivo de manera anual para asegurar "
        "la operatividad y conductividad ideal del sistema de puesta a tierra."
    )


# ─────────────────────────────────────────────────────────────────────────────
# Dynamic tables
# ─────────────────────────────────────────────────────────────────────────────

def _epp_es_necesario(nombre: str) -> str:
    n = nombre.upper()
    if "CARETA" in n or "ARNES" in n or "ARNÉS" in n:
        return "NO"
    return "SI – Plataforma SST"


def _table_epp(doc: Document, epps: list[str]) -> None:
    """2 cols: EPP | ES NECESARIO — 8.8+8.8 cm."""
    tbl = doc.add_table(rows=1 + len(epps), cols=2)
    _single_borders(tbl)
    _set_table_width(tbl, _BW)
    _set_tbl_grid(tbl, [8.8, 8.8])
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    for ri in range(1 + len(epps)):
        _set_col_width(tbl.cell(ri, 0), 8.8)
        _set_col_width(tbl.cell(ri, 1), 8.8)

    _gray_header_row(tbl.rows[0], ["EPP", "ES NECESARIO"])

    for i, epp in enumerate(epps, start=1):
        row = tbl.rows[i]
        row.cells[0].vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        row.cells[1].vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        _run(row.cells[0].paragraphs[0], epp, size_pt=11)
        _run(row.cells[1].paragraphs[0], _epp_es_necesario(epp), size_pt=11)


def _cargo_resp(rol: str) -> tuple[str, str]:
    if any(k in rol.lower() for k in ("supervis", "jefe", "lider", "líder")):
        return "Coordinador / Supervisor", "Supervisión de trabajos"
    return "Técnico ejecutor", "Ejecución de trabajos"


def _table_personal(doc: Document, personal: list[dict]) -> None:
    """4 cols: APELLIDOS | NOMBRE | CARGO | RESPONSABILIDADES — 4.4cm each."""
    tbl = doc.add_table(rows=1 + len(personal), cols=4)
    _single_borders(tbl)
    _set_table_width(tbl, _BW)
    _set_tbl_grid(tbl, [4.4, 4.4, 4.4, 4.4])
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    for ri in range(1 + len(personal)):
        for ci in range(4):
            _set_col_width(tbl.cell(ri, ci), 4.4)

    _gray_header_row(tbl.rows[0], ["APELLIDOS", "NOMBRE", "CARGO", "RESPONSABILIDADES"])

    for i, pers in enumerate(personal, start=1):
        nombre_full = pers.get("nombre", "").strip()
        parts = nombre_full.split(" ", 1)
        nombre   = parts[0].upper() if parts else ""
        apellido = (parts[1].upper() + ",") if len(parts) == 2 else ""
        cargo, resp = _cargo_resp(pers.get("rol", "Técnico"))
        row = tbl.rows[i]
        for ci, txt in enumerate([apellido, nombre, cargo, resp]):
            row.cells[ci].vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            _run(row.cells[ci].paragraphs[0], txt, size_pt=11)


def _table_materiales(doc: Document, materiales: list[dict]) -> None:
    """3 cols: MATERIALES | UNIDAD | CARACTERÍSTICAS — 7.1+3.5+7.0 cm."""
    tbl = doc.add_table(rows=1 + len(materiales), cols=3)
    _single_borders(tbl)
    _set_table_width(tbl, _BW)
    _set_tbl_grid(tbl, [7.1, 3.5, 7.0])
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    for ri in range(1 + len(materiales)):
        for ci, w in enumerate([7.1, 3.5, 7.0]):
            _set_col_width(tbl.cell(ri, ci), w)

    _gray_header_row(tbl.rows[0], ["MATERIALES", "UNIDAD", "CARACTERÍSTICAS"])

    for i, m in enumerate(materiales, start=1):
        row = tbl.rows[i]
        for ci, txt in enumerate([
            m.get("nombre", ""),
            m.get("unidad", "Und."),
            m.get("caracteristicas", "-"),
        ]):
            row.cells[ci].vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            _run(row.cells[ci].paragraphs[0], txt, size_pt=11)


def _table_herramientas(doc: Document, herramientas: list[dict]) -> None:
    """3 cols: HERRAMIENTAS Y EQUIPOS | UNIDAD | CARACTERÍSTICAS — 7.1+3.5+7.0 cm."""
    tbl = doc.add_table(rows=1 + len(herramientas), cols=3)
    _single_borders(tbl)
    _set_table_width(tbl, _BW)
    _set_tbl_grid(tbl, [7.1, 3.5, 7.0])
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    for ri in range(1 + len(herramientas)):
        for ci, w in enumerate([7.1, 3.5, 7.0]):
            _set_col_width(tbl.cell(ri, ci), w)

    _gray_header_row(tbl.rows[0], ["HERRAMIENTAS Y EQUIPOS", "UNIDAD", "CARACTERÍSTICAS"])

    for i, h in enumerate(herramientas, start=1):
        row = tbl.rows[i]
        nombre = h.get("nombre", "")
        if h.get("serie") and h["serie"] != "-":
            nombre = f"{nombre} {h['serie']}".strip()
        for ci, txt in enumerate([nombre, "1 Ud.", h.get("marca", "-")]):
            row.cells[ci].vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            _run(row.cells[ci].paragraphs[0], txt, size_pt=11)


# ─────────────────────────────────────────────────────────────────────────────
# Section 09: Evidence photos — 2x2 grid
# ─────────────────────────────────────────────────────────────────────────────

def _evidence_grid(doc: Document, evidencias_por_equipo: list[dict]) -> None:
    """
    For each equipment group: title + pairs of photos in 2-column tables.
    Single remaining photo goes in a 1-column table.
    """
    W_TWO = 8.8   # cm — width of each photo column (2-col grid)
    W_ONE = _BW   # cm — width for single-photo rows

    for grupo in evidencias_por_equipo:
        nombre = grupo.get("nombre", "Equipo")
        fotos  = grupo.get("fotos", [])

        p_t = doc.add_paragraph()
        p_t.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(p_t, f"EJECUCIÓN DE MANTENIMIENTO PREVENTIVO – {nombre.upper()}",
             bold=True, size_pt=11)

        if not fotos:
            _para_body(doc, "(Sin evidencias fotográficas registradas)", justify=False)
            doc.add_paragraph()
            continue

        i = 0
        while i < len(fotos):
            foto_izq = fotos[i]
            foto_der = fotos[i + 1] if i + 1 < len(fotos) else None

            if foto_der is None:
                tbl = doc.add_table(rows=2, cols=1)
                _single_borders(tbl, color="CCCCCC", sz=4)
                _set_table_width(tbl, W_ONE)
                _set_tbl_grid(tbl, [W_ONE])

                _set_col_width(tbl.cell(0, 0), W_ONE)
                _set_col_width(tbl.cell(1, 0), W_ONE)

                c_img = tbl.cell(0, 0)
                c_img.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                p_img = c_img.paragraphs[0]
                p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
                buf = _url_to_jpeg(foto_izq["url"])
                if buf:
                    p_img.add_run().add_picture(buf, width=Cm(16.0))
                else:
                    _run(p_img, "[imagen no disponible]", size_pt=9)

                c_obs = tbl.cell(1, 0)
                p_obs = c_obs.paragraphs[0]
                p_obs.alignment = WD_ALIGN_PARAGRAPH.CENTER
                obs = foto_izq.get("obs", "")
                _run(p_obs, obs, size_pt=9)
            else:
                tbl = doc.add_table(rows=2, cols=2)
                _single_borders(tbl, color="CCCCCC", sz=4)
                _set_table_width(tbl, _BW)
                _set_tbl_grid(tbl, [W_TWO, W_TWO])

                for ri in range(2):
                    for ci in range(2):
                        _set_col_width(tbl.cell(ri, ci), W_TWO)

                for ci, foto in enumerate([foto_izq, foto_der]):
                    c_img = tbl.cell(0, ci)
                    c_img.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                    p_img = c_img.paragraphs[0]
                    p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    buf = _url_to_jpeg(foto["url"])
                    if buf:
                        p_img.add_run().add_picture(buf, width=Cm(8.0))
                    else:
                        _run(p_img, "[imagen no disponible]", size_pt=9)

                    c_obs = tbl.cell(1, ci)
                    p_obs = c_obs.paragraphs[0]
                    p_obs.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    obs = foto.get("obs", "")
                    _run(p_obs, obs, size_pt=9)

            doc.add_paragraph()
            i += 2

        doc.add_paragraph()


# ─────────────────────────────────────────────────────────────────────────────
# Public entry point
# ─────────────────────────────────────────────────────────────────────────────

def generar_word_pozos(
    oc: str,
    ubicacion: str,
    equipos: list[dict],
    epps: list[str],
    herramientas: list[dict],
    materiales: list[dict],
    personal: list[dict],
    evidencias_por_equipo: list[dict],
) -> bytes:
    """
    Genera el Word del Informe General de Pozos a Tierra y devuelve los bytes.

    Args:
        oc: Número de Orden de Compra.
        ubicacion: Texto de ubicación / provincia.
        equipos: Lista de dicts con nombre del equipo intervenido.
        epps: Lista de nombres de EPP.
        herramientas: Lista de dicts {serie, nombre, marca}.
        materiales: Lista de dicts {nombre, unidad, caracteristicas}.
        personal: Lista de dicts {nombre, rol}.
        evidencias_por_equipo: Lista de dicts {nombre, fotos:[{url, obs}]}.
    """
    doc = Document()

    # Page margins to match legacy (usable width ≈ 17.6 cm)
    sec = doc.sections[0]
    sec.left_margin  = Cm(1.7)
    sec.right_margin = Cm(1.7)
    sec.top_margin   = Cm(2.5)
    sec.bottom_margin = Cm(2.5)

    # Global font style
    style = doc.styles["Normal"]
    style.font.name = "Arial"
    style.font.size = Pt(11)

    today = date.today()
    fecha_str = f"{today.day:02d}/{today.month:02d}/{today.year}"

    # ── 1. Header ──────────────────────────────────────────────────────────────
    _build_header(doc, oc, ubicacion)

    # ── 2. Portada ─────────────────────────────────────────────────────────────
    _build_portada(doc, oc, ubicacion, fecha_str)

    # ── 3. Índice ──────────────────────────────────────────────────────────────
    _build_indice(doc)

    # ── 4-12. Secciones de contenido ──────────────────────────────────────────

    # 01. GENERALIDADES
    _para_heading(doc, "01. GENERALIDADES", 14)
    _sec_generalidades(doc, ubicacion)
    doc.add_paragraph()

    # 02. ALCANCE
    _para_heading(doc, "02. ALCANCE", 14)
    _sec_alcance(doc, ubicacion)
    doc.add_paragraph()

    # 03. MARCO NORMATIVO
    _para_heading(doc, "03. MARCO NORMATIVO", 14)
    _sec_marco_normativo(doc)
    doc.add_paragraph()

    # 04. OBJETIVOS
    _para_heading(doc, "04. OBJETIVOS", 14)
    _sec_objetivos(doc)
    doc.add_paragraph()

    # 05. PROCEDIMIENTO SST
    _para_heading(doc, "05. PROCEDIMIENTO SST IMPLÍCITOS", 14)
    _para_heading(doc, "05.1. USO DEL EPP DE ACUERDO AL TIPO DE TRABAJO", 12)
    _sec_epp_intro(doc)
    _table_epp(doc, epps)
    doc.add_paragraph()

    _para_heading(doc, "05.2. PROCEDIMIENTO DE BLOQUEO Y ETIQUETADO LOTO", 12)
    _sec_loto(doc)
    doc.add_paragraph()

    # 06. PERSONAL COMPROMETIDO
    _para_heading(doc, "06. PERSONAL COMPROMETIDO", 14)
    _sec_personal_intro(doc)
    _table_personal(doc, personal)
    doc.add_paragraph()

    # 07. MATERIALES, HERRAMIENTAS Y EQUIPOS
    _para_heading(doc, "07. LISTA DE MATERIALES, HERRAMIENTAS Y EQUIPOS EMPLEADOS", 14)
    _table_materiales(doc, materiales)
    doc.add_paragraph()
    _table_herramientas(doc, herramientas)
    doc.add_paragraph()

    # 08. PROCEDIMIENTOS DE EJECUCIÓN
    _para_heading(doc, "08. PROCEDIMIENTOS DE EJECUCIÓN", 14)
    _para_heading(doc, "08.1. PREPARATIVOS PREVIOS A LA EJECUCIÓN", 12)
    _sec_preparativos(doc)
    doc.add_paragraph()

    _para_heading(doc, "08.2. EJECUCIÓN DE TRABAJO", 12)
    _sec_ejecucion(doc)
    doc.add_paragraph()

    # 09. EVIDENCIA FOTOGRÁFICA
    _para_heading(doc, "09. EVIDENCIA FOTOGRÁFICA", 14)
    _evidence_grid(doc, evidencias_por_equipo)

    # 10. CONCLUSIONES
    _para_heading(doc, "10. CONCLUSIONES", 14)
    _sec_conclusiones(doc)
    doc.add_paragraph()

    # 11. OBSERVACIONES
    _para_heading(doc, "11. OBSERVACIONES", 14)
    _sec_observaciones(doc)
    doc.add_paragraph()

    # 12. RECOMENDACIONES
    _para_heading(doc, "12. RECOMENDACIONES", 14)
    _sec_recomendaciones(doc)

    buf = io.BytesIO()
    doc.save(buf)
    buf.seek(0)
    return buf.read()
