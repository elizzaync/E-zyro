"""
Router: /vacaciones — Punto 3.3 (RR.HH.), control de vacaciones por ley (Perú).
Régimen parametrizable por empresa (General 30 d/año, REMYPE 15 d/año) con tope
de acumulación. Saldo derivado: devengo mensual desde fecha_ingreso menos los
días aprobados. Sin cálculo de pago vacacional.
Lecturas: empresa del token. Escrituras: RBAC dominio 'vacaciones'.
"""
from __future__ import annotations

import io
import uuid as _uuid
from datetime import date, datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.vacaciones import AjusteSaldoVacaciones, ConfigVacaciones, SolicitudVacaciones
from ..services.fcm_service import notificar_usuario
from ..schemas.vacaciones import (
    AjusteSaldoIn, AjusteSaldoOut, ConfigIn, ConfigOut, SaldoOut, SolicitudIn, SolicitudOut,
)

router = APIRouter(prefix="/vacaciones", tags=["vacaciones"])

# Días/año por régimen (Perú). 'otro' usa el valor explícito enviado.
REGIMEN_DIAS = {"general": 30, "remype": 15}
TOPE_DEFECTO = 30


def _parse_date(s: str) -> date:
    return date.fromisoformat(s[:10])


def _meses_servicio(ingreso: Optional[date], hoy: date) -> int:
    if not ingreso:
        return 0
    meses = (hoy.year - ingreso.year) * 12 + (hoy.month - ingreso.month)
    if hoy.day < ingreso.day:
        meses -= 1
    return max(0, meses)


def _get_config(db: Session, empresa_id: str) -> ConfigVacaciones:
    cfg = db.query(ConfigVacaciones).filter(ConfigVacaciones.empresa_id == empresa_id).first()
    if not cfg:
        cfg = ConfigVacaciones(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            regimen="general", dias_por_anio=REGIMEN_DIAS["general"], tope_acumulacion=TOPE_DEFECTO,
        )
        db.add(cfg)
        db.commit()
    return cfg


def _nombre(db: Session, empleado: Empleado) -> Optional[str]:
    row = db.query(Usuario.nombre, Usuario.apellido).filter(Usuario.id == empleado.usuario_id).first()
    return f"{row[0]} {row[1]}".strip() if row else None


def _gozado(db: Session, empresa_id: str, empleado_id: str) -> int:
    total = (
        db.query(func.coalesce(func.sum(SolicitudVacaciones.dias), 0))
        .filter(SolicitudVacaciones.empresa_id == empresa_id,
                SolicitudVacaciones.empleado_id == empleado_id,
                SolicitudVacaciones.estado == "aprobada")
        .scalar()
    )
    return int(total or 0)


def _ajuste(db: Session, empleado_id: str) -> int:
    row = db.query(AjusteSaldoVacaciones).filter(
        AjusteSaldoVacaciones.empleado_id == empleado_id).first()
    return row.ajuste_dias if row else 0


def _estado_vac(meses: int, disponible: float) -> str:
    if meses < 12:
        return "sin_derecho"
    if disponible <= 0:
        return "agotado"
    return "disponible"


def _saldo(db: Session, empresa_id: str, emp: Empleado, cfg: ConfigVacaciones) -> SaldoOut:
    hoy = date.today()
    meses = _meses_servicio(emp.fecha_ingreso, hoy)
    # Derecho a vacaciones al completar cada año de servicio (art. 10 D.Leg. 713).
    anos = meses // 12
    devengado = float(anos * cfg.dias_por_anio)
    ajuste_dias = _ajuste(db, str(emp.id))
    gozado = _gozado(db, empresa_id, str(emp.id))
    acumulado = devengado + ajuste_dias - gozado
    disponible = round(min(acumulado, float(cfg.tope_acumulacion)), 2) if acumulado > 0 else 0.0
    return SaldoOut(
        empleado_id=str(emp.id), empleado_nombre=_nombre(db, emp),
        cargo=emp.cargo,
        fecha_ingreso=(str(emp.fecha_ingreso) if emp.fecha_ingreso else None),
        meses_servicio=meses, anos_servicio=anos, dias_por_anio=cfg.dias_por_anio,
        devengado=devengado, ajuste_dias=ajuste_dias, gozado=gozado,
        disponible=disponible, tope_acumulacion=cfg.tope_acumulacion,
        estado_vacaciones=_estado_vac(meses, disponible),
    )


