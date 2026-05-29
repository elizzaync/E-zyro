"""
Generación dinámica (desde cero, reportlab platypus) del PRE-INFORME / INFORME FINAL
de un servicio: cabecera + procedimientos + evidencias (con fotos embebidas).
Independiente del overlay de plantillas de `pdf_service.py`.
"""
from __future__ import annotations

import io
import logging
from typing import Optional

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image,
)

_MAX_FOTOS = 12        # tope de fotos embebidas para acotar tamaño/tiempo
_FOTO_W = 55 * mm


def _img_flowable(url: str) -> Optional[Image]:
    """Descarga una imagen de Cloudinary y la devuelve como flowable escalado. None si falla."""
    if not url:
        return None
    try:
        import requests
        resp = requests.get(url, timeout=8)
        if resp.status_code != 200 or not resp.content:
            return None
        bio = io.BytesIO(resp.content)
        img = Image(bio)
        ratio = (img.imageHeight / img.imageWidth) if img.imageWidth else 0.75
        img.drawWidth = _FOTO_W
        img.drawHeight = _FOTO_W * ratio
        return img
    except Exception as e:  # noqa: BLE001 — una foto que falla no debe romper el PDF
        logging.warning(f"[informe] no se pudo embeber {url}: {e}")
        return None


def generar_informe_servicio_pdf(data: dict) -> bytes:
    """`data` = {tipo, empresa, servicio{...}, procedimientos[...], evidencias[...]}."""
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, topMargin=18 * mm, bottomMargin=16 * mm,
                            leftMargin=16 * mm, rightMargin=16 * mm,
                            title="Informe de servicio")
    styles = getSampleStyleSheet()
    h1 = ParagraphStyle("h1", parent=styles["Heading1"], fontSize=16, spaceAfter=4)
    sub = ParagraphStyle("sub", parent=styles["Normal"], fontSize=9, textColor=colors.grey)
    h2 = ParagraphStyle("h2", parent=styles["Heading2"], fontSize=12, spaceBefore=10, spaceAfter=4)
    normal = styles["Normal"]

    es_final = (data.get("tipo") == "final")
    serv = data.get("servicio", {}) or {}
    elems = []

    titulo = "INFORME FINAL DE SERVICIO" if es_final else "PRE-INFORME DE SERVICIO"
    elems.append(Paragraph(titulo, h1))
    elems.append(Paragraph(data.get("empresa", "") or "", sub))
    elems.append(Spacer(1, 6))

    # ── Datos del servicio ──
    info = [
        ["Servicio", serv.get("nombre", "") or ""],
        ["Estado", serv.get("estado", "") or ""],
        ["Alcance", serv.get("alcance", "") or "-"],
        ["Zona", serv.get("zona", "") or "-"],
        ["Responsable", serv.get("responsable", "") or "-"],
        ["Inicio", str(serv.get("fecha_inicio") or "-")],
        ["Fin", str(serv.get("fecha_fin") or "-")],
    ]
    if es_final:
        info.append(["N° Conformidad", serv.get("nro_conformidad", "") or "-"])
    t = Table(info, colWidths=[35 * mm, 120 * mm])
    t.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.lightgrey),
        ("ROWBACKGROUNDS", (1, 0), (1, -1), [colors.white]),
    ]))
    elems.append(t)

    # ── Procedimientos ──
    procs = data.get("procedimientos", []) or []
    elems.append(Paragraph(f"Procedimientos ({len(procs)})", h2))
    if procs:
        filas = [["#", "Procedimiento", "Estado", "Inicio", "Límite"]]
        for p in procs:
            filas.append([
                str(p.get("orden", "") or ""), p.get("nombre", "") or "",
                p.get("estado", "") or "", str(p.get("fecha_inicio") or "-"),
                str(p.get("fecha_limite") or "-"),
            ])
        tp = Table(filas, colWidths=[10 * mm, 80 * mm, 28 * mm, 20 * mm, 20 * mm], repeatRows=1)
        tp.setStyle(TableStyle([
            ("FONTSIZE", (0, 0), (-1, -1), 8),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0d47a1")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("GRID", (0, 0), (-1, -1), 0.4, colors.lightgrey),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]))
        elems.append(tp)
    else:
        elems.append(Paragraph("Sin procedimientos registrados.", normal))

    # ── Evidencias ──
    evs = data.get("evidencias", []) or []
    elems.append(Paragraph(f"Evidencias ({len(evs)})", h2))
    if not evs:
        elems.append(Paragraph("Sin evidencias registradas.", normal))
    else:
        celdas, fila = [], []
        embebidas = 0
        for ev in evs:
            cap = f"{ev.get('procedimiento','') or ''} · {ev.get('etapa','') or ''}<br/>{ev.get('descripcion','') or ''}"
            contenido = [Paragraph(cap, sub)]
            if embebidas < _MAX_FOTOS:
                img = _img_flowable(ev.get("url", ""))
                if img is not None:
                    contenido.insert(0, img)
                    embebidas += 1
            fila.append(contenido)
            if len(fila) == 2:
                celdas.append(fila)
                fila = []
        if fila:
            fila.append("")
            celdas.append(fila)
        te = Table(celdas, colWidths=[80 * mm, 80 * mm])
        te.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ]))
        elems.append(te)

    doc.build(elems)
    return buf.getvalue()
