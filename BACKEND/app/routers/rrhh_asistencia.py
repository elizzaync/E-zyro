"""
HU-30 Fase 3 — Asistencia: Motor de Cálculo + Advertencias + Detalle Diario + Reportes

Endpoints:
  GET  /rrhh/asistencia/resumen                    resumen semanal por empleado (paginado)
  GET  /rrhh/asistencia/diario                     vista diaria: todos los empleados para una fecha
  GET  /rrhh/asistencia/{empleado_id}/detalle       detalle diario de registros de un empleado
  POST /rrhh/asistencia/{empleado_id}/advertencia   emite memorándum de advertencia
  GET  /rrhh/asistencia/reportes/global             reporte global todos empleados (xlsx/pdf)
  GET  /rrhh/asistencia/reportes/semanal            exporta reporte semanal (xlsx/pdf)
  GET  /rrhh/asistencia/reportes/mensual            exporta reporte mensual
  GET  /rrhh/asistencia/reportes/tardanzas          exporta incidencias de tardanzas/faltas
  GET  /rrhh/asistencia/reportes/individual         exporta historial de un empleado
  GET  /rrhh/asistencia/reportes/horas-extra        exporta empleados con >48h semanales
"""
from __future__ import annotations

import io
import re as _re
import uuid as _uuid
from datetime import date, datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token
from app.core.permisos import exigir_no_tecnico
from app.models.registro_asistencia import RegistroAsistencia
from app.models.geolocalizacion_asistencia import GeolocalizacionAsistencia
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.documento_laboral import DocumentoLaboral
from app.models.empleado import Empleado
from app.models.usuario import Usuario
from app.models.area import Area

router = APIRouter(tags=["RRHH · Asistencia"])

META_HORAS_DIA   = 8.0
META_HORAS_SEM   = 48.0
MAX_ADVERTENCIAS = 3
TIPO_MEMO        = "memorandum"
NOMBRE_MEMO      = "Memorándum de Advertencia por Faltas/Tardanzas"

# ── UUID/Área helpers ─────────────────────────────────────────────────────────
_UUID_RE = _re.compile(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    _re.IGNORECASE
)

def _area_cache(db: Session, empresa_id: str) -> dict:
    """Carga todas las áreas de la empresa: {id → nombre}."""
    return {a.id: a.nombre for a in db.query(Area).filter(Area.empresa_id == empresa_id).all()}

def _resolve_area(val, cache: dict) -> str:
    """Resuelve emp.area: si es UUID lo convierte al nombre real, si es texto lo devuelve tal cual."""
    if not val:
        return ""
    s = str(val).strip()
    return cache.get(s, "") if _UUID_RE.match(s) else s

# Hora tolerada de entrada (tardanza = después de las 8:00 + 10 min)
_HORA_ENTRADA = 8   # 08:00
_MIN_TOLERANCIA = 10


# ── Helpers de período ────────────────────────────────────────────────────────

def _lunes_semana(ref: date) -> date:
    return ref - timedelta(days=ref.weekday())

def _sabado_semana(ref: date) -> date:
    return _lunes_semana(ref) + timedelta(days=5)

def _dias_laborables(inicio: date, fin: date) -> list[date]:
    dias, cur = [], inicio
    while cur <= fin:
        if cur.weekday() < 6:
            dias.append(cur)
        cur += timedelta(days=1)
    return dias

_DIAS_ES = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]


# ── Helpers de cálculo ────────────────────────────────────────────────────────

def _horas_dia(registros_dia: list) -> float:
    entrada  = next((r.fecha_hora for r in registros_dia if r.tipo == "entrada"),          None)
    salida   = next((r.fecha_hora for r in registros_dia if r.tipo == "salida"),           None)
    ini_alm  = next((r.fecha_hora for r in registros_dia if r.tipo == "entrada_almuerzo"), None)
    fin_alm  = next((r.fecha_hora for r in registros_dia if r.tipo == "salida_almuerzo"),  None)

    if not entrada or not salida:
        return 0.0

    horas = (salida - entrada).total_seconds() / 3600.0
    if ini_alm and fin_alm and fin_alm > ini_alm:
        horas -= (fin_alm - ini_alm).total_seconds() / 3600.0

    return max(0.0, horas)


def _estado_dia(registros_dia: list, horas: float, es_dia_laborable: bool) -> str:
    if not es_dia_laborable:
        return "—"
    entrada = next((r.fecha_hora for r in registros_dia if r.tipo == "entrada"), None)
    salida  = next((r.fecha_hora for r in registros_dia if r.tipo == "salida"),  None)

    if not entrada:
        return "Falta"

    # Tardanza: entrada después de HH:MM + tolerancia
    hora_limite = entrada.replace(
        hour=_HORA_ENTRADA, minute=_MIN_TOLERANCIA, second=0, microsecond=0)
    if entrada > hora_limite:
        return "Tardanza"

    if not salida:
        return "Incompleto"

    if horas >= META_HORAS_DIA - 0.5:  # margen de 30 min
        return "Al día"

    return "Incompleto"


