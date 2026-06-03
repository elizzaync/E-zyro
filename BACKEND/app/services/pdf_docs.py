"""
Generadores PDF (reportlab platypus) para: constancia de entrega EPP,
informe de correctivo e informe de inspección ITSE. Comparten estilo/helpers
con `pdf_informe_servicio` (reutiliza su descarga de imágenes).
"""
from __future__ import annotations

import io
from typing import Optional

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image

from .pdf_informe_servicio import _img_flowable

_AZUL = colors.HexColor("#0d47a1")

# Ancho útil: A4 210mm – 16mm×2 márgenes = 178mm
_PAGE_W = 178 * mm


def _doc(buf, titulo):
    return SimpleDocTemplate(buf, pagesize=A4, topMargin=18 * mm, bottomMargin=16 * mm,
                             leftMargin=16 * mm, rightMargin=16 * mm, title=titulo)


def _styles():
    s = getSampleStyleSheet()
    return {
        "h1":  ParagraphStyle("h1",  parent=s["Heading1"], fontSize=15, spaceAfter=4),
        "sub": ParagraphStyle("sub", parent=s["Normal"],   fontSize=9,  textColor=colors.grey),
        "h2":  ParagraphStyle("h2",  parent=s["Heading2"], fontSize=12, spaceBefore=10, spaceAfter=4),
        "n":   s["Normal"],
        # estilos para celdas de tabla
        "cell": ParagraphStyle("cell", parent=s["Normal"], fontSize=8, leading=11,
                                leftIndent=0, rightIndent=0),
        "cell_hdr": ParagraphStyle("cell_hdr", parent=s["Normal"], fontSize=8, leading=11,
                                    fontName="Helvetica-Bold", textColor=colors.white),
    }


def _kv_table(rows, st):
    """Tabla clave-valor con texto que hace wrap."""
    col_k, col_v = 42 * mm, _PAGE_W - 42 * mm
    wrapped = []
    for k, v in rows:
        wrapped.append([
            Paragraph(str(k), st["cell"]),
            Paragraph(str(v) if v else "-", st["cell"]),
        ])
    t = Table(wrapped, colWidths=[col_k, col_v])
    t.setStyle(TableStyle([
        ("BACKGROUND",  (0, 0), (0, -1), colors.whitesmoke),
        ("FONTNAME",    (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTSIZE",    (0, 0), (-1, -1), 9),
        ("VALIGN",      (0, 0), (-1, -1), "TOP"),
        ("GRID",        (0, 0), (-1, -1), 0.4, colors.lightgrey),
        ("TOPPADDING",  (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    return t


def _data_table(filas, anchos, st):
    """
    Tabla de datos con wrap de texto en cada celda.
    filas[0] = encabezado, resto = datos (todos strings).
    Las celdas se convierten a Paragraph para que el texto haga wrap
    y las filas crezcan verticalmente en vez de desbordar.
    """
    wrapped = []
    for i, row in enumerate(filas):
        style = st["cell_hdr"] if i == 0 else st["cell"]
        wrapped.append([Paragraph(str(c) if c else "", style) for c in row])

    t = Table(wrapped, colWidths=anchos, repeatRows=1, splitByRow=True)
    t.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, 0), _AZUL),
        ("GRID",          (0, 0), (-1, -1), 0.4, colors.lightgrey),
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING",    (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING",   (0, 0), (-1, -1), 4),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 4),
    ]))
    return t


# ── Constancia de entrega de EPP ─────────────────────────────────────────────
def generar_constancia_epp(data: dict) -> bytes:
    buf = io.BytesIO()
    doc = _doc(buf, "Constancia de entrega de EPP")
    st = _styles()
    e = [Paragraph("CONSTANCIA DE ENTREGA DE EPP", st["h1"]),
         Paragraph(data.get("empresa", "") or "", st["sub"]), Spacer(1, 6)]
    e.append(_kv_table([
        ("Receptor",    data.get("receptor", "") or "-"),
        ("Fecha",       str(data.get("fecha") or "-")),
        ("Observación", data.get("observacion", "") or "-"),
    ], st))
    e.append(Paragraph("Equipos entregados", st["h2"]))
    filas = [["#", "EPP", "Cantidad"]]
    for i, it in enumerate(data.get("items", []) or [], 1):
        filas.append([str(i), it.get("nombre", "") or "", str(it.get("cantidad", "") or "")])
    e.append(_data_table(filas, [12 * mm, _PAGE_W - 40 * mm, 28 * mm], st))
    e.append(Spacer(1, 18))
    img = _img_flowable(data.get("firma_url", "")) if data.get("firma_url") else None
    if img is not None:
        e.append(img)
    e.append(Paragraph("_______________________________<br/>Firma del receptor", st["sub"]))
    doc.build(e)
    return buf.getvalue()


