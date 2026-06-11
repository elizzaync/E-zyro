"""
HU-30 Fase 3 — Asistencia: Motor de Cálculo + Advertencias

Endpoints:
  GET  /rrhh/asistencia/resumen                    resumen semanal por empleado
  POST /rrhh/asistencia/{empleado_id}/advertencia  emite memorándum de advertencia
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date, datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token
from app.core.permisos import exigir_no_tecnico
from app.models.registro_asistencia import RegistroAsistencia
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.documento_laboral import DocumentoLaboral
from app.models.empleado import Empleado
from app.models.usuario import Usuario

router = APIRouter(tags=["RRHH · Asistencia"])

META_HORAS_DIA   = 8.0
MAX_ADVERTENCIAS = 3
TIPO_MEMO        = "memorandum"
NOMBRE_MEMO      = "Memorándum de Advertencia por Faltas/Tardanzas"


# ── Helpers de período ────────────────────────────────────────────────────────

def _lunes_semana(ref: date) -> date:
    return ref - timedelta(days=ref.weekday())


def _sabado_semana(ref: date) -> date:
    return _lunes_semana(ref) + timedelta(days=5)


def _dias_laborables(inicio: date, fin: date) -> list[date]:
    """Lunes-Sábado (weekday 0-5) entre inicio y fin, ambos inclusive."""
    dias, cur = [], inicio
    while cur <= fin:
        if cur.weekday() < 6:
            dias.append(cur)
        cur += timedelta(days=1)
    return dias


# ── Helpers de cálculo ────────────────────────────────────────────────────────

def _horas_dia(registros_dia: list) -> float:
    """
    Horas netas trabajadas en un día:
    (salida − entrada) − (salida_almuerzo − entrada_almuerzo).
    Retorna 0.0 si la entrada o salida están ausentes.
    """
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
    fecha_inicio: Optional[date] = Query(None, description="Inicio del período (default: lunes semana actual)"),
    fecha_fin:    Optional[date] = Query(None, description="Fin del período (default: sábado semana actual)"),
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

    # Empleados activos de la empresa (JOIN usuario para nombre/foto)
    empleados = (
        db.query(Empleado, Usuario)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo == True)
        .all()
    )

    # Registros de asistencia del período — una sola query para todos
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

    # Solicitudes laborales aprobadas que se solapan con el período
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

    # Índices por empleado para evitar O(n²)
    regs_por_emp:  dict[str, list] = {}
    for reg in todos_registros:
        regs_por_emp.setdefault(reg.empleado_id, []).append(reg)

    solis_por_emp: dict[str, list] = {}
    for sol in todas_solicitudes:
        solis_por_emp.setdefault(sol.empleado_id, []).append(sol)

    resultado = []

    for emp, usr in empleados:
        regs  = regs_por_emp.get(emp.id,  [])
        solis = solis_por_emp.get(emp.id, [])

        # Días laborables cubiertos por solicitud aprobada dentro del período
        dias_justificados: set[date] = set()
        for sol in solis:
            cur = max(sol.fecha_inicio, inicio)
            end = min(sol.fecha_fin,    fin)
            while cur <= end:
                if cur in dias_lab_set:
                    dias_justificados.add(cur)
                cur += timedelta(days=1)

        # Horas reales: solo en días SIN justificación (evita doble conteo)
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
            "area":               emp.area or "",
            "iniciales":          iniciales,
            "fotoUrl":            usr.foto_url or "",
            "horas_reales":       round(horas_reales,       2),
            "horas_justificadas": round(horas_justificadas, 2),
            "horas_total":        round(horas_total,        2),
            "horas_faltantes":    round(horas_faltantes,    2),
            "meta_horas":         meta_horas,
            "porcentaje":         porcentaje,
            "advertencias":       advertencias,
        })

    # Primero los que tienen más horas faltantes
    resultado.sort(key=lambda e: e["horas_faltantes"], reverse=True)

    return {
        "periodo": {
            "fecha_inicio": inicio.isoformat(),
            "fecha_fin":    fin.isoformat(),
            "meta_horas":   meta_horas,
        },
        "empleados": resultado,
    }


# ── 2. POST /rrhh/asistencia/{empleado_id}/advertencia ───────────────────────

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