def _contar_advertencias(db: Session, empleado_id: str, empresa_id: str) -> int:
    return (
        db.query(DocumentoLaboral)
        .filter(
            DocumentoLaboral.empleado_id == empleado_id,
            DocumentoLaboral.empresa_id  == empresa_id,
            DocumentoLaboral.tipo        == TIPO_MEMO,
        )
        .count()
    )


# ── 1. GET /rrhh/asistencia/resumen ──────────────────────────────────────────

@router.get("/rrhh/asistencia/resumen")
def resumen_asistencia(
    fecha_inicio: Optional[date] = Query(None),
    fecha_fin:    Optional[date] = Query(None),
    page:         int            = Query(1,  ge=1),
    limit:        int            = Query(10, ge=1, le=100),
    db:           Session        = Depends(get_db),
    payload:      dict           = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    hoy    = date.today()
    inicio = fecha_inicio or _lunes_semana(hoy)
    fin    = fecha_fin    or _sabado_semana(hoy)

    if fin < inicio:
        raise HTTPException(400, "fecha_fin debe ser >= fecha_inicio")

    dias_lab     = _dias_laborables(inicio, fin)
    dias_lab_set = set(dias_lab)
    meta_horas   = len(dias_lab) * META_HORAS_DIA

    empleados_q = (
        db.query(Empleado, Usuario)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
    )
    total_empleados = empleados_q.count()

    empleados = (
        empleados_q
        .order_by(Usuario.nombre, Usuario.apellido)
        .all()
    )

    inicio_dt = datetime(inicio.year, inicio.month, inicio.day, 0, 0, 0)
    fin_dt    = datetime(fin.year,    fin.month,    fin.day,    23, 59, 59)

    todos_registros = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id == empresa_id,
            RegistroAsistencia.fecha_hora >= inicio_dt,
            RegistroAsistencia.fecha_hora <= fin_dt,
        )
        .all()
    )

    todas_solicitudes = (
        db.query(SolicitudLaboral)
        .filter(
            SolicitudLaboral.empresa_id  == empresa_id,
            SolicitudLaboral.estado      == "aprobada",
            SolicitudLaboral.fecha_inicio <= fin,
            SolicitudLaboral.fecha_fin   >= inicio,
        )
        .all()
    )

    regs_por_emp:  dict[str, list] = {}
    for reg in todos_registros:
        regs_por_emp.setdefault(reg.empleado_id, []).append(reg)

    solis_por_emp: dict[str, list] = {}
    for sol in todas_solicitudes:
        solis_por_emp.setdefault(sol.empleado_id, []).append(sol)

    area_nombres = _area_cache(db, empresa_id)
    resultado = []

    for emp, usr in empleados:
        regs  = regs_por_emp.get(emp.id,  [])
        solis = solis_por_emp.get(emp.id, [])

        dias_justificados: set[date] = set()
        for sol in solis:
            cur = max(sol.fecha_inicio, inicio)
            end = min(sol.fecha_fin,    fin)
            while cur <= end:
                if cur in dias_lab_set:
                    dias_justificados.add(cur)
                cur += timedelta(days=1)

        horas_reales = 0.0
        for dia in dias_lab:
            if dia not in dias_justificados:
                regs_dia = [r for r in regs if r.fecha_hora.date() == dia]
                horas_reales += _horas_dia(regs_dia)

        horas_justificadas = len(dias_justificados) * META_HORAS_DIA
        horas_total        = horas_reales + horas_justificadas
        horas_faltantes    = max(0.0, meta_horas - horas_total)
        porcentaje         = round((horas_total / meta_horas * 100) if meta_horas > 0 else 0.0, 1)

        advertencias = _contar_advertencias(db, emp.id, empresa_id)

        nombre    = f"{usr.nombre} {usr.apellido}".strip()
        iniciales = (
            (usr.nombre[0]   if usr.nombre   else "") +
            (usr.apellido[0] if usr.apellido else "")
        ).upper() or "?"

        resultado.append({
            "id":                 emp.id,
            "nombreCompleto":     nombre,
            "cargo":              emp.cargo,
            "area":               _resolve_area(emp.area, area_nombres),
            "iniciales":          iniciales,
            "fotoUrl":            usr.foto_url or "",
            "tipo_contrato":      emp.tipo,
            "codigo":             emp.codigo,
            "fecha_ingreso":      emp.fecha_ingreso.isoformat() if emp.fecha_ingreso else None,
            "horas_reales":       round(horas_reales,       2),
            "horas_justificadas": round(horas_justificadas, 2),
            "horas_total":        round(horas_total,        2),
            "horas_faltantes":    round(horas_faltantes,    2),
            "meta_horas":         meta_horas,
            "porcentaje":         porcentaje,
            "advertencias":       advertencias,
        })

    resultado.sort(key=lambda e: e["horas_faltantes"], reverse=True)

    # Paginación en memoria sobre el resultado ya ordenado
    total = len(resultado)
    offset = (page - 1) * limit
    pagina = resultado[offset: offset + limit]

    return {
        "periodo": {
            "fecha_inicio": inicio.isoformat(),
            "fecha_fin":    fin.isoformat(),
            "meta_horas":   meta_horas,
        },
        "empleados":     pagina,
        "total":         total,
        "page":          page,
        "limit":         limit,
        "total_paginas": max(1, -(-total // limit)),
    }


# ── 1b. GET /rrhh/asistencia/diario ─────────────────────────────────────────
# NOTA: este endpoint DEBE definirse ANTES de /{empleado_id}/detalle para que
#       FastAPI no interprete "diario" como un empleado_id.

@router.get("/rrhh/asistencia/diario")
def asistencia_diaria(
    fecha:   date = Query(...),
    page:    int  = Query(1,  ge=1),
    limit:   int  = Query(10, ge=1, le=100),
    db:      Session = Depends(get_db),
    payload: dict    = Depends(verificar_token),
):
    """Vista diaria: todos los empleados activos para la fecha indicada."""
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    fecha_dt_ini = datetime(fecha.year, fecha.month, fecha.day, 0,  0,  0)
    fecha_dt_fin = datetime(fecha.year, fecha.month, fecha.day, 23, 59, 59)

    empleados_q = (
        db.query(Empleado, Usuario)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
        .order_by(Usuario.nombre, Usuario.apellido)
        .all()
    )
    total = len(empleados_q)
    area_nombres = _area_cache(db, empresa_id)

    registros = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id == empresa_id,
            RegistroAsistencia.fecha_hora >= fecha_dt_ini,
            RegistroAsistencia.fecha_hora <= fecha_dt_fin,
        )
        .all()
    )

    reg_ids = [r.id for r in registros]
    geos: dict[str, GeolocalizacionAsistencia] = {}
    if reg_ids:
        for g in db.query(GeolocalizacionAsistencia).filter(
            GeolocalizacionAsistencia.registro_id.in_(reg_ids)
        ).all():
            geos[g.registro_id] = g

    regs_por_emp: dict[str, list] = {}
    for r in registros:
        regs_por_emp.setdefault(r.empleado_id, []).append(r)

    es_lab = fecha.weekday() < 6  # Lun-Sáb

    def _geo(reg):
        if not reg:
            return None
        g = geos.get(reg.id)
        if not g:
            return None
        return {"lat": float(g.latitud), "lng": float(g.longitud),
                "precision": float(g.precision_m) if g.precision_m else None}

    def _lat(reg):
        g = geos.get(reg.id) if reg else None
        return float(g.latitud) if g else None

    def _lng(reg):
        g = geos.get(reg.id) if reg else None
        return float(g.longitud) if g else None

    filas = []
    for emp, usr in empleados_q:
        regs = regs_por_emp.get(emp.id, [])

        entrada  = next((r for r in regs if r.tipo == "entrada"),          None)
        salida   = next((r for r in regs if r.tipo == "salida"),           None)
        ini_alm  = next((r for r in regs if r.tipo == "entrada_almuerzo"), None)
        fin_alm  = next((r for r in regs if r.tipo == "salida_almuerzo"),  None)

        horas  = _horas_dia(regs)
        estado = _estado_dia(regs, horas, es_lab)

        nombre    = f"{usr.nombre} {usr.apellido}".strip()
        iniciales = (
            (usr.nombre[0]   if usr.nombre   else "") +
            (usr.apellido[0] if usr.apellido else "")
        ).upper() or "?"

        filas.append({
            "empleado_id":     emp.id,
            "nombreCompleto":  nombre,
            "cargo":           emp.cargo or "",
            "area":            _resolve_area(emp.area, area_nombres),
            "iniciales":       iniciales,
            "fotoUrl":         usr.foto_url or "",
            "hora_ingreso":    entrada.fecha_hora.strftime("%H:%M") if entrada  else None,
            "hora_salida":     salida.fecha_hora.strftime("%H:%M")  if salida   else None,
            "almuerzo_inicio": ini_alm.fecha_hora.strftime("%H:%M") if ini_alm  else None,
            "almuerzo_fin":    fin_alm.fecha_hora.strftime("%H:%M") if fin_alm  else None,
            "horas_trabajadas": round(horas, 2),
            "lat_ingreso":     _lat(entrada),
            "lng_ingreso":     _lng(entrada),
            "lat_salida":      _lat(salida),
            "lng_salida":      _lng(salida),
            "geo_ingreso":     _geo(entrada),
            "geo_salida":      _geo(salida),
            "estado":          estado,
        })

    offset = (page - 1) * limit
    pagina = filas[offset: offset + limit]

    return {
        "fecha":         fecha.isoformat(),
        "empleados":     pagina,
        "total":         total,
        "page":          page,
        "limit":         limit,
        "total_paginas": max(1, -(-total // limit)),
    }


# ── 2. GET /rrhh/asistencia/{empleado_id}/detalle ────────────────────────────

@router.get("/rrhh/asistencia/{empleado_id}/detalle")
def detalle_diario(
    empleado_id: str,
    fecha_inicio: Optional[date] = Query(None),
    fecha_fin:    Optional[date] = Query(None),
    page:         int            = Query(1,  ge=1),
    limit:        int            = Query(10, ge=1, le=100),
    db:           Session        = Depends(get_db),
    payload:      dict           = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(404, "Empleado no encontrado")

    hoy    = date.today()
    inicio = fecha_inicio or _lunes_semana(hoy)
    fin    = fecha_fin    or _sabado_semana(hoy)

    if fin < inicio:
        raise HTTPException(400, "fecha_fin debe ser >= fecha_inicio")

    dias_lab = _dias_laborables(inicio, fin)

    inicio_dt = datetime(inicio.year, inicio.month, inicio.day, 0, 0, 0)
    fin_dt    = datetime(fin.year,    fin.month,    fin.day,    23, 59, 59)

    registros = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id  == empresa_id,
            RegistroAsistencia.empleado_id == empleado_id,
            RegistroAsistencia.fecha_hora  >= inicio_dt,
            RegistroAsistencia.fecha_hora  <= fin_dt,
        )
        .all()
    )

    # Cargar geolocalizaciones
    reg_ids = [r.id for r in registros]
    geos: dict[str, GeolocalizacionAsistencia] = {}
    if reg_ids:
        for g in db.query(GeolocalizacionAsistencia).filter(
            GeolocalizacionAsistencia.registro_id.in_(reg_ids)
        ).all():
            geos[g.registro_id] = g

    # Agregar por día
    regs_por_dia: dict[date, list] = {}
    for r in registros:
        d = r.fecha_hora.date()
        regs_por_dia.setdefault(d, []).append(r)

    filas = []
    for dia in sorted(set(dias_lab) | set(regs_por_dia.keys()), reverse=True):
        regs_dia = regs_por_dia.get(dia, [])
        es_lab   = dia in set(dias_lab)

        entrada   = next((r for r in regs_dia if r.tipo == "entrada"),          None)
        salida    = next((r for r in regs_dia if r.tipo == "salida"),           None)
        ini_alm   = next((r for r in regs_dia if r.tipo == "entrada_almuerzo"), None)
        fin_alm   = next((r for r in regs_dia if r.tipo == "salida_almuerzo"),  None)

        horas = _horas_dia(regs_dia)
        estado = _estado_dia(regs_dia, horas, es_lab)

        def _geo_dict(reg):
            if not reg:
                return None
            g = geos.get(reg.id)
            if not g:
                return None
            return {
                "lat":      float(g.latitud),
                "lng":      float(g.longitud),
                "precision": float(g.precision_m) if g.precision_m else None,
            }

        def _fmt_time(dt):
            return dt.strftime("%H:%M") if dt else None

        dur_alm = None
        if ini_alm and fin_alm and fin_alm > ini_alm:
            mins = int((fin_alm - ini_alm).total_seconds() / 60)
            dur_alm = f"{mins} min"

        filas.append({
            "fecha":          dia.isoformat(),
            "dia_nombre":     _DIAS_ES[dia.weekday()],
            "hora_ingreso":   _fmt_time(entrada.fecha_hora  if entrada  else None),
            "hora_salida":    _fmt_time(salida.fecha_hora   if salida   else None),
            "almuerzo_inicio":_fmt_time(ini_alm.fecha_hora  if ini_alm  else None),
            "almuerzo_fin":   _fmt_time(fin_alm.fecha_hora  if fin_alm  else None),
            "almuerzo_dur":   dur_alm,
            "horas_trabajadas": round(horas, 2),
            "estado":          estado,
            "geo_ingreso":     _geo_dict(entrada),
            "geo_salida":      _geo_dict(salida),
        })

    total = len(filas)
    offset = (page - 1) * limit
    pagina = filas[offset: offset + limit]

    return {
        "empleado_id": empleado_id,
        "periodo": {"fecha_inicio": inicio.isoformat(), "fecha_fin": fin.isoformat()},
        "dias": pagina,
        "total": total,
        "page": page,
        "limit": limit,
        "total_paginas": max(1, -(-total // limit)),
    }


# ── 3. POST /rrhh/asistencia/{empleado_id}/advertencia ───────────────────────

@router.post("/rrhh/asistencia/{empleado_id}/advertencia", status_code=201)
def emitir_advertencia(
    empleado_id: str,
    db:      Session = Depends(get_db),
    payload: dict    = Depends(verificar_token),
):
    exigir_no_tecnico(payload, "Solo personal de RRHH puede emitir advertencias")
    empresa_id = payload["empresa_id"]

    emp = (
        db.query(Empleado)
        .filter(
            Empleado.id         == empleado_id,
            Empleado.empresa_id == empresa_id,
            Empleado.activo     == True,
        )
        .first()
    )
    if not emp:
        raise HTTPException(404, "Empleado no encontrado")

    n = _contar_advertencias(db, emp.id, empresa_id)

    if n >= MAX_ADVERTENCIAS:
        raise HTTPException(
            400,
            "Límite legal de advertencias alcanzado (Falta grave). "
            "El empleado ya tiene 3 memorándums emitidos.",
        )

    memo = DocumentoLaboral(
        id                   = str(_uuid.uuid4()),
        empleado_id          = emp.id,
        empresa_id           = empresa_id,
        tipo                 = TIPO_MEMO,
        nombre               = NOMBRE_MEMO,
        url_archivo          = None,
        public_id_cloudinary = None,
        fecha_emision        = date.today(),
        requiere_firma       = False,
    )
    db.add(memo)
    db.commit()
    db.refresh(memo)

    nueva_cuenta = n + 1
    return {
        "id":                    memo.id,
        "mensaje":               f"Advertencia N°{nueva_cuenta} registrada correctamente.",
        "numero_advertencia":    nueva_cuenta,
        "advertencias_restantes": MAX_ADVERTENCIAS - nueva_cuenta,
    }


# ══════════════════════════════════════════════════════════════════════════════
# REPORTES DE ASISTENCIA
# ══════════════════════════════════════════════════════════════════════════════

def _build_resumen_full(db: Session, empresa_id: str, inicio: date, fin: date):
    """Construye todos los datos del resumen para reportes (sin paginar)."""
    dias_lab     = _dias_laborables(inicio, fin)
    dias_lab_set = set(dias_lab)
    meta_horas   = len(dias_lab) * META_HORAS_DIA

    empleados = (
        db.query(Empleado, Usuario)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
        .order_by(Usuario.nombre, Usuario.apellido)
        .all()
    )

    inicio_dt = datetime(inicio.year, inicio.month, inicio.day, 0, 0, 0)
    fin_dt    = datetime(fin.year,    fin.month,    fin.day,    23, 59, 59)

    todos_registros = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id == empresa_id,
            RegistroAsistencia.fecha_hora >= inicio_dt,
            RegistroAsistencia.fecha_hora <= fin_dt,
        )
        .all()
    )

    todas_solicitudes = (
        db.query(SolicitudLaboral)
        .filter(
            SolicitudLaboral.empresa_id  == empresa_id,
            SolicitudLaboral.estado      == "aprobada",
            SolicitudLaboral.fecha_inicio <= fin,
            SolicitudLaboral.fecha_fin   >= inicio,
        )
        .all()
    )

    regs_por_emp:  dict[str, list] = {}
    for r in todos_registros:
        regs_por_emp.setdefault(r.empleado_id, []).append(r)

    solis_por_emp: dict[str, list] = {}
    for s in todas_solicitudes:
        solis_por_emp.setdefault(s.empleado_id, []).append(s)

    area_nombres = _area_cache(db, empresa_id)
    filas = []
    for emp, usr in empleados:
        regs  = regs_por_emp.get(emp.id,  [])
        solis = solis_por_emp.get(emp.id, [])

        dias_justificados: set[date] = set()
        for sol in solis:
            cur = max(sol.fecha_inicio, inicio)
            end = min(sol.fecha_fin,    fin)
            while cur <= end:
                if cur in dias_lab_set:
                    dias_justificados.add(cur)
                cur += timedelta(days=1)

        horas_reales = 0.0
        faltas = tardanzas = 0
        for dia in dias_lab:
            regs_dia = [r for r in regs if r.fecha_hora.date() == dia]
            if dia not in dias_justificados:
                h = _horas_dia(regs_dia)
                horas_reales += h
                estado = _estado_dia(regs_dia, h, True)
                if estado == "Falta":
                    faltas += 1
                elif estado == "Tardanza":
                    tardanzas += 1

        horas_justificadas = len(dias_justificados) * META_HORAS_DIA
        horas_total        = horas_reales + horas_justificadas
        horas_faltantes    = max(0.0, meta_horas - horas_total)
        horas_extra        = max(0.0, horas_total - META_HORAS_SEM)
        porcentaje         = round((horas_total / meta_horas * 100) if meta_horas > 0 else 0.0, 1)

        filas.append({
            "nombre":             f"{usr.nombre} {usr.apellido}".strip(),
            "cargo":              emp.cargo or "",
            "area":               _resolve_area(emp.area, area_nombres),
            "horas_reales":       round(horas_reales, 2),
            "horas_justificadas": round(horas_justificadas, 2),
            "horas_total":        round(horas_total, 2),
            "horas_faltantes":    round(horas_faltantes, 2),
            "horas_extra":        round(horas_extra, 2),
            "meta_horas":         meta_horas,
            "porcentaje":         porcentaje,
            "faltas":             faltas,
            "tardanzas":          tardanzas,
        })

    return filas, meta_horas


def _xlsx_stream(titulo: str, encabezados: list[str], filas: list[list]) -> io.BytesIO:
    """Genera un XLSX en memoria con formato básico."""
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = titulo[:31]

    # Título
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=len(encabezados))
    cell_titulo = ws.cell(row=1, column=1, value=titulo)
    cell_titulo.font      = Font(bold=True, size=13, color="FFFFFF")
    cell_titulo.fill      = PatternFill("solid", fgColor="16A34A")
    cell_titulo.alignment = Alignment(horizontal="center")

    # Encabezados
    header_fill = PatternFill("solid", fgColor="BBF7D0")
    for col, h in enumerate(encabezados, start=1):
        c = ws.cell(row=2, column=col, value=h)
        c.font      = Font(bold=True)
        c.fill      = header_fill
        c.alignment = Alignment(horizontal="center")

    # Datos
    for row_i, fila in enumerate(filas, start=3):
        for col_i, val in enumerate(fila, start=1):
            ws.cell(row=row_i, column=col_i, value=val)

    # Auto-ancho de columnas
    for col_i, h in enumerate(encabezados, start=1):
        max_len = max(
            len(str(h)),
            max((len(str(f[col_i - 1])) for f in filas if f[col_i - 1] is not None), default=0),
        )
        ws.column_dimensions[
            openpyxl.utils.get_column_letter(col_i)
        ].width = min(max_len + 4, 50)

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return buf