def _empleado_actual(db: Session, payload: dict) -> Optional[Empleado]:
    return (
        db.query(Empleado)
        .filter(Empleado.usuario_id == payload.get("id"),
                Empleado.empresa_id == payload["empresa_id"])
        .first()
    )


# ── Configuración ────────────────────────────────────────────────────────────
@router.get("/config", response_model=ConfigOut)
def obtener_config(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    cfg = _get_config(db, payload["empresa_id"])
    return ConfigOut(regimen=cfg.regimen, dias_por_anio=cfg.dias_por_anio,
                     tope_acumulacion=cfg.tope_acumulacion)


@router.put("/config", response_model=ConfigOut)
def actualizar_config(body: ConfigIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "vacaciones", "configurar")
    cfg = _get_config(db, payload["empresa_id"])
    cfg.regimen = body.regimen
    # Días/año: explícito o derivado del régimen (general/remype). 'otro' exige valor.
    if body.dias_por_anio is not None:
        cfg.dias_por_anio = body.dias_por_anio
    elif body.regimen in REGIMEN_DIAS:
        cfg.dias_por_anio = REGIMEN_DIAS[body.regimen]
    elif body.regimen == "otro":
        raise HTTPException(status_code=422, detail="Régimen 'otro' requiere dias_por_anio")
    cfg.tope_acumulacion = body.tope_acumulacion if body.tope_acumulacion is not None else cfg.tope_acumulacion
    cfg.updated_at = datetime.utcnow()
    db.commit()
    return ConfigOut(regimen=cfg.regimen, dias_por_anio=cfg.dias_por_anio,
                     tope_acumulacion=cfg.tope_acumulacion)


# ── Saldos ───────────────────────────────────────────────────────────────────
@router.get("/saldos", response_model=List[SaldoOut])
def listar_saldos(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    cfg = _get_config(db, empresa_id)
    emps = (
        db.query(Empleado)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)  # noqa: E712
        .all()
    )
    saldos = [_saldo(db, empresa_id, e, cfg) for e in emps]
    saldos.sort(key=lambda s: (s.empleado_nombre or ""))
    return saldos


@router.get("/saldo/{empleado_id}", response_model=SaldoOut)
def saldo_empleado(empleado_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    return _saldo(db, empresa_id, emp, _get_config(db, empresa_id))


# ── Solicitudes ──────────────────────────────────────────────────────────────
def _sol_out(db: Session, s: SolicitudVacaciones) -> SolicitudOut:
    nombre = (
        db.query(Usuario.nombre, Usuario.apellido)
        .join(Empleado, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.id == s.empleado_id).first()
    )
    return SolicitudOut(
        id=str(s.id), empleado_id=str(s.empleado_id),
        empleado_nombre=(f"{nombre[0]} {nombre[1]}".strip() if nombre else None),
        fecha_inicio=(str(s.fecha_inicio) if s.fecha_inicio else None),
        fecha_fin=(str(s.fecha_fin) if s.fecha_fin else None),
        dias=int(s.dias), estado=s.estado, motivo=s.motivo,
        fecha_resolucion=(s.fecha_resolucion.isoformat() if s.fecha_resolucion else None),
    )


@router.get("/solicitudes", response_model=List[SolicitudOut])
def listar_solicitudes(
    empleado_id: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(SolicitudVacaciones).filter(
        SolicitudVacaciones.empresa_id == payload["empresa_id"])
    if empleado_id:
        qry = qry.filter(SolicitudVacaciones.empleado_id == empleado_id)
    if estado:
        qry = qry.filter(SolicitudVacaciones.estado == estado)
    rows = qry.order_by(SolicitudVacaciones.created_at.desc()).limit(500).all()
    return [_sol_out(db, s) for s in rows]


@router.post("/solicitudes", response_model=SolicitudOut, status_code=201)
def crear_solicitud(body: SolicitudIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    self_emp = _empleado_actual(db, payload)
    # Auto-solicitud (propio): libre para cualquier empleado con ficha.
    # Solicitar por OTRO empleado: requiere permiso vacaciones:solicitar.
    if body.empleado_id and (not self_emp or body.empleado_id != str(self_emp.id)):
        exigir_permiso(db, payload, "vacaciones", "solicitar")
        emp = db.query(Empleado).filter(
            Empleado.id == body.empleado_id, Empleado.empresa_id == empresa_id).first()
    else:
        emp = self_emp
    if not emp:
        raise HTTPException(status_code=404, detail="Tu usuario no tiene ficha de empleado")
    ini = _parse_date(body.fecha_inicio)
    fin = _parse_date(body.fecha_fin)
    if fin < ini:
        raise HTTPException(status_code=422, detail="fecha_fin no puede ser anterior a fecha_inicio")
    dias = (fin - ini).days + 1
    saldo = _saldo(db, empresa_id, emp, _get_config(db, empresa_id))
    if dias > saldo.disponible:
        raise HTTPException(
            status_code=409,
            detail=f"Saldo insuficiente: solicitas {dias} d, disponible {saldo.disponible:.1f} d")
    s = SolicitudVacaciones(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, empleado_id=str(emp.id),
        fecha_inicio=ini, fecha_fin=fin, dias=dias, estado="pendiente",
        motivo=body.motivo, solicitado_por_id=payload.get("id"),
    )
    db.add(s)
    db.commit()
    return _sol_out(db, s)


# ── Autoservicio del empleado (token) ────────────────────────────────────────
@router.get("/mi-saldo", response_model=SaldoOut)
def mi_saldo(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    empresa_id = payload["empresa_id"]
    emp = _empleado_actual(db, payload)
    if not emp:
        raise HTTPException(status_code=404, detail="Tu usuario no tiene ficha de empleado")
    return _saldo(db, empresa_id, emp, _get_config(db, empresa_id))


@router.get("/mis-solicitudes", response_model=List[SolicitudOut])
def mis_solicitudes(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    emp = _empleado_actual(db, payload)
    if not emp:
        return []
    rows = (
        db.query(SolicitudVacaciones)
        .filter(SolicitudVacaciones.empresa_id == payload["empresa_id"],
                SolicitudVacaciones.empleado_id == str(emp.id))
        .order_by(SolicitudVacaciones.created_at.desc())
        .limit(200).all()
    )
    return [_sol_out(db, s) for s in rows]


def _resolver(db: Session, payload: dict, sol_id: str, nuevo_estado: str) -> SolicitudOut:
    empresa_id = payload["empresa_id"]
    s = db.query(SolicitudVacaciones).filter(
        SolicitudVacaciones.id == sol_id, SolicitudVacaciones.empresa_id == empresa_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if s.estado != "pendiente":
        raise HTTPException(status_code=409, detail=f"La solicitud ya está {s.estado}")
    if nuevo_estado == "aprobada":
        # Validar saldo disponible antes de aprobar
        emp = db.query(Empleado).filter(Empleado.id == s.empleado_id).first()
        cfg = _get_config(db, empresa_id)
        saldo = _saldo(db, empresa_id, emp, cfg)
        if s.dias > saldo.disponible:
            raise HTTPException(
                status_code=409,
                detail=f"Saldo insuficiente: solicita {s.dias} d, disponible {saldo.disponible} d")
    s.estado = nuevo_estado
    s.resuelto_por_id = payload.get("id")
    s.fecha_resolucion = datetime.utcnow()
    db.commit()

    # Notificar al solicitante el resultado de su solicitud.
    try:
        emp = db.query(Empleado).filter(Empleado.id == s.empleado_id).first()
        if emp and emp.usuario_id:
            if nuevo_estado == "aprobada":
                titulo = "Vacaciones aprobadas"
                mensaje = (f"Tu solicitud de {s.dias} día(s) "
                           f"({s.fecha_inicio.isoformat()} al {s.fecha_fin.isoformat()}) fue aprobada.")
            else:
                titulo = "Vacaciones rechazadas"
                mensaje = (f"Tu solicitud de {s.dias} día(s) "
                           f"({s.fecha_inicio.isoformat()} al {s.fecha_fin.isoformat()}) fue rechazada.")
            notificar_usuario(
                db, empresa_id=empresa_id, usuario_id=emp.usuario_id,
                titulo=titulo, mensaje=mensaje,
                tipo="recordatorio", categoria="vacaciones",
                referencia_tabla=f"vacaciones:{s.id}",
            )
            db.commit()
    except Exception:
        db.rollback()

    return _sol_out(db, s)


@router.post("/solicitudes/{sol_id}/aprobar", response_model=SolicitudOut)
def aprobar(sol_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "vacaciones", "aprobar")
    return _resolver(db, payload, sol_id, "aprobada")


@router.post("/solicitudes/{sol_id}/rechazar", response_model=SolicitudOut)
def rechazar(sol_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "vacaciones", "rechazar")
    return _resolver(db, payload, sol_id, "rechazada")


# ── Ajuste de saldo inicial (migración) ──────────────────────────────────────
@router.put("/saldo-inicial/{empleado_id}", response_model=AjusteSaldoOut)
def fijar_saldo_inicial(
    empleado_id: str,
    body: AjusteSaldoIn,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    """Fija el saldo de vacaciones disponibles de un empleado a `dias_disponibles`,
    calculando el ajuste necesario según el devengado actual (años completos).
    Requiere permiso vacaciones:configurar. Idempotente (upsert)."""
    exigir_permiso(db, payload, "vacaciones", "configurar")
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    cfg = _get_config(db, empresa_id)
    meses = _meses_servicio(emp.fecha_ingreso, date.today())
    anos = meses // 12
    devengado_actual = float(anos * cfg.dias_por_anio)
    # ajuste = diferencia entre lo que queremos que tenga y lo que ya tiene por devengo
    ajuste = int(round(body.dias_disponibles - devengado_actual))
    row = db.query(AjusteSaldoVacaciones).filter(
        AjusteSaldoVacaciones.empleado_id == empleado_id).first()
    if row:
        row.ajuste_dias = ajuste
        row.notas = body.notas
        row.creado_por_id = payload.get("id")
        row.updated_at = datetime.utcnow()
    else:
        row = AjusteSaldoVacaciones(
            id=str(_uuid.uuid4()), empresa_id=empresa_id,
            empleado_id=empleado_id, ajuste_dias=ajuste,
            notas=body.notas, creado_por_id=payload.get("id"),
        )
        db.add(row)
    db.commit()
    return AjusteSaldoOut(
        empleado_id=empleado_id, ajuste_dias=ajuste, notas=row.notas)


# ── Helpers de reporte ────────────────────────────────────────────────────────

def _saldos_todos(db: Session, empresa_id: str):
    cfg = _get_config(db, empresa_id)
    emps = (
        db.query(Empleado)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)  # noqa: E712
        .all()
    )
    saldos = [_saldo(db, empresa_id, e, cfg) for e in emps]
    saldos.sort(key=lambda s: (s.empleado_nombre or ""))
    return saldos, cfg


_ESTADO_LABEL = {
    "sin_derecho": "Sin derecho (<1 año)",
    "agotado":     "Saldo agotado",
    "disponible":  "Con días disponibles",
}


# ── Reporte Excel ─────────────────────────────────────────────────────────────

@router.get("/reporte.xlsx")
def reporte_excel(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.utils import get_column_letter

    empresa_id = payload["empresa_id"]
    saldos, cfg = _saldos_todos(db, empresa_id)

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Vacaciones"

    # ── Paleta ────────────────────────────────────────────────────────────────
    AZUL      = "1A56DB"
    BLANCO    = "FFFFFF"
    ROJO_BG   = "FEE2E2"
    ROJO_FG   = "991B1B"
    VERDE_BG  = "DCFCE7"
    VERDE_FG  = "166534"
    AMBAR_BG  = "FEF3C7"
    AMBAR_FG  = "92400E"
    GRIS_HDR  = "F1F5F9"
    GRIS_BORD = "CBD5E1"

    thin = Side(style="thin", color=GRIS_BORD)
    borde = Border(left=thin, right=thin, top=thin, bottom=thin)

    regimen_label = {"general": "General (30 d/año)", "remype": "REMYPE (15 d/año)"}.get(
        cfg.regimen, f"Otro ({cfg.dias_por_anio} d/año)"
    )

    # ── Título ────────────────────────────────────────────────────────────────
    ws.merge_cells("A1:K1")
    c = ws["A1"]
    c.value = "REPORTE DE VACACIONES POR LEY"
    c.font = Font(name="Calibri", bold=True, size=14, color=BLANCO)
    c.fill = PatternFill("solid", fgColor=AZUL)
    c.alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 28

    ws.merge_cells("A2:K2")
    c = ws["A2"]
    c.value = (
        f"Régimen: {regimen_label}   |   "
        f"Tope acumulación: {cfg.tope_acumulacion} días   |   "
        f"Generado: {date.today().strftime('%d/%m/%Y')}"
    )
    c.font = Font(name="Calibri", size=10, color="475569")
    c.alignment = Alignment(horizontal="center")
    ws.row_dimensions[2].height = 18

    ws.row_dimensions[3].height = 6   # espacio

    # ── Encabezados ───────────────────────────────────────────────────────────
    COLS = [
        ("N°",              6),
        ("Empleado",        28),
        ("Cargo",           22),
        ("F. Ingreso",      13),
        ("Meses serv.",     13),
        ("Años serv.",      11),
        ("Días/año",        10),
        ("Devengado",       12),
        ("Gozado",          10),
        ("Disponible",      12),
        ("Estado",          22),
    ]
    HDR_ROW = 4
    for ci, (titulo, ancho) in enumerate(COLS, 1):
        col_letter = get_column_letter(ci)
        ws.column_dimensions[col_letter].width = ancho
        cell = ws.cell(row=HDR_ROW, column=ci, value=titulo)
        cell.font = Font(name="Calibri", bold=True, size=10, color="1E293B")
        cell.fill = PatternFill("solid", fgColor=GRIS_HDR)
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = borde
    ws.row_dimensions[HDR_ROW].height = 24

    # ── Filas de datos ────────────────────────────────────────────────────────
    for idx, s in enumerate(saldos, 1):
        row = HDR_ROW + idx
        estado = s.estado_vacaciones

        if estado == "sin_derecho":
            bg, fg = AMBAR_BG, AMBAR_FG
        elif estado == "agotado":
            bg, fg = ROJO_BG, ROJO_FG
        else:
            bg, fg = VERDE_BG, VERDE_FG

        valores = [
            idx,
            s.empleado_nombre or "",
            s.cargo or "",
            s.fecha_ingreso or "",
            s.meses_servicio,
            s.anos_servicio,
            s.dias_por_anio,
            s.devengado,
            s.gozado,
            s.disponible,
            _ESTADO_LABEL.get(estado, estado),
        ]
        for ci, val in enumerate(valores, 1):
            cell = ws.cell(row=row, column=ci, value=val)
            cell.font = Font(name="Calibri", size=10,
                             color=(fg if ci == 11 else "1E293B"),
                             bold=(ci == 11))
            if ci == 11:
                cell.fill = PatternFill("solid", fgColor=bg)
            cell.alignment = Alignment(
                horizontal="center" if ci in (1, 4, 5, 6, 7, 8, 9, 10) else "left",
                vertical="center"
            )
            cell.border = borde
        ws.row_dimensions[row].height = 20

    # ── Congelar encabezado ───────────────────────────────────────────────────
    ws.freeze_panes = ws.cell(row=HDR_ROW + 1, column=1)

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    filename = f"vacaciones_{date.today().isoformat()}.xlsx"
    return StreamingResponse(
        buf,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ── Reporte PDF ───────────────────────────────────────────────────────────────

@router.get("/reporte.pdf")
def reporte_pdf(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib import colors
    from reportlab.lib.units import cm
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer,
    )
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_LEFT

    empresa_id = payload["empresa_id"]
    saldos, cfg = _saldos_todos(db, empresa_id)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=landscape(A4),
        leftMargin=1.5*cm, rightMargin=1.5*cm,
        topMargin=1.5*cm, bottomMargin=1.5*cm,
    )

    styles = getSampleStyleSheet()
    AZUL     = colors.HexColor("#1A56DB")
    GRIS     = colors.HexColor("#64748B")
    ROJO_BG  = colors.HexColor("#FEE2E2")
    ROJO_FG  = colors.HexColor("#991B1B")
    VERDE_BG = colors.HexColor("#DCFCE7")
    AMBAR_BG = colors.HexColor("#FEF3C7")
    BLANCO   = colors.white
    HDR_BG   = colors.HexColor("#1E3A5F")

    regimen_label = {"general": "General (30 d/año)", "remype": "REMYPE (15 d/año)"}.get(
        cfg.regimen, f"Otro ({cfg.dias_por_anio} d/año)"
    )

    story = []

    # Título
    title_style = ParagraphStyle("title", fontSize=16, textColor=AZUL,
                                  alignment=TA_CENTER, fontName="Helvetica-Bold",
                                  spaceAfter=4)
    sub_style   = ParagraphStyle("sub", fontSize=9, textColor=GRIS,
                                  alignment=TA_CENTER, spaceAfter=12)
    story.append(Paragraph("REPORTE DE VACACIONES POR LEY (SUNAFIL)", title_style))
    story.append(Paragraph(
        f"Régimen: {regimen_label} &nbsp;|&nbsp; "
        f"Tope: {cfg.tope_acumulacion} días &nbsp;|&nbsp; "
        f"Generado: {date.today().strftime('%d/%m/%Y')}",
        sub_style,
    ))
    story.append(Spacer(1, 0.3*cm))

    # Tabla
    hdr = ["N°", "Empleado", "Cargo", "F. Ingreso", "Meses", "Años",
           "Días/Año", "Devengado", "Gozado", "Disponible", "Estado"]
    col_widths = [1*cm, 5.5*cm, 4.5*cm, 2.5*cm, 2*cm, 1.8*cm,
                  2.2*cm, 2.4*cm, 2*cm, 2.4*cm, 4*cm]

    cell_style = ParagraphStyle("cell", fontSize=8, fontName="Helvetica",
                                 leading=10, alignment=TA_LEFT)
    ctr_style  = ParagraphStyle("ctr",  fontSize=8, fontName="Helvetica",
                                 leading=10, alignment=TA_CENTER)

    data = [hdr]
    row_colors: list[tuple] = []

    for idx, s in enumerate(saldos, 1):
        estado = s.estado_vacaciones
        if estado == "sin_derecho":
            row_bg = AMBAR_BG
        elif estado == "agotado":
            row_bg = ROJO_BG
        else:
            row_bg = VERDE_BG
        row_colors.append(row_bg)

        data.append([
            Paragraph(str(idx),                         ctr_style),
            Paragraph(s.empleado_nombre or "",          cell_style),
            Paragraph(s.cargo or "",                    cell_style),
            Paragraph(s.fecha_ingreso or "",            ctr_style),
            Paragraph(str(s.meses_servicio),            ctr_style),
            Paragraph(str(s.anos_servicio),             ctr_style),
            Paragraph(str(s.dias_por_anio),             ctr_style),
            Paragraph(str(int(s.devengado)),            ctr_style),
            Paragraph(str(s.gozado),                    ctr_style),
            Paragraph(f"{s.disponible:.0f}",            ctr_style),
            Paragraph(_ESTADO_LABEL.get(estado, estado), cell_style),
        ])

    t = Table(data, colWidths=col_widths, repeatRows=1)

    ts = TableStyle([
        # Encabezado
        ("BACKGROUND",  (0, 0), (-1, 0), HDR_BG),
        ("TEXTCOLOR",   (0, 0), (-1, 0), BLANCO),
        ("FONTNAME",    (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE",    (0, 0), (-1, 0), 8),
        ("ALIGN",       (0, 0), (-1, 0), "CENTER"),
        ("VALIGN",      (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUND", (0, 1), (-1, -1), [colors.white]),
        ("GRID",        (0, 0), (-1, -1), 0.4, colors.HexColor("#CBD5E1")),
        ("TOPPADDING",  (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ])
    # Filas con color según estado
    for ri, bg in enumerate(row_colors, 1):
        ts.add("BACKGROUND", (0, ri), (-1, ri), bg)
    t.setStyle(ts)

    story.append(t)
    story.append(Spacer(1, 0.6*cm))

    # Leyenda
    leyenda_style = ParagraphStyle("ley", fontSize=7.5, textColor=GRIS,
                                    alignment=TA_LEFT)
    story.append(Paragraph(
        "<b>Leyenda:</b> &nbsp;"
        "<font color='#92400E'>Amarillo = Sin derecho (menos de 12 meses de servicio)</font> &nbsp;|&nbsp; "
        "<font color='#991B1B'>Rojo = Saldo agotado (días disponibles = 0)</font> &nbsp;|&nbsp; "
        "<font color='#166534'>Verde = Con días disponibles</font>",
        leyenda_style,
    ))
    story.append(Spacer(1, 0.3*cm))
    story.append(Paragraph(
        "Normativa: D. Leg. N° 713 · D.S. 013-2013-PRODUCE (REMYPE) · D. Leg. N° 1405 (fraccionamiento)",
        ParagraphStyle("norm", fontSize=7, textColor=colors.HexColor("#94A3B8"), alignment=TA_LEFT),
    ))

    doc.build(story)
    buf.seek(0)
    filename = f"vacaciones_{date.today().isoformat()}.pdf"
    return StreamingResponse(
        buf, media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
