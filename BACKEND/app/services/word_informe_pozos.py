"""
Generación del Informe General de Pozos a Tierra en formato Word (.docx).
Utiliza python-docx para la estructura y Pillow para convertir imágenes WebP → JPEG.
"""
from __future__ import annotations

import io
import logging
import re
from datetime import date
from typing import Any, Optional

import requests
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor, Cm
from PIL import Image as PILImage

logger = logging.getLogger(__name__)

# ── Rutas absolutas de logos ──────────────────────────────────────────────────
_LOGO_HEADER = "/home/harold/E-zyro-frontend/public/assets/img/headerLogo.png"
_LOGO_TALMA  = "/home/harold/E-zyro-frontend/public/assets/img/talma.png"

_MESES_ES = [
    "", "ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO",
    "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE",
]

# ─────────────────────────────────────────────────────────────────────────────
# Helpers XML
# ─────────────────────────────────────────────────────────────────────────────

def _set_font(run, name="Arial", size_pt=11, bold=False, color: Optional[RGBColor] = None):
    run.font.name = name
    run.font.size = Pt(size_pt)
    run.font.bold = bold
    if color:
        run.font.color.rgb = color


def _set_cell_bg(cell, hex_color: str):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def _set_col_width(cell, width_cm: float):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcW = OxmlElement("w:tcW")
    tcW.set(qn("w:w"), str(int(width_cm * 567)))  # 1 cm ≈ 567 twips
    tcW.set(qn("w:type"), "dxa")
    tcPr.append(tcW)


def _set_table_borders(table, color="000000", size=4):
    tbl = table._tbl
    tblPr = tbl.tblPr
    if tblPr is None:
        tblPr = OxmlElement("w:tblPr")
        tbl.insert(0, tblPr)
    tblBorders = OxmlElement("w:tblBorders")
    for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
        bd = OxmlElement(f"w:{side}")
        bd.set(qn("w:val"), "single")
        bd.set(qn("w:sz"), str(size))
        bd.set(qn("w:space"), "0")
        bd.set(qn("w:color"), color)
        tblBorders.append(bd)
    tblPr.append(tblBorders)


def _para_text(para, text: str, bold=False, size_pt=11, align=None, color: Optional[RGBColor] = None):
    run = para.add_run(text)
    _set_font(run, size_pt=size_pt, bold=bold, color=color)
    if align:
        para.alignment = align
    return run


def _add_bookmark(para, bk_id: int, bk_name: str):
    p = para._p
    bm_start = OxmlElement("w:bookmarkStart")
    bm_start.set(qn("w:id"), str(bk_id))
    bm_start.set(qn("w:name"), bk_name)
    p.append(bm_start)
    bm_end = OxmlElement("w:bookmarkEnd")
    bm_end.set(qn("w:id"), str(bk_id))
    p.append(bm_end)


def _add_anchor_hyperlink(para, anchor: str, text: str, size_pt=11):
    """Agrega un hipervínculo interno al párrafo dado (apunta a un bookmark)."""
    hl = OxmlElement("w:hyperlink")
    hl.set(qn("w:anchor"), anchor)
    run_el = OxmlElement("w:r")
    rPr = OxmlElement("w:rPr")
    style_el = OxmlElement("w:rStyle")
    style_el.set(qn("w:val"), "Hyperlink")
    rPr.append(style_el)
    sz_el = OxmlElement("w:sz")
    sz_el.set(qn("w:val"), str(int(size_pt * 2)))
    rPr.append(sz_el)
    szCs_el = OxmlElement("w:szCs")
    szCs_el.set(qn("w:val"), str(int(size_pt * 2)))
    rPr.append(szCs_el)
    run_el.append(rPr)
    t_el = OxmlElement("w:t")
    t_el.text = text
    t_el.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    run_el.append(t_el)
    hl.append(run_el)
    para._p.append(hl)


# ─────────────────────────────────────────────────────────────────────────────
# Imágenes
# ─────────────────────────────────────────────────────────────────────────────

def _url_to_jpeg_buffer(url: str, timeout: int = 15) -> Optional[io.BytesIO]:
    """Descarga una imagen desde URL y la convierte a JPEG (maneja WebP)."""
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
        logger.warning("[word_pozos] imagen no descargada %s: %s", url, exc)
        return None


