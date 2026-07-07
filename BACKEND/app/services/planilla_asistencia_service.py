"""
Resumen de asistencia por periodo para la planilla (Fase 8).

Compone la lógica de asistencia que YA existe (no la reconstruye): reutiliza
`routers.rrhh_asistencia` (turnos, feriados, permisos aprobados, horas reales
por día). Único punto de entrada: `resumen_horas_periodo` — usado por el
propio endpoint `GET /rrhh/asistencia/resumen` (Fase 0 de esta migración) y
por el motor de cálculo legal de Planilla (`planilla_calculo_service`), que
usa horas_reales/horas_faltantes/meta_horas como insumo directo de las
fórmulas. Las importaciones de los routers son perezosas para evitar ciclos
de importación al cargar el módulo.

Nota histórica: existió un `resumen_asistencia_periodo` (día/minuto,
más simple) usado por una versión anterior de `calcular_planilla` — quedó
reemplazado por `resumen_horas_periodo` cuando el motor legal pasó a calcular
el sueldo devengado proporcional a las horas reales (no por conteo de días).
"""
from __future__ import annotations

from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session


def resumen_horas_periodo(db: Session, empresa_id: str, inicio: date, fin: date) -> list[dict]:
    """Por empleado activo en [inicio, fin]: identidad + horas acumuladas del
    periodo (horas_reales, horas_justificadas, horas_total, horas_faltantes,
    horas_extra, meta_horas, etc.).

    Extraído 1:1 (Fase 0 de la migración del motor de Planilla) del bucle que
    antes vivía inline en `routers.rrhh_asistencia.resumen_asistencia` — MISMA
    lógica, MISMOS campos, sin ordenar ni paginar (eso sigue siendo
    responsabilidad de cada consumidor). Dos consumidores:
      - el propio endpoint `GET /rrhh/asistencia/resumen` (ordena + pagina).
      - el motor de cálculo de Planilla (Fase 8, usa horas_reales/horas_faltantes/
        horas_extra/meta_horas/tipo_contrato como insumo de las fórmulas legales).
    """
    from app.models.turno import Turno as _Turno, TurnoEmpleado as _TE
    from app.models.registro_asistencia import RegistroAsistencia
    from app.models.solicitud_laboral import SolicitudLaboral
    from app.models.empleado import Empleado
    from app.models.usuario import Usuario
    from app.routers.rrhh_asistencia import (
        _dias_laborables, _feriados_set, _min_entre_horas, _parse_dias_lab,
        _horas_dia, _resolve_area, _area_cache, _contar_advertencias,
        META_HORAS_DIA,
    )

    dias_lab     = _dias_laborables(inicio, fin)
    dias_lab_set = set(dias_lab)
    feriados     = _feriados_set(db, empresa_id, inicio, fin)

    # Domingos del rango (día de descanso semanal obligatorio, D.Leg. 713 Art. 3
    # y 4): _dias_laborables ya los excluye de dias_lab por construcción, así
    # que se recorren aparte para detectar asistencia marcada en domingo —
    # trabajo en el día de descanso, pagado con sobretasa (ver
    # planilla_calculo_service.calcular_boleta_empleado).
    domingos: list[date] = []
    _cur = inicio
    while _cur <= fin:
        if _cur.weekday() == 6:
            domingos.append(_cur)
        _cur += timedelta(days=1)

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

    # Asignaciones de turno vigentes en el rango
    from sqlalchemy import or_ as _or_
    asigns = (
        db.query(_TE, _Turno)
        .join(_Turno, _Turno.id == _TE.turno_id)
        .filter(
            _Turno.empresa_id == empresa_id,
            _TE.activo == True, _Turno.activo == True,
            _TE.fecha_desde <= fin,
            _or_(_TE.fecha_hasta.is_(None), _TE.fecha_hasta >= inicio),
        ).all()
    )
    asigns_por_emp: dict[str, list] = {}
    for te, turno in asigns:
        asigns_por_emp.setdefault(str(te.empleado_id), []).append((te, turno))

    def _info_turno_dia(emp_id: str, dia: date):
        """(horas_req, dias_lab_set) para el turno del empleado ese día."""
        for te, turno in asigns_por_emp.get(str(emp_id), []):
            if te.fecha_desde <= dia and (te.fecha_hasta is None or te.fecha_hasta >= dia):
                req_min = max(
                    _min_entre_horas(turno.hora_entrada, turno.hora_salida)
                    - (turno.duracion_almuerzo_minutos or 0), 0
                )
                return (
                    req_min / 60.0,
                    _parse_dias_lab(getattr(turno, "dias_laborales", None)),
                )
        return (META_HORAS_DIA, {0, 1, 2, 3, 4})   # defecto L-V, 8h

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
            if sol.tipo in ("justificacion_tardanza", "permanencia_extra"):
                continue  # solo cuentan solicitudes de ausencia/permiso para justificar días
            cur = max(sol.fecha_inicio, inicio)
            end = min(sol.fecha_fin,    fin)
            while cur <= end:
                if cur in dias_lab_set:
                    dias_justificados.add(cur)
                cur += timedelta(days=1)

        horas_reales       = 0.0
        horas_justificadas = 0.0
        meta_horas_emp     = 0.0
        dias_laborados     = 0
        horas_domingo      = 0.0

        for dia in domingos:
            regs_dia = [r for r in regs if r.fecha_hora.date() == dia]
            horas_domingo += _horas_dia(regs_dia)

        for dia in dias_lab:
            req_h, dias_turno = _info_turno_dia(emp.id, dia)

            # Solo días que el turno del empleado marca como laborables
            if dia.weekday() not in dias_turno:
                continue
            # Excluir feriados
            if dia in feriados:
                continue

            meta_horas_emp += req_h

            if dia in dias_justificados:
                horas_justificadas += req_h
            else:
                regs_dia = [r for r in regs if r.fecha_hora.date() == dia]
                h = _horas_dia(regs_dia)
                horas_reales += h
                if h > 0:
                    dias_laborados += 1

        # Horas extras aprobadas (permanencia_extra)
        perm_extra_h = float(sum(
            s.dias or 0 for s in solis if s.tipo == "permanencia_extra"
        ))
        horas_total           = horas_reales + horas_justificadas
        horas_faltantes       = max(0.0, meta_horas_emp - horas_total)
        horas_extra           = max(0.0, horas_total - meta_horas_emp)
        horas_extra_aprobadas = round(min(horas_extra, perm_extra_h), 2)
        horas_extra_no_autor  = round(max(0.0, horas_extra - horas_extra_aprobadas), 2)
        porcentaje            = round((horas_total / meta_horas_emp * 100) if meta_horas_emp > 0 else 0.0, 1)

        advertencias = _contar_advertencias(db, emp.id, empresa_id)

        nombre    = f"{usr.nombre} {usr.apellido}".strip()
        iniciales = (
            (usr.nombre[0]   if usr.nombre   else "") +
            (usr.apellido[0] if usr.apellido else "")
        ).upper() or "?"

        resultado.append({
            "id":                    emp.id,
            "nombreCompleto":        nombre,
            "cargo":                 emp.cargo,
            "area":                  _resolve_area(emp.area, area_nombres),
            "iniciales":             iniciales,
            "fotoUrl":               usr.foto_url or "",
            "tipo_contrato":         emp.tipo,
            "codigo":                emp.codigo,
            "tipo_documento":        emp.tipo_documento or "DNI",
            "numero_documento":      emp.numero_documento,
            "cuspp":                 emp.cuspp,
            "fecha_ingreso":         emp.fecha_ingreso.isoformat() if emp.fecha_ingreso else None,
            "horas_reales":          round(horas_reales,       2),
            "horas_justificadas":    round(horas_justificadas, 2),
            "horas_total":           round(horas_total,        2),
            "horas_faltantes":       round(horas_faltantes,    2),
            "horas_extra":           round(horas_extra,        2),
            "horas_extra_aprobadas": horas_extra_aprobadas,
            "horas_extra_no_autor":  horas_extra_no_autor,
            "horas_domingo":         round(horas_domingo, 2),
            "dias_laborados":        dias_laborados,
            "meta_horas":            round(meta_horas_emp, 2),
            "porcentaje":            porcentaje,
            "advertencias":          advertencias,
        })

    return resultado
