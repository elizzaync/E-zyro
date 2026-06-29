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
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.vacaciones import AjusteSaldoVacaciones, ConfigVacaciones, SolicitudVacaciones
from ..models.solicitud_laboral import SolicitudLaboral
from ..services.fcm_service import notificar_usuario
from ..schemas.vacaciones import (
    AjusteSaldoIn, AjusteSaldoOut, ConfigIn, ConfigOut, SaldoOut, SolicitudIn, SolicitudOut,
    DetalleSolicitudVac,
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


def _gozado_detalle(db: Session, empresa_id: str, empleado_id: str) -> tuple[int, list]:
    """Suma los días de solicitudes_laborales de tipo vacaciones aprobadas."""
    rows = (
        db.query(SolicitudLaboral)
        .filter(
            SolicitudLaboral.empresa_id == empresa_id,
            SolicitudLaboral.empleado_id == empleado_id,
            SolicitudLaboral.tipo.ilike("vacaciones"),
            SolicitudLaboral.estado == "aprobada",
            SolicitudLaboral.fecha_inicio.isnot(None),
            SolicitudLaboral.fecha_fin.isnot(None),
        )
        .order_by(SolicitudLaboral.fecha_inicio)
        .all()
    )
    detalle: list[DetalleSolicitudVac] = []
    total = 0
    for r in rows:
        dias = (r.fecha_fin - r.fecha_inicio).days + 1
        total += dias
        detalle.append(DetalleSolicitudVac(
            fecha_inicio=r.fecha_inicio.isoformat(),
            fecha_fin=r.fecha_fin.isoformat(),
            dias=dias,
            fecha_aprobacion=r.fecha_aprobacion.isoformat() if r.fecha_aprobacion else None,
        ))
    return total, detalle


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
    anos = meses // 12
    devengado = float(anos * cfg.dias_por_anio)
    ajuste_dias = _ajuste(db, str(emp.id))
    gozado, solicitudes_gozadas = _gozado_detalle(db, empresa_id, str(emp.id))
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
        solicitudes_gozadas=solicitudes_gozadas,
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

    # ── Hoja 2: Detalle de períodos aprobados ─────────────────────────────────
    ws2 = wb.create_sheet("Detalle Períodos")
    DET_COLS = [
        ("Empleado",      28), ("Cargo",      18), ("Desde",     13),
        ("Hasta",         13), ("Días",        8), ("Aprobado el", 15),
    ]
    for ci, (titulo, ancho) in enumerate(DET_COLS, 1):
        col_l = get_column_letter(ci)
        ws2.column_dimensions[col_l].width = ancho
        c2 = ws2.cell(row=1, column=ci, value=titulo)
        c2.font = Font(name="Calibri", bold=True, size=10, color="1E293B")
        c2.fill = PatternFill("solid", fgColor="1E3A5F")
        c2.font = Font(name="Calibri", bold=True, size=10, color=BLANCO)
        c2.alignment = Alignment(horizontal="center", vertical="center")
        c2.border = borde
    ws2.row_dimensions[1].height = 22

    det_row = 2
    for s in saldos:
        if not s.solicitudes_gozadas:
            continue
        for per in s.solicitudes_gozadas:
            vals = [
                s.empleado_nombre or "",
                s.cargo or "",
                per.fecha_inicio,
                per.fecha_fin,
                per.dias,
                per.fecha_aprobacion[:10] if per.fecha_aprobacion else "",
            ]
            for ci, val in enumerate(vals, 1):
                c2 = ws2.cell(row=det_row, column=ci, value=val)
                c2.font = Font(name="Calibri", size=10)
                c2.alignment = Alignment(
                    horizontal="center" if ci > 2 else "left", vertical="center"
                )
                c2.border = borde
                if ci == 5:
                    c2.fill = PatternFill("solid", fgColor=VERDE_BG)
            ws2.row_dimensions[det_row].height = 18
            det_row += 1
    ws2.freeze_panes = ws2.cell(row=2, column=1)

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

def _pdf_footer(canvas, doc, fecha_gen: str, total_pags_ref: list):
    """Pie de página numerado en todas las hojas."""
    from reportlab.lib import colors as _c
    from reportlab.lib.units import cm as _cm
    w, h = doc.pagesize
    canvas.saveState()
    canvas.setFont("Helvetica", 6.5)
    canvas.setFillColor(_c.HexColor("#94A3B8"))
    canvas.drawString(1.5*_cm, 0.7*_cm,
        f"CONFIDENCIAL — Uso exclusivo de Gerencia y Recursos Humanos  |  "
        f"Generado: {fecha_gen}  |  "
        f"Normativa: D.Leg. 713 · D.S. 013-2013-PRODUCE · D.Leg. 1405")
    canvas.drawRightString(w - 1.5*_cm, 0.7*_cm, f"Página {doc.page}")
    canvas.setStrokeColor(_c.HexColor("#E2E8F0"))
    canvas.setLineWidth(0.5)
    canvas.line(1.5*_cm, 1*_cm, w - 1.5*_cm, 1*_cm)
    canvas.restoreState()


@router.get("/reporte.pdf")
def reporte_pdf(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib import colors
    from reportlab.lib.units import cm
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer,
        HRFlowable, KeepTogether, PageBreak,
    )
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY

    empresa_id = payload["empresa_id"]
    saldos, cfg = _saldos_todos(db, empresa_id)
    hoy = date.today()
    fecha_gen = hoy.strftime("%d/%m/%Y")

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=landscape(A4),
        leftMargin=1.8*cm, rightMargin=1.8*cm,
        topMargin=1.6*cm, bottomMargin=1.8*cm,
    )
    PAGE_W = landscape(A4)[0] - 3.6*cm   # ancho útil

    # ── Paleta corporativa ────────────────────────────────────────────────────
    AZUL      = colors.HexColor("#1A56DB")
    AZUL_OSC  = colors.HexColor("#1E3A5F")
    AZUL_MED  = colors.HexColor("#1D4ED8")
    AZUL_CLR  = colors.HexColor("#EFF6FF")
    GRIS      = colors.HexColor("#64748B")
    GRIS_CLR  = colors.HexColor("#F8FAFC")
    GRIS_BRD  = colors.HexColor("#CBD5E1")
    GRIS_BRD2 = colors.HexColor("#E2E8F0")
    ROJO_BG   = colors.HexColor("#FEF2F2")
    ROJO_FG   = colors.HexColor("#B91C1C")
    VERDE_BG  = colors.HexColor("#F0FDF4")
    VERDE_FG  = colors.HexColor("#15803D")
    AMBAR_BG  = colors.HexColor("#FFFBEB")
    AMBAR_FG  = colors.HexColor("#B45309")
    BLANCO    = colors.white
    NEGRO     = colors.HexColor("#0F172A")
    PLOMO     = colors.HexColor("#475569")

    regimen_label = {
        "general": "Régimen General",
        "remype":  "Régimen REMYPE (Pequeña Empresa)",
    }.get(cfg.regimen, f"Régimen especial")

    def _fmt(iso: Optional[str]) -> str:
        if not iso:
            return "—"
        try:
            return date.fromisoformat(iso[:10]).strftime("%d/%m/%Y")
        except Exception:
            return iso

    # ── Estilos tipográficos ──────────────────────────────────────────────────
    def PS(name, **kw):
        return ParagraphStyle(name, **kw)

    T_MAIN   = PS("TM",  fontSize=18, textColor=BLANCO,    fontName="Helvetica-Bold",
                  alignment=TA_LEFT, leading=22)
    T_SUB    = PS("TS",  fontSize=9,  textColor=colors.HexColor("#BFDBFE"),
                  fontName="Helvetica", alignment=TA_LEFT, leading=13)
    T_CONF   = PS("TC",  fontSize=7.5, textColor=colors.HexColor("#FEF3C7"),
                  fontName="Helvetica-Bold", alignment=TA_RIGHT)
    SEC_ST   = PS("SEC", fontSize=10, textColor=AZUL_OSC, fontName="Helvetica-Bold",
                  spaceBefore=12, spaceAfter=5, leading=13)
    BODY_ST  = PS("BD",  fontSize=8.5, textColor=PLOMO, fontName="Helvetica",
                  leading=13, spaceAfter=3, alignment=TA_JUSTIFY)
    BULL_ST  = PS("BL",  fontSize=8.5, textColor=NEGRO, fontName="Helvetica",
                  leading=13, leftIndent=12, spaceAfter=2)
    CELL_ST  = PS("C",   fontSize=8,   fontName="Helvetica", leading=10, alignment=TA_LEFT)
    CTR_ST   = PS("CT",  fontSize=8,   fontName="Helvetica", leading=10, alignment=TA_CENTER)
    CTR_B    = PS("CTB", fontSize=8,   fontName="Helvetica-Bold", leading=10, alignment=TA_CENTER)
    SML_ST   = PS("SM",  fontSize=7.5, fontName="Helvetica", leading=9.5,
                  alignment=TA_LEFT,   textColor=PLOMO)
    SML_CTR  = PS("SMC", fontSize=7.5, fontName="Helvetica", leading=9.5,
                  alignment=TA_CENTER, textColor=PLOMO)
    NORM_ST  = PS("N",   fontSize=7,   textColor=colors.HexColor("#94A3B8"), alignment=TA_LEFT)
    LABEL_ST = PS("LB",  fontSize=7,   fontName="Helvetica-Bold", textColor=PLOMO,
                  alignment=TA_CENTER, leading=9)
    VAL_ST   = PS("VL",  fontSize=14,  fontName="Helvetica-Bold", textColor=AZUL_OSC,
                  alignment=TA_CENTER, leading=16)
    KPI_SUB  = PS("KS",  fontSize=7,   fontName="Helvetica", textColor=GRIS,
                  alignment=TA_CENTER, leading=9)

    story = []

    # ════════════════════════════════════════════════════════════════════════
    # BLOQUE CABECERA (banner de color)
    # ════════════════════════════════════════════════════════════════════════
    hdr_inner = Table(
        [[
            Paragraph(
                "REPORTE DE VACACIONES<br/>"
                "<font size='10'>Control de saldos y períodos por ley · Recursos Humanos</font>",
                T_MAIN,
            ),
            Paragraph(
                f"CONFIDENCIAL<br/>"
                f"<font size='7' color='#BFDBFE'>Uso exclusivo de Gerencia y RR.HH.</font>",
                T_CONF,
            ),
        ]],
        colWidths=[PAGE_W * 0.72, PAGE_W * 0.28],
    )
    hdr_inner.setStyle(TableStyle([
        ("VALIGN",       (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING",   (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 10),
        ("LEFTPADDING",  (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ]))
    hdr_wrap = Table([[hdr_inner]], colWidths=[PAGE_W])
    hdr_wrap.setStyle(TableStyle([
        ("BACKGROUND",   (0, 0), (-1, -1), AZUL_OSC),
        ("TOPPADDING",   (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 6),
        ("LEFTPADDING",  (0, 0), (-1, -1), 14),
        ("RIGHTPADDING", (0, 0), (-1, -1), 14),
        ("ROUNDEDCORNERS", (0, 0), (-1, -1), [4]),
    ]))
    story.append(hdr_wrap)

    # Banda de metadatos bajo el banner
    meta = Table([[
        Paragraph(f"<b>Régimen:</b> {regimen_label}", SML_ST),
        Paragraph(f"<b>Días por año:</b> {cfg.dias_por_anio}", SML_ST),
        Paragraph(f"<b>Tope de acumulación:</b> {cfg.tope_acumulacion} días", SML_ST),
        Paragraph(f"<b>Fecha de emisión:</b> {fecha_gen}", SML_ST),
        Paragraph(f"<b>Total empleados activos:</b> {len(saldos)}", SML_ST),
    ]], colWidths=[PAGE_W / 5] * 5)
    meta.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), AZUL_CLR),
        ("TOPPADDING",    (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING",   (0, 0), (-1, -1), 8),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 8),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("LINEBELOW",     (0, 0), (-1, -1), 0.5, GRIS_BRD),
    ]))
    story.append(meta)
    story.append(Spacer(1, 0.4*cm))

    # ════════════════════════════════════════════════════════════════════════
    # KPIs EJECUTIVOS (4 tarjetas)
    # ════════════════════════════════════════════════════════════════════════
    con_derecho  = [s for s in saldos if s.meses_servicio >= 12]
    sin_derecho  = [s for s in saldos if s.meses_servicio < 12]
    total_gozado = sum(s.gozado for s in saldos)
    total_disp   = sum(s.disponible for s in saldos)

    def _kpi_cell(valor, label, sub, bg, fg):
        t = Table([[
            Paragraph(str(valor), PS("V", fontSize=20, fontName="Helvetica-Bold",
                                     textColor=fg, alignment=TA_CENTER, leading=22)),
            ],[
            Paragraph(label, PS("L", fontSize=8, fontName="Helvetica-Bold",
                                 textColor=fg, alignment=TA_CENTER, leading=10)),
            ],[
            Paragraph(sub, PS("S", fontSize=7, fontName="Helvetica",
                               textColor=fg, alignment=TA_CENTER, leading=9)),
        ]])
        t.setStyle(TableStyle([
            ("BACKGROUND",    (0, 0), (-1, -1), bg),
            ("TOPPADDING",    (0, 0), (-1, -1), 8),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ("ALIGN",         (0, 0), (-1, -1), "CENTER"),
            ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ]))
        return t

    kpi_w = (PAGE_W - 0.6*cm) / 4
    kpis = Table([[
        _kpi_cell(len(saldos),    "TOTAL EMPLEADOS",       "Activos en el sistema",         AZUL_CLR,  AZUL_OSC),
        _kpi_cell(len(con_derecho),"CON DERECHO",          f"≥ 12 meses de servicio",        VERDE_BG,  VERDE_FG),
        _kpi_cell(f"{total_gozado}d", "DÍAS GOZADOS",     "Vacaciones aprobadas y tomadas", AMBAR_BG,  AMBAR_FG),
        _kpi_cell(f"{int(total_disp)}d","DÍAS DISPONIBLES","Pendientes de goce",            ROJO_BG,   ROJO_FG),
    ]], colWidths=[kpi_w]*4, rowHeights=[None])
    kpis.setStyle(TableStyle([
        ("LINEAFTER",     (0, 0), (2, -1), 0.5, GRIS_BRD2),
        ("BOX",           (0, 0), (-1, -1), 0.8, GRIS_BRD),
        ("LEFTPADDING",   (0, 0), (-1, -1), 0),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 0),
        ("TOPPADDING",    (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    story.append(kpis)
    story.append(Spacer(1, 0.5*cm))
    story.append(HRFlowable(width="100%", thickness=0.6, color=GRIS_BRD2, spaceAfter=4))

    # ════════════════════════════════════════════════════════════════════════
    # SECCIÓN 1 — RESUMEN DE SALDOS
    # ════════════════════════════════════════════════════════════════════════
    story.append(Paragraph("1.  Resumen de Saldos por Empleado", SEC_ST))

    hdr_res = [
        Paragraph("<b>N°</b>",         CTR_ST),
        Paragraph("<b>Empleado</b>",    CELL_ST),
        Paragraph("<b>Cargo</b>",       CELL_ST),
        Paragraph("<b>F. Ingreso</b>",  CTR_ST),
        Paragraph("<b>Meses</b>",       CTR_ST),
        Paragraph("<b>Años</b>",        CTR_ST),
        Paragraph("<b>Días/Año</b>",    CTR_ST),
        Paragraph("<b>Devengado</b>",   CTR_ST),
        Paragraph("<b>Gozado</b>",      CTR_ST),
        Paragraph("<b>Disponible</b>",  CTR_ST),
        Paragraph("<b>Estado</b>",      CTR_ST),
    ]
    cw_res = [0.8*cm, 5*cm, 4*cm, 2.3*cm, 1.7*cm, 1.5*cm,
              2*cm, 2.1*cm, 1.8*cm, 2.1*cm, None]
    cw_res[-1] = PAGE_W - sum(cw_res[:-1])

    data_res = [hdr_res]
    row_clrs: list = []

    for idx, s in enumerate(saldos, 1):
        est = s.estado_vacaciones
        if est == "sin_derecho":
            row_bg, est_fg, est_txt = AMBAR_BG, AMBAR_FG, "Sin derecho"
        elif est == "agotado":
            row_bg, est_fg, est_txt = ROJO_BG,  ROJO_FG,  "Saldo agotado"
        else:
            row_bg, est_fg, est_txt = VERDE_BG, VERDE_FG, f"{s.disponible:.0f} días disp."
        row_clrs.append(row_bg)

        est_st = PS(f"ES{idx}", fontSize=7.5, fontName="Helvetica-Bold",
                    textColor=est_fg, alignment=TA_CENTER, leading=9)
        data_res.append([
            Paragraph(str(idx),              CTR_ST),
            Paragraph(s.empleado_nombre or "", CELL_ST),
            Paragraph(s.cargo or "",          CELL_ST),
            Paragraph(_fmt(s.fecha_ingreso),  CTR_ST),
            Paragraph(str(s.meses_servicio),  CTR_ST),
            Paragraph(str(s.anos_servicio),   CTR_ST),
            Paragraph(str(s.dias_por_anio),   CTR_ST),
            Paragraph(str(int(s.devengado)),  CTR_ST),
            Paragraph(f"<b>{s.gozado}</b>" if s.gozado else "0", CTR_ST),
            Paragraph(f"<b>{s.disponible:.0f}</b>",               CTR_B),
            Paragraph(est_txt,                est_st),
        ])

    t_res = Table(data_res, colWidths=cw_res, repeatRows=1)
    ts_res = TableStyle([
        ("BACKGROUND",    (0, 0), (-1, 0), AZUL_OSC),
        ("TEXTCOLOR",     (0, 0), (-1, 0), BLANCO),
        ("ALIGN",         (0, 0), (-1, 0), "CENTER"),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("GRID",          (0, 0), (-1, -1), 0.35, GRIS_BRD2),
        ("LINEBELOW",     (0, 0), (-1, 0), 1.5, AZUL_MED),
        ("TOPPADDING",    (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ("LEFTPADDING",   (0, 0), (-1, -1), 5),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
    ])
    for ri, bg in enumerate(row_clrs, 1):
        ts_res.add("BACKGROUND", (0, ri), (-1, ri), bg)
        if ri % 2 == 0:
            pass  # alternado ya cubierto por row_clrs
    t_res.setStyle(ts_res)
    story.append(t_res)

    story.append(Spacer(1, 0.2*cm))
    ley_st = PS("LEY", fontSize=7, textColor=PLOMO, alignment=TA_LEFT, leading=10)
    story.append(Paragraph(
        "<font color='#B45309'><b>■</b></font> Amarillo = Sin derecho: el trabajador no ha cumplido 1 año de servicio. &nbsp;"
        "<font color='#B91C1C'><b>■</b></font> Rojo = Saldo agotado: días devengados ya consumidos. &nbsp;"
        "<font color='#15803D'><b>■</b></font> Verde = Con días disponibles para goce.",
        ley_st,
    ))

    # ════════════════════════════════════════════════════════════════════════
    # SECCIÓN 2 — MARCO LEGAL Y RÉGIMEN DE VACACIONES
    # ════════════════════════════════════════════════════════════════════════
    story.append(PageBreak())
    story.append(Paragraph("2.  Marco Legal y Régimen de Vacaciones (SUNAFIL — Perú)", SEC_ST))

    # Recuadro de régimen aplicable
    reg_color = AZUL_CLR
    reg_box = Table([[
        Paragraph(
            f"<b>Régimen aplicado a esta empresa: {regimen_label}</b><br/>"
            f"<font size='8'>{cfg.dias_por_anio} días de vacaciones por año completo de servicio · "
            f"Acumulación máxima: {cfg.tope_acumulacion} días ({cfg.tope_acumulacion // cfg.dias_por_anio} períodos)</font>",
            PS("RB", fontSize=9, fontName="Helvetica", textColor=AZUL_OSC,
               alignment=TA_LEFT, leading=13),
        )
    ]], colWidths=[PAGE_W])
    reg_box.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), reg_color),
        ("TOPPADDING",    (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ("LEFTPADDING",   (0, 0), (-1, -1), 12),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 12),
        ("LINERIGHT",     (0, 0), (0, -1), 4, AZUL_MED),
    ]))
    story.append(reg_box)
    story.append(Spacer(1, 0.35*cm))

    # Tabla de artículos legales
    leg_hdr = [
        Paragraph("<b>Norma</b>",           CTR_ST),
        Paragraph("<b>Artículo / Tema</b>", CELL_ST),
        Paragraph("<b>Descripción</b>",     CELL_ST),
        Paragraph("<b>Aplicación en empresa</b>", CELL_ST),
    ]
    leg_cw = [3.2*cm, 4*cm, None, 5.5*cm]
    leg_cw[2] = PAGE_W - sum(c for c in leg_cw if c)

    leg_data = [leg_hdr, *[
        [
            Paragraph(n, PS(f"LN{i}", fontSize=7.5, fontName="Helvetica-Bold",
                            textColor=AZUL_OSC, alignment=TA_CENTER, leading=10)),
            Paragraph(a, PS(f"LA{i}", fontSize=7.5, fontName="Helvetica-Bold",
                            textColor=NEGRO, leading=10)),
            Paragraph(d, PS(f"LD{i}", fontSize=7.5, fontName="Helvetica",
                            textColor=PLOMO, leading=11, alignment=TA_JUSTIFY)),
            Paragraph(ap, PS(f"LAP{i}", fontSize=7.5, fontName="Helvetica",
                             textColor=NEGRO, leading=11)),
        ]
        for i, (n, a, d, ap) in enumerate([
            (
                "D. Leg. N° 713\n(08/11/1991)",
                "Art. 10 — Requisito\nde devengamiento",
                "El trabajador adquiere el derecho a vacaciones al cumplir 1 año completo "
                "de servicios y haber laborado no menos del 80% de los días hábiles del año.",
                f"Empleados con {'menos de 12 meses' if cfg.dias_por_anio else '12 meses o más'} "
                "de servicio aparecen como 'Sin derecho' en este reporte.",
            ),
            (
                "D. Leg. N° 713\nArt. 12",
                "Días de descanso\nvacacional",
                "Régimen General: 30 días calendario por año completo de servicios. "
                "El derecho al goce es remunerado y obligatorio.",
                "No aplica directamente (empresa en régimen REMYPE)." if cfg.regimen == "remype"
                else f"Se aplican {cfg.dias_por_anio} días por año completo de servicio.",
            ),
            (
                "D.S. N° 013-2013\nPRODUCE — REMYPE\n(Art. 49)",
                "Régimen laboral\nde Pequeña Empresa",
                "Las Pequeñas Empresas inscritas en el REMYPE otorgan 15 días calendario "
                "de vacaciones por año completo de servicio, en lugar de los 30 días del "
                "régimen general. Beneficio compensado con menores costos laborales para el empleador.",
                f"Esta empresa aplica {cfg.dias_por_anio} d/año bajo el régimen REMYPE. "
                f"Tope de acumulación: {cfg.tope_acumulacion} días.",
            ),
            (
                "D. Leg. N° 713\nArt. 19 y 23",
                "Acumulación y\ntope vacacional",
                "Las vacaciones pueden acumularse de común acuerdo entre empleador y trabajador, "
                f"hasta un máximo de 2 períodos consecutivos. Para el régimen REMYPE (15 d/año), "
                f"el tope es de 30 días. Una vez alcanzado el tope, los días adicionales "
                "NO se acumulan — se pierde el derecho a los días no tomados por encima del límite.",
                f"Tope vigente: {cfg.tope_acumulacion} días ({cfg.tope_acumulacion // cfg.dias_por_anio} períodos). "
                "Los trabajadores que alcanzan este tope deben programar su goce.",
            ),
            (
                "D. Leg. N° 713\nArt. 23 — Prescripción",
                "Prescripción del\npago doble",
                "Si el empleador no otorga las vacaciones dentro del año siguiente a "
                "aquel en que se generó el derecho, el trabajador tiene derecho a percibir: "
                "(1) la remuneración del mes vacacional, (2) una remuneración adicional por "
                "el trabajo en período de vacaciones, y (3) una indemnización equivalente a "
                "una remuneración mensual. El derecho a la indemnización prescribe a los 2 años.",
                "Las vacaciones no gozadas generan un pasivo laboral para la empresa. "
                "Se recomienda programar el goce antes del vencimiento del período.",
            ),
            (
                "D. Leg. N° 1405\n(12/09/2018)",
                "Fraccionamiento\nvacacional",
                "El trabajador puede solicitar el fraccionamiento de sus vacaciones en "
                "períodos mínimos de 7 días naturales, previa comunicación al empleador. "
                "El empleador puede reducir las vacaciones a un mínimo de 7 días, pagando "
                "la remuneración proporcional más 1/6 adicional del total.",
                "Los trabajadores con saldo disponible pueden fraccionar sus vacaciones "
                "en acuerdo con el área de Recursos Humanos.",
            ),
            (
                "D. Leg. N° 713\nArt. 16",
                "Pago vacacional",
                "El pago de la remuneración vacacional debe efectuarse antes del inicio "
                "del goce vacacional. La remuneración vacacional es equivalente a la que "
                "el trabajador hubiera percibido habitual y permanentemente.",
                "Coordinar con planilla el pago previo al inicio de cada período vacacional.",
            ),
        ], 1)
    ]]

    t_leg = Table(leg_data, colWidths=leg_cw, repeatRows=1)
    t_leg.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, 0), AZUL_OSC),
        ("TEXTCOLOR",     (0, 0), (-1, 0), BLANCO),
        ("ALIGN",         (0, 0), (0, -1), "CENTER"),
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
        ("GRID",          (0, 0), (-1, -1), 0.3, GRIS_BRD2),
        ("LINEBELOW",     (0, 0), (-1, 0), 1.5, AZUL_MED),
        ("TOPPADDING",    (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING",   (0, 0), (-1, -1), 6),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 6),
        ("ROWBACKGROUND", (0, 1), (-1, -1), [BLANCO, GRIS_CLR]),
    ]))
    story.append(t_leg)
    story.append(Spacer(1, 0.4*cm))

    # Cuadro de recomendaciones
    rec_box = Table([[
        Paragraph(
            "<b>Recomendaciones de Gestión para Gerencia:</b><br/>"
            "1. Programar el goce vacacional de trabajadores con saldo agotado o próximos al tope, "
            "para evitar la generación de pasivos laborales e indemnizaciones. &nbsp; "
            "2. Los trabajadores con saldo 0 (agotado) ya consumieron todos sus días devengados — "
            "no generan costo adicional si toman vacaciones dentro del año en curso. &nbsp; "
            "3. Los trabajadores 'Sin derecho' aún no cumplen el año; su primer derecho se activa "
            "al completar 12 meses continuos de servicio. &nbsp; "
            "4. Se recomienda actualizar el registro de vacaciones gozadas mensualmente para "
            "mantener el control del pasivo laboral.",
            PS("REC", fontSize=8, fontName="Helvetica", textColor=AZUL_OSC,
               alignment=TA_JUSTIFY, leading=12),
        )
    ]], colWidths=[PAGE_W])
    rec_box.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), AZUL_CLR),
        ("TOPPADDING",    (0, 0), (-1, -1), 9),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
        ("LEFTPADDING",   (0, 0), (-1, -1), 12),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 12),
        ("LINERIGHT",     (0, 0), (0, -1), 4, colors.HexColor("#3B82F6")),
    ]))
    story.append(rec_box)

    # ════════════════════════════════════════════════════════════════════════
    # SECCIÓN 3 — DETALLE POR EMPLEADO (sólo quienes tienen períodos aprobados)
    # ════════════════════════════════════════════════════════════════════════
    con_gozado = [s for s in saldos if s.solicitudes_gozadas]
    if con_gozado:
        story.append(PageBreak())
        story.append(Paragraph("3.  Detalle de Períodos de Vacaciones Gozadas por Empleado", SEC_ST))
        story.append(Paragraph(
            "Se listan únicamente los trabajadores con al menos una solicitud de vacaciones aprobada "
            "y efectivamente gozada. Los días mostrados en 'Gozado' se descuentan del saldo disponible.",
            PS("DET_INT", fontSize=8, textColor=PLOMO, fontName="Helvetica",
               leading=12, spaceAfter=8, alignment=TA_JUSTIFY),
        ))

        for s in con_gozado:
            bloque = []

            # Ficha del empleado
            ficha = Table([[
                Paragraph(f"<b>{s.empleado_nombre or '—'}</b>", CELL_ST),
                Paragraph(s.cargo or "", SML_ST),
                Paragraph(f"Ingreso: {_fmt(s.fecha_ingreso)}", SML_ST),
                Paragraph(f"{s.meses_servicio} meses / {s.anos_servicio} años", SML_ST),
                Paragraph(
                    f"Dev: <b>{int(s.devengado)}</b>d  "
                    f"Gozado: <b>{s.gozado}</b>d  "
                    f"Disp: <b>{s.disponible:.0f}</b>d",
                    PS("FC", fontSize=8, fontName="Helvetica-Bold", textColor=AZUL_OSC,
                       alignment=TA_RIGHT, leading=10),
                ),
            ]], colWidths=[5*cm, 3.5*cm, 2.8*cm, 3*cm, None])
            ficha_cw5 = PAGE_W - 5*cm - 3.5*cm - 2.8*cm - 3*cm
            ficha = Table([[
                Paragraph(f"<b>{s.empleado_nombre or '—'}</b>", CELL_ST),
                Paragraph(s.cargo or "", SML_ST),
                Paragraph(f"Ingreso: {_fmt(s.fecha_ingreso)}", SML_ST),
                Paragraph(f"{s.meses_servicio} meses / {s.anos_servicio} años", SML_ST),
                Paragraph(
                    f"Dev: <b>{int(s.devengado)}</b>d &nbsp; "
                    f"Gozado: <b>{s.gozado}</b>d &nbsp; "
                    f"Disp: <b>{s.disponible:.0f}</b>d",
                    PS(f"FC{s.empleado_id}", fontSize=8, fontName="Helvetica-Bold",
                       textColor=AZUL_OSC, alignment=TA_RIGHT, leading=10),
                ),
            ]], colWidths=[5*cm, 3.5*cm, 2.8*cm, 3*cm, ficha_cw5])
            ficha.setStyle(TableStyle([
                ("BACKGROUND",    (0, 0), (-1, -1), GRIS_CLR),
                ("TOPPADDING",    (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("LEFTPADDING",   (0, 0), (-1, -1), 8),
                ("RIGHTPADDING",  (0, 0), (-1, -1), 8),
                ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
                ("LINERIGHT",     (0, 0), (0, -1), 3, AZUL_MED),
            ]))
            bloque.append(ficha)

            # Tabla de períodos
            per_hdr = [
                Paragraph("<b>#</b>",             CTR_ST),
                Paragraph("<b>Desde</b>",          CTR_ST),
                Paragraph("<b>Hasta</b>",          CTR_ST),
                Paragraph("<b>Días gozados</b>",   CTR_ST),
                Paragraph("<b>Aprobado el</b>",    CTR_ST),
                Paragraph("<b>Observación</b>",    CELL_ST),
            ]
            per_cw = [0.8*cm, 2.8*cm, 2.8*cm, 2.5*cm, 2.8*cm, None]
            per_cw[-1] = PAGE_W - sum(c for c in per_cw if c)

            per_data = [per_hdr]
            for i, per in enumerate(s.solicitudes_gozadas, 1):
                per_data.append([
                    Paragraph(str(i),                   SML_CTR),
                    Paragraph(_fmt(per.fecha_inicio),   SML_CTR),
                    Paragraph(_fmt(per.fecha_fin),      SML_CTR),
                    Paragraph(f"<b>{per.dias}</b> día{'s' if per.dias != 1 else ''}", SML_CTR),
                    Paragraph(_fmt(per.fecha_aprobacion), SML_CTR),
                    Paragraph("Período aprobado y gozado", SML_ST),
                ])

            t_per = Table(per_data, colWidths=per_cw)
            t_per.setStyle(TableStyle([
                ("BACKGROUND",    (0, 0), (-1, 0), colors.HexColor("#334155")),
                ("TEXTCOLOR",     (0, 0), (-1, 0), BLANCO),
                ("ALIGN",         (0, 0), (-1, -1), "CENTER"),
                ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
                ("GRID",          (0, 0), (-1, -1), 0.3, GRIS_BRD2),
                ("TOPPADDING",    (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ("LEFTPADDING",   (0, 0), (-1, -1), 5),
                ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
                ("ROWBACKGROUND", (0, 1), (-1, -1), [BLANCO, GRIS_CLR]),
                ("BACKGROUND",    (3, 1), (3, -1), VERDE_BG),
            ]))
            bloque.append(t_per)
            bloque.append(Spacer(1, 0.3*cm))
            story.append(KeepTogether(bloque))

    # ════════════════════════════════════════════════════════════════════════
    # BUILD
    # ════════════════════════════════════════════════════════════════════════
    footer_fn = lambda canvas, doc: _pdf_footer(canvas, doc, fecha_gen, [])
    doc.build(story, onFirstPage=footer_fn, onLaterPages=footer_fn)

    buf.seek(0)
    filename = f"reporte_vacaciones_{hoy.isoformat()}.pdf"
    return StreamingResponse(
        buf, media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