# ─────────────────────────────────────────────────────────────────────────────
# Documento principal
# ─────────────────────────────────────────────────────────────────────────────

def _configurar_estilos_globales(doc: Document):
    """Fuente global Arial 11 en el estilo Normal."""
    style = doc.styles["Normal"]
    font = style.font
    font.name = "Arial"
    font.size = Pt(11)


def _construir_header(doc: Document, oc: str, ubicacion: str, fecha_str: str):
    """Encabezado con logos, OC, título y campos de firmas."""
    section = doc.sections[0]
    section.header_distance = Cm(0.5)
    header = section.header

    # Limpiar párrafo por defecto
    for p in header.paragraphs:
        p.clear()

    table = header.add_table(rows=3, cols=3, width=Inches(9))
    table.style = "Table Grid"
    _set_table_borders(table, color="003366", size=4)

    # Fila 0: logos + datos del informe
    row0 = table.rows[0]
    row0.height = Cm(1.8)

    # Celda 0,0: Logo E-zyro/empresa
    c00 = row0.cells[0]
    c00.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _set_col_width(c00, 3.2)
    p00 = c00.paragraphs[0]
    p00.alignment = WD_ALIGN_PARAGRAPH.CENTER
    try:
        run_logo = p00.add_run()
        run_logo.add_picture(_LOGO_HEADER, width=Cm(2.8))
    except Exception:
        p00.add_run("E-ZYRO")

    # Celda 0,1: Título
    c01 = row0.cells[1]
    c01.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _set_cell_bg(c01, "003366")
    p01 = c01.paragraphs[0]
    p01.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r01 = p01.add_run("INFORME DE MANTENIMIENTO PREVENTIVO\nPOZO A TIERRA")
    _set_font(r01, size_pt=10, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    # Celda 0,2: Logo Talma
    c02 = row0.cells[2]
    c02.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    _set_col_width(c02, 3.2)
    p02 = c02.paragraphs[0]
    p02.alignment = WD_ALIGN_PARAGRAPH.CENTER
    try:
        run_talma = p02.add_run()
        run_talma.add_picture(_LOGO_TALMA, width=Cm(2.8))
    except Exception:
        p02.add_run("TALMA")

    # Fila 1: OC, ubicación, fecha
    row1 = table.rows[1]
    data_row = [
        ("N° OC:", oc or "—"),
        ("UBICACIÓN:", ubicacion or "—"),
        ("FECHA:", fecha_str),
    ]
    for idx, (lbl, val) in enumerate(data_row):
        cell = row1.cells[idx]
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = cell.paragraphs[0]
        r_lbl = p.add_run(lbl + " ")
        _set_font(r_lbl, size_pt=8, bold=True)
        r_val = p.add_run(val)
        _set_font(r_val, size_pt=8)

    # Fila 2: campos de firma
    row2 = table.rows[2]
    firmas = ["ELABORADO POR: _______________", "REVISADO POR: _______________", "APROBADO POR: _______________"]
    for idx, firma in enumerate(firmas):
        cell = row2.cells[idx]
        p = cell.paragraphs[0]
        r = p.add_run(firma)
        _set_font(r, size_pt=7)
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER


def _portada(doc: Document, ubicacion: str, fecha_str: str):
    """Primera página: título grande, fecha dinámica y tabla de ejecución."""
    doc.add_paragraph()
    doc.add_paragraph()

    p_titulo = doc.add_paragraph()
    p_titulo.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p_titulo.add_run("INFORME DE MANTENIMIENTO PREVENTIVO\nPOZO A TIERRA")
    _set_font(r, size_pt=24, bold=True, color=RGBColor(0x00, 0x33, 0x66))

    doc.add_paragraph()

    p_ubic = doc.add_paragraph()
    p_ubic.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r2 = p_ubic.add_run(ubicacion.upper() if ubicacion else "")
    _set_font(r2, size_pt=14, bold=True)

    doc.add_paragraph()

    p_fecha = doc.add_paragraph()
    p_fecha.alignment = WD_ALIGN_PARAGRAPH.CENTER
    today = date.today()
    r3 = p_fecha.add_run(f"{_MESES_ES[today.month]} – {today.year}")
    _set_font(r3, size_pt=16, bold=True)

    doc.add_paragraph()
    doc.add_paragraph()

    # Tabla "Fecha de Ejecución"
    tbl = doc.add_table(rows=2, cols=2)
    _set_table_borders(tbl)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

    hdr = tbl.rows[0]
    hdr.cells[0].text = "FECHA DE EJECUCIÓN"
    hdr.cells[1].text = "RESPONSABLE"
    for cell in hdr.cells:
        _set_cell_bg(cell, "003366")
        for par in cell.paragraphs:
            for run in par.runs:
                _set_font(run, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    row = tbl.rows[1]
    row.cells[0].text = fecha_str
    row.cells[1].text = ""

    doc.add_page_break()


def _indice(doc: Document, secciones: list[tuple[str, str]]):
    """
    TOC manual con hipervínculos internos a bookmarks.
    secciones: [(titulo, anchor_name), ...]
    """
    p_toc = doc.add_paragraph()
    r = p_toc.add_run("ÍNDICE")
    _set_font(r, size_pt=14, bold=True)
    _add_bookmark(p_toc, 0, "toc_inicio")

    doc.add_paragraph()

    for titulo, anchor in secciones:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.5)
        _add_anchor_hyperlink(p, anchor, titulo, size_pt=11)

    doc.add_page_break()


def _seccion_heading(doc: Document, titulo: str, bk_id: int, bk_name: str) -> None:
    """Agrega un encabezado de sección con bookmark."""
    p = doc.add_paragraph()
    r = p.add_run(titulo)
    _set_font(r, size_pt=12, bold=True, color=RGBColor(0x00, 0x33, 0x66))
    _add_bookmark(p, bk_id, bk_name)
    doc.add_paragraph()


# ─────────────────────────────────────────────────────────────────────────────
# Secciones de contenido
# ─────────────────────────────────────────────────────────────────────────────

def _seccion_antecedentes(doc: Document):
    texto = (
        "El presente informe describe las actividades de mantenimiento preventivo realizadas "
        "en los pozos a tierra de las instalaciones del cliente, conforme al programa de "
        "mantenimiento vigente y en cumplimiento de las normas técnicas peruanas aplicables "
        "(NTP 370.050 – Sistemas de Puesta a Tierra). El mantenimiento preventivo de los "
        "pozos a tierra garantiza la continuidad del sistema de protección eléctrica y la "
        "seguridad del personal y los equipos."
    )
    p = doc.add_paragraph()
    r = p.add_run(texto)
    _set_font(r, size_pt=11)
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY


def _seccion_objetivo(doc: Document):
    texto = (
        "Realizar el mantenimiento preventivo de los sistemas de puesta a tierra, verificando "
        "la resistencia de cada pozo a tierra según los estándares establecidos, aplicando "
        "tratamiento de activación con gel conductor (THOR GEL) y asegurando que los valores "
        "de resistencia se encuentren por debajo de los límites permitidos por la normativa "
        "vigente (≤ 5 Ω para sistemas de protección de personas)."
    )
    p = doc.add_paragraph()
    r = p.add_run(texto)
    _set_font(r, size_pt=11)
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY


def _seccion_alcance(doc: Document, equipos: list[dict]):
    texto = (
        "El alcance del servicio comprende el mantenimiento preventivo de los siguientes "
        "pozos a tierra:"
    )
    p = doc.add_paragraph()
    r = p.add_run(texto)
    _set_font(r, size_pt=11)
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

    for eq in equipos:
        p_item = doc.add_paragraph(style="List Bullet")
        r_item = p_item.add_run(eq.get("nombre", ""))
        _set_font(r_item, size_pt=11)


def _seccion_docs_referencia(doc: Document):
    docs = [
        ("NTP 370.050", "Instalaciones Eléctricas en Edificios – Puesta a Tierra"),
        ("CNE – Utilización", "Código Nacional de Electricidad – Reglas de Utilización"),
        ("NTP-IEC 60364-5-54", "Instalaciones eléctricas en edificios – Selección e instalación de los materiales eléctricos – Puesta a tierra y conductores de protección"),
        ("Ley 29783", "Ley de Seguridad y Salud en el Trabajo"),
        ("DS 005-2012-TR", "Reglamento de la Ley de Seguridad y Salud en el Trabajo"),
    ]
    tbl = doc.add_table(rows=1, cols=2)
    _set_table_borders(tbl)
    hdr = tbl.rows[0].cells
    hdr[0].text = "CÓDIGO / NORMA"
    hdr[1].text = "DESCRIPCIÓN"
    for cell in hdr:
        _set_cell_bg(cell, "003366")
        for par in cell.paragraphs:
            for run in par.runs:
                _set_font(run, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    for codigo, descripcion in docs:
        row = tbl.add_row()
        row.cells[0].text = codigo
        row.cells[1].text = descripcion
        for cell in row.cells:
            for par in cell.paragraphs:
                for run in par.runs:
                    _set_font(run, size_pt=10)


def _seccion_epp(doc: Document, epps: list[str]):
    """Tabla de EPPs con regla condicional ES_NECESARIO."""

    def _es_necesario(nombre: str) -> str:
        n = nombre.upper()
        if "CARETA" in n or "ARNES" in n or "ARNÉS" in n:
            return "NO"
        if "PROTECTORES DE OIDO" in n or "PROTECTOR DE OIDO" in n or "GUANTE" in n:
            return "SI"
        return "SI – Plataforma SST"

    tbl = doc.add_table(rows=1, cols=3)
    _set_table_borders(tbl)
    hdr = tbl.rows[0].cells
    for idx, col in enumerate(["N°", "EQUIPOS DE PROTECCIÓN PERSONAL", "ES NECESARIO"]):
        hdr[idx].text = col
        _set_cell_bg(hdr[idx], "003366")
        for par in hdr[idx].paragraphs:
            for run in par.runs:
                _set_font(run, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    for i, epp in enumerate(epps, start=1):
        row = tbl.add_row()
        row.cells[0].text = str(i)
        row.cells[1].text = epp
        row.cells[2].text = _es_necesario(epp)
        for cell in row.cells:
            for par in cell.paragraphs:
                for run in par.runs:
                    _set_font(run, size_pt=10)


def _seccion_personal(doc: Document, personal: list[dict]):
    """Tabla de personal con cargo y responsabilidad por rol."""

    def _cargo_resp(rol: str) -> tuple[str, str]:
        if "supervis" in rol.lower() or "jefe" in rol.lower() or "lider" in rol.lower() or "líder" in rol.lower():
            return "Coordinador / Supervisor", "Supervisión de trabajos"
        return "Técnico ejecutor", "Ejecución de trabajos"

    tbl = doc.add_table(rows=1, cols=4)
    _set_table_borders(tbl)
    hdr = tbl.rows[0].cells
    for idx, col in enumerate(["N°", "NOMBRES Y APELLIDOS", "CARGO", "RESPONSABILIDAD"]):
        hdr[idx].text = col
        _set_cell_bg(hdr[idx], "003366")
        for par in hdr[idx].paragraphs:
            for run in par.runs:
                _set_font(run, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    for i, pers in enumerate(personal, start=1):
        cargo, resp = _cargo_resp(pers.get("rol", "Técnico"))
        row = tbl.add_row()
        row.cells[0].text = str(i)
        row.cells[1].text = pers.get("nombre", "")
        row.cells[2].text = cargo
        row.cells[3].text = resp
        for cell in row.cells:
            for par in cell.paragraphs:
                for run in par.runs:
                    _set_font(run, size_pt=10)


def _seccion_herramientas(doc: Document, herramientas: list[dict]):
    tbl = doc.add_table(rows=1, cols=4)
    _set_table_borders(tbl)
    hdr = tbl.rows[0].cells
    for idx, col in enumerate(["N°", "SERIE", "HERRAMIENTA / INSTRUMENTO", "MARCA"]):
        hdr[idx].text = col
        _set_cell_bg(hdr[idx], "003366")
        for par in hdr[idx].paragraphs:
            for run in par.runs:
                _set_font(run, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    for i, h in enumerate(herramientas, start=1):
        row = tbl.add_row()
        row.cells[0].text = str(i)
        row.cells[1].text = h.get("serie", "-")
        row.cells[2].text = h.get("nombre", "")
        row.cells[3].text = h.get("marca", "-")
        for cell in row.cells:
            for par in cell.paragraphs:
                for run in par.runs:
                    _set_font(run, size_pt=10)


def _seccion_materiales(doc: Document, materiales: list[dict]):
    tbl = doc.add_table(rows=1, cols=4)
    _set_table_borders(tbl)
    hdr = tbl.rows[0].cells
    for idx, col in enumerate(["N°", "MATERIAL / INSUMO", "UNIDAD", "CARACTERÍSTICAS"]):
        hdr[idx].text = col
        _set_cell_bg(hdr[idx], "003366")
        for par in hdr[idx].paragraphs:
            for run in par.runs:
                _set_font(run, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF))

    for i, m in enumerate(materiales, start=1):
        row = tbl.add_row()
        row.cells[0].text = str(i)
        row.cells[1].text = m.get("nombre", "")
        row.cells[2].text = m.get("unidad", "Ud.")
        row.cells[3].text = m.get("caracteristicas", "-")
        for cell in row.cells:
            for par in cell.paragraphs:
                for run in par.runs:
                    _set_font(run, size_pt=10)


_OBS_CLEAN_RE = re.compile(r"OBS\s*:", re.IGNORECASE)


def _limpiar_obs(texto: str) -> str:
    return _OBS_CLEAN_RE.sub("", texto or "").strip()


def _seccion_evidencia(doc: Document, evidencias_por_equipo: list[dict]):
    """
    evidencias_por_equipo: [
        {
          "nombre": str,
          "fotos": [{"url": str, "obs": str}, ...]
        }
    ]
    Cuadrícula 2x2: fila imágenes + fila observaciones. Si es impar → celda fusionada.
    """
    W_IMG_INCHES = 3.0  # ancho de imagen en pulgadas por celda

    for grupo in evidencias_por_equipo:
        nombre_eq = grupo.get("nombre", "Equipo")
        fotos = grupo.get("fotos", [])

        p_titulo = doc.add_paragraph()
        r_t = p_titulo.add_run(f"EJECUCIÓN DE MANTENIMIENTO PREVENTIVO – {nombre_eq.upper()}")
        _set_font(r_t, size_pt=11, bold=True, color=RGBColor(0x00, 0x33, 0x66))

        if not fotos:
            p_vacio = doc.add_paragraph()
            r_v = p_vacio.add_run("(Sin evidencias fotográficas registradas)")
            _set_font(r_v, size_pt=10)
            doc.add_paragraph()
            continue

        # Iterar en pares
        i = 0
        while i < len(fotos):
            foto_izq = fotos[i]
            foto_der = fotos[i + 1] if i + 1 < len(fotos) else None
            impar = foto_der is None

            if impar:
                # Una sola foto: tabla 1 col
                tbl = doc.add_table(rows=2, cols=1)
                _set_table_borders(tbl, color="CCCCCC")

                cell_img = tbl.rows[0].cells[0]
                cell_img.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                p_img = cell_img.paragraphs[0]
                p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
                buf = _url_to_jpeg_buffer(foto_izq["url"])
                if buf:
                    run_img = p_img.add_run()
                    run_img.add_picture(buf, width=Inches(W_IMG_INCHES * 2))
                else:
                    p_img.add_run("[imagen no disponible]")

                cell_obs = tbl.rows[1].cells[0]
                p_obs = cell_obs.paragraphs[0]
                p_obs.alignment = WD_ALIGN_PARAGRAPH.CENTER
                r_obs = p_obs.add_run(_limpiar_obs(foto_izq.get("obs", "")))
                _set_font(r_obs, size_pt=9)
            else:
                # Dos fotos: tabla 2 cols
                tbl = doc.add_table(rows=2, cols=2)
                _set_table_borders(tbl, color="CCCCCC")

                for col_idx, foto in enumerate([foto_izq, foto_der]):
                    cell_img = tbl.rows[0].cells[col_idx]
                    cell_img.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                    p_img = cell_img.paragraphs[0]
                    p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    buf = _url_to_jpeg_buffer(foto["url"])
                    if buf:
                        run_img = p_img.add_run()
                        run_img.add_picture(buf, width=Inches(W_IMG_INCHES))
                    else:
                        p_img.add_run("[imagen no disponible]")

                    cell_obs = tbl.rows[1].cells[col_idx]
                    p_obs = cell_obs.paragraphs[0]
                    p_obs.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    r_obs = p_obs.add_run(_limpiar_obs(foto.get("obs", "")))
                    _set_font(r_obs, size_pt=9)

            doc.add_paragraph()
            i += 2

        doc.add_paragraph()


# ─────────────────────────────────────────────────────────────────────────────
# Entrada pública
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
        ubicacion: Texto de ubicación concatenado (provincias únicas).
        equipos: Lista de dicts con nombre del equipo intervenido.
        epps: Lista de nombres de EPP.
        herramientas: Lista de dicts {serie, nombre, marca}.
        materiales: Lista de dicts {nombre, unidad, caracteristicas}.
        personal: Lista de dicts {nombre, rol}.
        evidencias_por_equipo: Lista de dicts {nombre, fotos:[{url, obs}]}.
    """
    doc = Document()
    _configurar_estilos_globales(doc)

    today = date.today()
    fecha_str = f"{today.day:02d}/{today.month:02d}/{today.year}"

    # Encabezado de página
    _construir_header(doc, oc, ubicacion, f"{_MESES_ES[today.month]} {today.year}")

    # Portada
    _portada(doc, ubicacion, fecha_str)

    # Índice con secciones
    secciones: list[tuple[str, str]] = [
        ("01. ANTECEDENTES",              "sec_antecedentes"),
        ("02. OBJETIVO",                   "sec_objetivo"),
        ("03. ALCANCE",                    "sec_alcance"),
        ("04. DOCUMENTOS DE REFERENCIA",   "sec_docs"),
        ("05. EQUIPOS DE PROTECCIÓN PERSONAL", "sec_epp"),
        ("06. PERSONAL",                   "sec_personal"),
        ("07. HERRAMIENTAS E INSTRUMENTOS","sec_herramientas"),
        ("08. MATERIALES E INSUMOS",       "sec_materiales"),
        ("09. EVIDENCIA FOTOGRÁFICA",      "sec_evidencia"),
    ]
    _indice(doc, secciones)

    # ── Secciones de contenido ────────────────────────────────────────────────
    bk_id = 1

    _seccion_heading(doc, "01. ANTECEDENTES", bk_id, "sec_antecedentes"); bk_id += 1
    _seccion_antecedentes(doc)
    doc.add_paragraph()

    _seccion_heading(doc, "02. OBJETIVO", bk_id, "sec_objetivo"); bk_id += 1
    _seccion_objetivo(doc)
    doc.add_paragraph()

    _seccion_heading(doc, "03. ALCANCE", bk_id, "sec_alcance"); bk_id += 1
    _seccion_alcance(doc, equipos)
    doc.add_paragraph()

    _seccion_heading(doc, "04. DOCUMENTOS DE REFERENCIA", bk_id, "sec_docs"); bk_id += 1
    _seccion_docs_referencia(doc)
    doc.add_paragraph()

    _seccion_heading(doc, "05. EQUIPOS DE PROTECCIÓN PERSONAL (EPPs)", bk_id, "sec_epp"); bk_id += 1
    _seccion_epp(doc, epps)
    doc.add_paragraph()

    _seccion_heading(doc, "06. PERSONAL", bk_id, "sec_personal"); bk_id += 1
    _seccion_personal(doc, personal)
    doc.add_paragraph()

    _seccion_heading(doc, "07. HERRAMIENTAS E INSTRUMENTOS", bk_id, "sec_herramientas"); bk_id += 1
    _seccion_herramientas(doc, herramientas)
    doc.add_paragraph()

    _seccion_heading(doc, "08. MATERIALES E INSUMOS", bk_id, "sec_materiales"); bk_id += 1
    _seccion_materiales(doc, materiales)
    doc.add_paragraph()

    _seccion_heading(doc, "09. EVIDENCIA FOTOGRÁFICA", bk_id, "sec_evidencia"); bk_id += 1
    _seccion_evidencia(doc, evidencias_por_equipo)

    buf = io.BytesIO()
    doc.save(buf)
    buf.seek(0)
    return buf.read()
