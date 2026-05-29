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


def _doc(buf, titulo):
    return SimpleDocTemplate(buf, pagesize=A4, topMargin=18 * mm, bottomMargin=16 * mm,
                             leftMargin=16 * mm, rightMargin=16 * mm, title=titulo)


def _styles():
    s = getSampleStyleSheet()
    return {
        "h1": ParagraphStyle("h1", parent=s["Heading1"], fontSize=15, spaceAfter=4),
        "sub": ParagraphStyle("sub", parent=s["Normal"], fontSize=9, textColor=colors.grey),
        "h2": ParagraphStyle("h2", parent=s["Heading2"], fontSize=12, spaceBefore=10, spaceAfter=4),
        "n": s["Normal"],
    }


def _kv_table(rows):
    t = Table(rows, colWidths=[40 * mm, 115 * mm])
    t.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.lightgrey),
    ]))
    return t


def _data_table(filas, anchos):
    t = Table(filas, colWidths=anchos, repeatRows=1)
    t.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("BACKGROUND", (0, 0), (-1, 0), _AZUL),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.lightgrey),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
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
        ["Receptor", data.get("receptor", "") or "-"],
        ["Fecha", str(data.get("fecha") or "-")],
        ["Observación", data.get("observacion", "") or "-"],
    ]))
    e.append(Paragraph("Equipos entregados", st["h2"]))
    filas = [["#", "EPP", "Cantidad"]]
    for i, it in enumerate(data.get("items", []) or [], 1):
        filas.append([str(i), it.get("nombre", "") or "", str(it.get("cantidad", "") or "")])
    e.append(_data_table(filas, [12 * mm, 118 * mm, 25 * mm]))
    # Firma
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
        ["Código", data.get("codigo", "") or "-"],
        ["Servicio", data.get("servicio", "") or "-"],
        ["Estado", data.get("estado", "") or "-"],
        ["Alcance", data.get("alcance", "") or "-"],
        ["Inicio", str(data.get("fecha_inicio") or "-")],
        ["Fin", str(data.get("fecha_fin") or "-")],
    ]))
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
        ["Cliente", data.get("cliente", "") or "-"],
        ["Ubicación", data.get("ubicacion", "") or "-"],
        ["Zona", data.get("zona", "") or "-"],
        ["Modo", data.get("modo", "") or "-"],
        ["Fecha", str(data.get("fecha") or "-")],
        ["Estado", data.get("estado", "") or "-"],
    ]))

    tableros = data.get("tableros", []) or []
    if tableros:
        e.append(Paragraph(f"Tableros ({len(tableros)})", st["h2"]))
        filas = [["Tablero", "Ambiente", "Descripción"]]
        for t in tableros:
            filas.append([t.get("nombre", "") or "", t.get("ambiente", "") or "-", t.get("descripcion", "") or "-"])
        e.append(_data_table(filas, [50 * mm, 45 * mm, 60 * mm]))

    items = data.get("items", []) or []
    e.append(Paragraph(f"Hallazgos ({len(items)})", st["h2"]))
    if items:
        filas = [["Descripción", "Resultado", "Observación"]]
        for it in items:
            filas.append([it.get("descripcion", "") or "", it.get("resultado", "") or "", it.get("observacion", "") or "-"])
        e.append(_data_table(filas, [75 * mm, 30 * mm, 50 * mm]))
    else:
        e.append(Paragraph("Sin hallazgos registrados.", st["n"]))

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
        tf = Table(celdas, colWidths=[80 * mm, 80 * mm])
        tf.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
        e.append(tf)

    if data.get("observaciones"):
        e.append(Paragraph("Conclusiones", st["h2"]))
        e.append(Paragraph(data["observaciones"], st["n"]))
    doc.build(e)
    return buf.getvalue()