# ── Informe de correctivo ────────────────────────────────────────────────────
def generar_informe_correctivo(data: dict) -> bytes:
    buf = io.BytesIO()
    doc = _doc(buf, "Informe de correctivo")
    st = _styles()
    e = [Paragraph("INFORME DE CORRECTIVO / GARANTÍA", st["h1"]),
         Paragraph(data.get("empresa", "") or "", st["sub"]), Spacer(1, 6)]
    e.append(_kv_table([
        ("Código",  data.get("codigo",  "") or "-"),
        ("Servicio",data.get("servicio","") or "-"),
        ("Estado",  data.get("estado",  "") or "-"),
        ("Alcance", data.get("alcance", "") or "-"),
        ("Inicio",  str(data.get("fecha_inicio") or "-")),
        ("Fin",     str(data.get("fecha_fin")    or "-")),
    ], st))
    obs = data.get("observaciones")
    if obs:
        e.append(Paragraph("Observaciones / recomendaciones", st["h2"]))
        e.append(Paragraph(obs, st["n"]))
    doc.build(e)
    return buf.getvalue()


# ── Informe de inspección ITSE ───────────────────────────────────────────────
def generar_informe_itse(data: dict) -> bytes:
    buf = io.BytesIO()
    doc = _doc(buf, "Informe de inspección ITSE")
    st = _styles()
    e = [Paragraph("INFORME DE INSPECCIÓN ITSE", st["h1"]),
         Paragraph(data.get("empresa", "") or "", st["sub"]), Spacer(1, 6)]
    e.append(_kv_table([
        ("Cliente",   data.get("cliente",   "") or "-"),
        ("Ubicación", data.get("ubicacion", "") or "-"),
        ("Zona",      data.get("zona",      "") or "-"),
        ("Modo",      data.get("modo",      "") or "-"),
        ("Fecha",     str(data.get("fecha") or "-")),
        ("Estado",    data.get("estado",    "") or "-"),
    ], st))

    # ── Tableros ─────────────────────────────────────────────────────────────
    tableros = data.get("tableros", []) or []
    if tableros:
        e.append(Paragraph(f"Tableros ({len(tableros)})", st["h2"]))
        # Tablero: 90mm | Ambiente: 38mm | Descripción: 50mm  → total 178mm
        filas = [["Tablero", "Ambiente", "Descripción"]]
        for tb in tableros:
            filas.append([
                tb.get("nombre",      "") or "",
                tb.get("ambiente",    "") or "-",
                tb.get("descripcion", "") or "-",
            ])
        e.append(_data_table(filas, [90 * mm, 38 * mm, _PAGE_W - 128 * mm], st))

    # ── Hallazgos ─────────────────────────────────────────────────────────────
    items = data.get("items", []) or []
    e.append(Paragraph(f"Hallazgos ({len(items)})", st["h2"]))
    if items:
        # Descripción: 112mm | Resultado: 30mm | Observación: 36mm → total 178mm
        filas = [["Descripción", "Resultado", "Observación"]]
        for it in items:
            filas.append([
                it.get("descripcion", "") or "",
                it.get("resultado",   "") or "",
                it.get("observacion", "") or "-",
            ])
        e.append(_data_table(filas, [112 * mm, 30 * mm, _PAGE_W - 142 * mm], st))
    else:
        e.append(Paragraph("Sin hallazgos registrados.", st["n"]))

    # ── Fotos ─────────────────────────────────────────────────────────────────
    fotos = [u for u in (data.get("fotos", []) or []) if u][:12]
    if fotos:
        e.append(Paragraph(f"Evidencias fotográficas ({len(fotos)})", st["h2"]))
        fila, celdas = [], []
        for u in fotos:
            img = _img_flowable(u)
            fila.append(img if img is not None else "")
            if len(fila) == 2:
                celdas.append(fila)
                fila = []
        if fila:
            fila.append("")
            celdas.append(fila)
        tf = Table(celdas, colWidths=[_PAGE_W / 2, _PAGE_W / 2])
        tf.setStyle(TableStyle([
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ]))
        e.append(tf)

    # ── Conclusiones ─────────────────────────────────────────────────────────
    if data.get("observaciones"):
        e.append(Paragraph("Conclusiones", st["h2"]))
        e.append(Paragraph(data["observaciones"], st["n"]))

    doc.build(e)
    return buf.getvalue()