def _pdf_stream(titulo: str, encabezados: list[str], filas: list[list],
                subtitulo: str = "") -> io.BytesIO:
    """Genera un PDF en memoria usando reportlab."""
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib import colors
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.lib.units import cm

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=landscape(A4),
                            leftMargin=1.5*cm, rightMargin=1.5*cm,
                            topMargin=1.5*cm, bottomMargin=1.5*cm)

    styles = getSampleStyleSheet()
    story = [
        Paragraph(titulo,    styles["Title"]),
        Paragraph(subtitulo, styles["Normal"]) if subtitulo else Spacer(1, 0),
        Spacer(1, 0.4*cm),
    ]

    data = [encabezados] + [[str(v) if v is not None else "" for v in fila] for fila in filas]
    n_cols = len(encabezados)
    col_width = (doc.width) / n_cols

    t = Table(data, colWidths=[col_width] * n_cols, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND",   (0, 0), (-1, 0), colors.HexColor("#16A34A")),
        ("TEXTCOLOR",    (0, 0), (-1, 0), colors.white),
        ("FONTNAME",     (0, 0), (-1, 0), "Helvetica-Bold"),
        ("ALIGN",        (0, 0), (-1, -1), "CENTER"),
        ("VALIGN",       (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE",     (0, 0), (-1, -1), 8),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F0FDF4")]),
        ("GRID",         (0, 0), (-1, -1), 0.5, colors.HexColor("#D1FAE5")),
        ("TOPPADDING",   (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 4),
    ]))
    story.append(t)

    doc.build(story)
    buf.seek(0)
    return buf


def _export_response(buf: io.BytesIO, fmt: str, filename: str):
    if fmt == "pdf":
        return StreamingResponse(
            buf,
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{filename}.pdf"'},
        )
    return StreamingResponse(
        buf,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}.xlsx"'},
    )


# ── Reporte Global (todos los empleados, rango libre) ────────────────────────

@router.get("/rrhh/asistencia/reportes/global")
def reporte_global(
    fecha_inicio: date = Query(...),
    fecha_fin:    date = Query(...),
    fmt:          str  = Query("xlsx", regex="^(xlsx|pdf)$"),
    db:           Session = Depends(get_db),
    payload:      dict    = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    if fecha_fin < fecha_inicio:
        raise HTTPException(400, "fecha_fin debe ser >= fecha_inicio")

    filas, meta = _build_resumen_full(db, empresa_id, fecha_inicio, fecha_fin)
    titulo    = f"Reporte Global — {fecha_inicio.strftime('%d/%m/%Y')} al {fecha_fin.strftime('%d/%m/%Y')}"
    subtitulo = f"Meta: {meta:.0f} horas | Total empleados: {len(filas)}"
    encabezados = ["Empleado", "Cargo", "Área",
                   "H. Reales", "H. Justificadas", "H. Total",
                   "H. Faltantes", "% Cumpl.", "Faltas", "Tardanzas",
                   "Prom. Diario (h)"]
    dias_lab_count = len(_dias_laborables(fecha_inicio, fecha_fin)) or 1
    datos = [
        [r["nombre"], r["cargo"], r["area"],
         r["horas_reales"], r["horas_justificadas"], r["horas_total"],
         r["horas_faltantes"], f"{r['porcentaje']}%", r["faltas"], r["tardanzas"],
         round(r["horas_total"] / dias_lab_count, 2)]
        for r in filas
    ]

    buf = _xlsx_stream(titulo, encabezados, datos) if fmt == "xlsx" else \
          _pdf_stream(titulo, encabezados, datos, subtitulo)
    return _export_response(buf, fmt, f"reporte_global_{fecha_inicio.isoformat()}")


# ── Reporte Semanal ───────────────────────────────────────────────────────────

@router.get("/rrhh/asistencia/reportes/semanal")
def reporte_semanal(
    fecha_inicio: Optional[date] = Query(None),
    fecha_fin:    Optional[date] = Query(None),
    fmt:          str            = Query("xlsx", regex="^(xlsx|pdf)$"),
    db:           Session        = Depends(get_db),
    payload:      dict           = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    hoy    = date.today()
    inicio = fecha_inicio or _lunes_semana(hoy)
    fin    = fecha_fin    or _sabado_semana(hoy)

    filas, meta = _build_resumen_full(db, empresa_id, inicio, fin)
    titulo    = f"Asistencia Semanal — {inicio.strftime('%d/%m/%Y')} al {fin.strftime('%d/%m/%Y')}"
    subtitulo = f"Meta: {meta} horas"
    encabezados = ["Empleado", "Cargo", "Área", "H. Reales", "H. Justificadas",
                   "H. Total", "H. Faltantes", "% Cumplimiento", "Faltas", "Tardanzas"]
    datos = [
        [r["nombre"], r["cargo"], r["area"],
         r["horas_reales"], r["horas_justificadas"], r["horas_total"],
         r["horas_faltantes"], f"{r['porcentaje']}%", r["faltas"], r["tardanzas"]]
        for r in filas
    ]

    if fmt == "xlsx":
        buf = _xlsx_stream(titulo, encabezados, datos)
    else:
        buf = _pdf_stream(titulo, encabezados, datos, subtitulo)

    return _export_response(buf, fmt, f"asistencia_semanal_{inicio.isoformat()}")


# ── Reporte Mensual ───────────────────────────────────────────────────────────

@router.get("/rrhh/asistencia/reportes/mensual")
def reporte_mensual(
    anio: int = Query(..., ge=2020, le=2100),
    mes:  int = Query(..., ge=1, le=12),
    fmt:  str = Query("xlsx", regex="^(xlsx|pdf)$"),
    db:   Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    from calendar import monthrange
    inicio = date(anio, mes, 1)
    fin    = date(anio, mes, monthrange(anio, mes)[1])

    filas, meta = _build_resumen_full(db, empresa_id, inicio, fin)
    meses_es = ["", "Enero","Febrero","Marzo","Abril","Mayo","Junio",
                "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
    titulo = f"Asistencia Mensual — {meses_es[mes]} {anio}"
    encabezados = ["Empleado", "Cargo", "Área", "H. Reales", "H. Justificadas",
                   "H. Total", "H. Faltantes", "% Cumplimiento", "Faltas", "Tardanzas"]
    datos = [
        [r["nombre"], r["cargo"], r["area"],
         r["horas_reales"], r["horas_justificadas"], r["horas_total"],
         r["horas_faltantes"], f"{r['porcentaje']}%", r["faltas"], r["tardanzas"]]
        for r in filas
    ]

    if fmt == "xlsx":
        buf = _xlsx_stream(titulo, encabezados, datos)
    else:
        buf = _pdf_stream(titulo, encabezados, datos)

    return _export_response(buf, fmt, f"asistencia_mensual_{anio}_{mes:02d}")


# ── Reporte Tardanzas/Faltas ──────────────────────────────────────────────────

@router.get("/rrhh/asistencia/reportes/tardanzas")
def reporte_tardanzas(
    fecha_inicio: date = Query(...),
    fecha_fin:    date = Query(...),
    fmt:          str  = Query("xlsx", regex="^(xlsx|pdf)$"),
    db:           Session = Depends(get_db),
    payload:      dict    = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    filas, _ = _build_resumen_full(db, empresa_id, fecha_inicio, fecha_fin)
    titulo = f"Tardanzas y Faltas — {fecha_inicio.strftime('%d/%m/%Y')} al {fecha_fin.strftime('%d/%m/%Y')}"
    incidencias = [r for r in filas if r["faltas"] > 0 or r["tardanzas"] > 0]
    encabezados = ["Empleado", "Cargo", "Área", "Faltas", "Tardanzas", "H. Faltantes"]
    datos = [
        [r["nombre"], r["cargo"], r["area"], r["faltas"], r["tardanzas"], r["horas_faltantes"]]
        for r in sorted(incidencias, key=lambda x: -(x["faltas"] + x["tardanzas"]))
    ]

    if fmt == "xlsx":
        buf = _xlsx_stream(titulo, encabezados, datos)
    else:
        buf = _pdf_stream(titulo, encabezados, datos)

    return _export_response(buf, fmt, f"tardanzas_faltas_{fecha_inicio.isoformat()}")


# ── Reporte Individual ────────────────────────────────────────────────────────

@router.get("/rrhh/asistencia/reportes/individual")
def reporte_individual(
    empleado_id:  str  = Query(...),
    fecha_inicio: date = Query(...),
    fecha_fin:    date = Query(...),
    fmt:          str  = Query("xlsx", regex="^(xlsx|pdf)$"),
    db:           Session = Depends(get_db),
    payload:      dict    = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(404, "Empleado no encontrado")

    usr = db.query(Usuario).filter(Usuario.id == emp.usuario_id).first()
    nombre = f"{usr.nombre} {usr.apellido}".strip() if usr else "Empleado"

    dias_lab     = _dias_laborables(fecha_inicio, fecha_fin)
    inicio_dt    = datetime(fecha_inicio.year, fecha_inicio.month, fecha_inicio.day, 0, 0, 0)
    fin_dt       = datetime(fecha_fin.year,    fecha_fin.month,    fecha_fin.day,    23, 59, 59)

    registros = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id  == empresa_id,
            RegistroAsistencia.empleado_id == empleado_id,
            RegistroAsistencia.fecha_hora  >= inicio_dt,
            RegistroAsistencia.fecha_hora  <= fin_dt,
        )
        .all()
    )

    regs_por_dia: dict[date, list] = {}
    for r in registros:
        regs_por_dia.setdefault(r.fecha_hora.date(), []).append(r)

    titulo = f"Historial Asistencia — {nombre}"
    encabezados = ["Fecha", "Día", "Ingreso", "Salida", "H. Trabajo", "Estado"]
    datos = []
    for dia in sorted(dias_lab, reverse=True):
        regs_dia = regs_por_dia.get(dia, [])
        horas    = _horas_dia(regs_dia)
        estado   = _estado_dia(regs_dia, horas, True)
        entrada  = next((r.fecha_hora for r in regs_dia if r.tipo == "entrada"), None)
        salida   = next((r.fecha_hora for r in regs_dia if r.tipo == "salida"),  None)
        datos.append([
            dia.strftime("%d/%m/%Y"),
            _DIAS_ES[dia.weekday()],
            entrada.strftime("%H:%M") if entrada else "—",
            salida.strftime("%H:%M")  if salida  else "—",
            f"{horas:.1f}h",
            estado,
        ])

    if fmt == "xlsx":
        buf = _xlsx_stream(titulo, encabezados, datos)
    else:
        buf = _pdf_stream(titulo, encabezados, datos,
                          f"{fecha_inicio.strftime('%d/%m/%Y')} – {fecha_fin.strftime('%d/%m/%Y')}")

    return _export_response(buf, fmt, f"asistencia_{empleado_id[:8]}_{fecha_inicio.isoformat()}")


# ── Reporte Horas Extra ───────────────────────────────────────────────────────
# Basado en solicitudes de permanencia_extra APROBADAS con >= 1 hora (campo dias).

@router.get("/rrhh/asistencia/reportes/horas-extra")
def reporte_horas_extra(
    fecha_inicio: Optional[date] = Query(None),
    fecha_fin:    Optional[date] = Query(None),
    fmt:          str            = Query("xlsx", regex="^(xlsx|pdf)$"),
    db:           Session        = Depends(get_db),
    payload:      dict           = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    hoy    = date.today()
    inicio = fecha_inicio or _lunes_semana(hoy)
    fin    = fecha_fin    or _sabado_semana(hoy)

    rows = (
        db.query(SolicitudLaboral, Empleado, Usuario)
        .join(Empleado, SolicitudLaboral.empleado_id == Empleado.id)
        .join(Usuario,  Empleado.usuario_id == Usuario.id)
        .filter(
            SolicitudLaboral.empresa_id    == empresa_id,
            SolicitudLaboral.tipo          == "permanencia_extra",
            SolicitudLaboral.estado        == "aprobada",
            SolicitudLaboral.dias          >= 1,
            SolicitudLaboral.fecha_inicio  >= inicio,
            SolicitudLaboral.fecha_inicio  <= fin,
        )
        .order_by(SolicitudLaboral.fecha_inicio)
        .all()
    )

    titulo = f"Horas Extra Aprobadas — {inicio.strftime('%d/%m/%Y')} al {fin.strftime('%d/%m/%Y')}"
    encabezados = ["Empleado", "Cargo", "Área", "Fecha", "Horas Aprobadas", "Ref. Solicitud", "Estado"]
    datos = [
        [
            f"{usr.nombre} {usr.apellido}".strip(),
            emp.cargo or "",
            emp.area  or "",
            sol.fecha_inicio.strftime("%d/%m/%Y"),
            sol.dias,
            str(sol.id)[:8].upper(),
            sol.estado.capitalize(),
        ]
        for sol, emp, usr in rows
    ]

    subtitulo = f"Solicitudes de Permanencia Extra aprobadas del {inicio.strftime('%d/%m/%Y')} al {fin.strftime('%d/%m/%Y')}"
    if fmt == "xlsx":
        buf = _xlsx_stream(titulo, encabezados, datos)
    else:
        buf = _pdf_stream(titulo, encabezados, datos, subtitulo)

    return _export_response(buf, fmt, f"horas_extra_{inicio.isoformat()}")
