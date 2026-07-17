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

FIX 2026-07-07: falta y sobretiempo se calculan POR DÍA dentro del loop de
`dias_lab`, no por acumulación del período (D.S. 007-2002-TR: el tramo
25%/35% de hora extra aplica por JORNADA, no una sola vez al mes). Un día
corto ya NO compensa (netea) un día largo: ambos se acumulan por separado en
`horas_faltantes`/`horas_extra`. Los buckets `horas_extra_25`/`horas_extra_35`
(ya truncados a la hora completa, por día) son el insumo directo que
`planilla_calculo_service.calcular_boleta_empleado` usa para pagar el
sobretiempo — el motor YA NO deriva la hora extra de horas_reales/meta_horas.

FIX 2026-07-08 (detalle diario, modal "Ver" de Planilla): las tres pasadas
que antes existían por separado (domingos / feriados_trabajables / dias_lab)
se unificaron en UN solo loop que recorre TODOS los días del rango — sigue
produciendo EXACTAMENTE los mismos totales de antes (domingo/feriado siguen
sin tocar meta_horas/horas_faltantes/horas_extra*, días fuera del turno del
empleado siguen sin contar para nada, días justificados siguen sin generar
falta ni extra), pero de paso arma `detalle_dias` — single source of truth:
los totales son la SUMA de ese detalle, nunca un cálculo aparte. Activado
solo con `incluir_detalle_dias=True` (los dos consumidores existentes,
`/rrhh/asistencia/resumen` y `/planilla/preview`/`calcular_planilla`, NO lo
piden — no pagan el costo extra de armar el detalle día-por-día con
geolocalización de cada empleado en cada carga de la tabla).

FIX 2026-07-08 (hora extra ANCLADA al horario pactado, decisión de negocio
explícita del usuario): antes, `horas_reales` era el SPAN crudo
(salida − entrada − almuerzo) sin importar en qué momento del día ocurrió, así
que llegar 1h ANTES de la hora de entrada del turno podía contar como
sobretiempo si el total superaba las horas requeridas — igual que quedarse
1h después de la salida. Esto NO es lo que el negocio quiere: "las horas
extra son fuera de tu hora de trabajo" — específicamente, DESPUÉS de la hora
de salida pactada. Llegar temprano ya NO cuenta para nada (ni resta falta ni
suma extra); el sobretiempo ahora se calcula EXCLUSIVAMENTE como tiempo
trabajado después de `turno_hora_salida` (`_horas_dia_ancladas`). Si el
empleado no tiene un turno con horario de reloj definido (turno_hora_entrada/
salida=None — cae al default de 8h sin turno asignado), no hay ancla contra
la cual comparar y se preserva el cálculo anterior por SPAN total.
"""
from __future__ import annotations

import math
from datetime import date, datetime, time as _time, timedelta

from sqlalchemy.orm import Session


def _horas_dia_ancladas(
    regs_dia: list, dia: date,
    turno_hora_entrada: "_time | None", turno_hora_salida: "_time | None",
    duracion_almuerzo_minutos: int = 0,
) -> tuple[float, float]:
    """(horas_regulares, horas_extra_bruto) ancladas al horario PACTADO del
    turno — ver FIX 2026-07-08 en el docstring del módulo. `horas_regulares`
    es el tiempo trabajado DENTRO de [turno_hora_entrada, turno_hora_salida]
    (llegar antes no lo agranda); `horas_extra_bruto` es SOLO el tiempo
    trabajado después de `turno_hora_salida` (llegar antes nunca genera
    extra, sin importar cuánto se quede después).

    FIX 2026-07-16 (almuerzo OBLIGATORIO, decisión de negocio explícita del
    usuario): el refrigerio no es opcional — el trabajador SIEMPRE lo toma,
    marque o no su salida/entrada de almuerzo. Antes, si no marcaba esas dos
    marcaciones, `horas_regulares` no descontaba nada (asumía que trabajó
    corrido), inflando sus horas reales/extra exactamente por la duración del
    almuerzo configurada en el turno. Ahora se descuenta SIEMPRE al menos
    `duracion_almuerzo_minutos` (lo pactado); si además marcó un almuerzo real
    MÁS LARGO que eso, se descuenta el real (no se le paga el exceso de
    descanso sobre lo autorizado)."""
    entrada = next((r.fecha_hora for r in regs_dia if r.tipo == "entrada"),          None)
    salida  = next((r.fecha_hora for r in regs_dia if r.tipo == "salida"),           None)
    ini_alm = next((r.fecha_hora for r in regs_dia if r.tipo == "entrada_almuerzo"), None)
    fin_alm = next((r.fecha_hora for r in regs_dia if r.tipo == "salida_almuerzo"),  None)

    if not entrada or not salida:
        return 0.0, 0.0

    almuerzo_pactado_h = max(0, duracion_almuerzo_minutos) / 60.0

    if turno_hora_entrada is None or turno_hora_salida is None:
        # Sin turno con horario de reloj (cae al default sin turno asignado):
        # no hay ancla contra la cual comparar — se preserva el SPAN total.
        horas = (salida - entrada).total_seconds() / 3600.0
        almuerzo_real_h = 0.0
        if ini_alm and fin_alm and fin_alm > ini_alm:
            almuerzo_real_h = (fin_alm - ini_alm).total_seconds() / 3600.0
        horas -= max(almuerzo_pactado_h, almuerzo_real_h)
        return max(0.0, horas), 0.0

    turno_entrada_dt = datetime.combine(dia, turno_hora_entrada)
    turno_salida_dt  = datetime.combine(dia, turno_hora_salida)

    inicio_regular = max(entrada, turno_entrada_dt)   # llegar temprano NO cuenta
    fin_regular    = min(salida, turno_salida_dt)      # el tramo regular no pasa de la salida pactada
    horas_regulares = max(0.0, (fin_regular - inicio_regular).total_seconds() / 3600.0)

    almuerzo_real_h = 0.0
    if ini_alm and fin_alm and fin_alm > ini_alm:
        alm_ini_ov = max(ini_alm, inicio_regular)
        alm_fin_ov = min(fin_alm, fin_regular)
        if alm_fin_ov > alm_ini_ov:
            almuerzo_real_h = (alm_fin_ov - alm_ini_ov).total_seconds() / 3600.0
    horas_regulares -= max(almuerzo_pactado_h, almuerzo_real_h)
    horas_regulares = max(0.0, horas_regulares)

    horas_extra_bruto = max(0.0, (salida - turno_salida_dt).total_seconds() / 3600.0)

    return horas_regulares, horas_extra_bruto


def resumen_horas_periodo(
    db: Session, empresa_id: str, inicio: date, fin: date,
    *, incluir_detalle_dias: bool = False,
) -> list[dict]:
    """Por empleado activo en [inicio, fin]: identidad + horas acumuladas del
    periodo (horas_reales, horas_justificadas, horas_total, horas_faltantes,
    horas_extra, meta_horas, etc.). Si `incluir_detalle_dias=True`, cada fila
    también trae `detalle_dias`: una entrada por CADA día del rango con el
    desglose exacto (turno, marcaciones con geolocalización, falta/extra ya
    truncados) que arma el modal "Ver asistencia" de Planilla — construido
    por el MISMO loop que calcula los totales, nunca recalculado aparte.

    Extraído 1:1 (Fase 0 de la migración del motor de Planilla) del bucle que
    antes vivía inline en `routers.rrhh_asistencia.resumen_asistencia` — MISMA
    lógica, MISMOS campos, sin ordenar ni paginar (eso sigue siendo
    responsabilidad de cada consumidor). Consumidores:
      - el propio endpoint `GET /rrhh/asistencia/resumen` (ordena + pagina).
      - el motor de cálculo de Planilla (Fase 8, usa horas_reales/horas_faltantes/
        horas_extra/meta_horas/tipo_contrato como insumo de las fórmulas legales).
      - `GET /planilla/empleados/{id}/asistencia-detalle` (Fase 9, modal de
        verificación — el único que pasa `incluir_detalle_dias=True`).
    """
    from app.models.turno import Turno as _Turno, TurnoEmpleado as _TE
    from app.models.registro_asistencia import RegistroAsistencia
    from app.models.solicitud_laboral import SolicitudLaboral
    from app.models.empleado import Empleado
    from app.models.usuario import Usuario
    from app.routers.rrhh_asistencia import (
        _dias_laborables, _feriados_set, _min_entre_horas, _parse_dias_lab,
        _horas_dia, _resolve_area, _area_cache, _contar_advertencias,
        META_HORAS_DIA, _DIAS_ES,
    )

    dias_lab_set = set(_dias_laborables(inicio, fin))
    feriados     = _feriados_set(db, empresa_id, inicio, fin)

    # Todos los días del rango — un solo loop cubre domingos, feriados,
    # laborables y días fuera del turno del empleado (antes eran tres pasadas
    # separadas que, sumadas, ya recorrían la misma cantidad de días; unificar
    # no cuesta más). `detalle_dias` solo se ARMA si se pidió (ver abajo).
    todos_los_dias: list[date] = []
    _cur = inicio
    while _cur <= fin:
        todos_los_dias.append(_cur)
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

    # Geolocalización por marcación (tabla aparte, 1:N con RegistroAsistencia
    # vía registro_id — RegistroAsistencia NO tiene columnas lat/lng propias).
    # Solo se consulta si se pidió el detalle diario (evita el costo/JOIN extra
    # en los dos consumidores que no lo necesitan).
    geos_por_registro: dict[str, tuple[float, float]] = {}
    if incluir_detalle_dias and todos_registros:
        from app.models.geolocalizacion_asistencia import GeolocalizacionAsistencia
        reg_ids = [r.id for r in todos_registros]
        for g in db.query(GeolocalizacionAsistencia).filter(
            GeolocalizacionAsistencia.registro_id.in_(reg_ids)
        ).all():
            geos_por_registro[g.registro_id] = (float(g.latitud), float(g.longitud))

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
        """(horas_req, dias_lab_set, turno_nombre, hora_entrada, hora_salida,
        duracion_almuerzo_minutos) para el turno del empleado ese día —
        hora_entrada/hora_salida son `time` (la hora de RELOJ pactada, no una
        duración) para que el detalle diario pueda comparar "marcaste a las
        X" contra "tu turno empieza a las Y". turno_nombre/horas=None cuando
        cae al defecto (sin turno asignado)."""
        for te, turno in asigns_por_emp.get(str(emp_id), []):
            if te.fecha_desde <= dia and (te.fecha_hasta is None or te.fecha_hasta >= dia):
                almuerzo_min = turno.duracion_almuerzo_minutos or 0
                req_min = max(
                    _min_entre_horas(turno.hora_entrada, turno.hora_salida) - almuerzo_min, 0
                )
                return (
                    req_min / 60.0,
                    _parse_dias_lab(getattr(turno, "dias_laborales", None)),
                    turno.nombre, turno.hora_entrada, turno.hora_salida, almuerzo_min,
                )
        return (META_HORAS_DIA, {0, 1, 2, 3, 4}, None, None, None, 0)   # defecto L-V, 8h, sin turno

    regs_por_emp:  dict[str, list] = {}
    for reg in todos_registros:
        regs_por_emp.setdefault(reg.empleado_id, []).append(reg)

    solis_por_emp: dict[str, list] = {}
    for sol in todas_solicitudes:
        solis_por_emp.setdefault(sol.empleado_id, []).append(sol)

    area_nombres = _area_cache(db, empresa_id)
    resultado = []

    def _marcacion_punto(reg) -> dict | None:
        if reg is None:
            return None
        lat, lng = geos_por_registro.get(reg.id, (None, None))
        return {"hora": reg.fecha_hora, "lat": lat, "lng": lng}

    for emp, usr in empleados:
        regs  = regs_por_emp.get(emp.id,  [])
        solis = solis_por_emp.get(emp.id, [])

        # date -> tipo de la SolicitudLaboral que justifica ese día (última
        # que aplique si hay solapamiento — caso raro).
        dias_justificados: dict[date, str] = {}
        for sol in solis:
            if sol.tipo in ("justificacion_tardanza", "permanencia_extra"):
                continue  # solo cuentan solicitudes de ausencia/permiso para justificar días
            cur = max(sol.fecha_inicio, inicio)
            end = min(sol.fecha_fin,    fin)
            while cur <= end:
                if cur in dias_lab_set:
                    dias_justificados[cur] = sol.tipo
                cur += timedelta(days=1)

        horas_reales       = 0.0
        horas_justificadas = 0.0
        meta_horas_emp     = 0.0
        dias_laborados     = 0
        horas_domingo      = 0.0
        horas_feriado      = 0.0
        horas_faltantes    = 0.0
        # Sobretiempo (2026-07-07, FIX horas extra por día, D.S. 007-2002-TR:
        # el tramo 25%/35% aplica por JORNADA, no una sola vez al período —
        # sin netear un día corto con uno largo). `horas_extra` es el total
        # informativo sin truncar; `horas_extra_25`/`horas_extra_35` ya
        # vienen truncadas a la hora completa por día y clasificadas por
        # tramo (25% las primeras 2h de CADA día, 35% el resto de ese día).
        horas_extra        = 0.0
        horas_extra_25     = 0.0
        horas_extra_35     = 0.0

        detalle_dias: list[dict] = []

        # ── UN solo loop sobre TODOS los días del rango — mismos totales que
        # las tres pasadas separadas de antes (domingo/feriado nunca tocan
        # meta_horas/horas_faltantes/horas_extra*, días fuera de turno nunca
        # cuentan para nada), ver docstring del módulo.
        for dia in todos_los_dias:
            regs_dia = [r for r in regs if r.fecha_hora.date() == dia]
            entrada  = next((r for r in regs_dia if r.tipo == "entrada"),          None)
            salida   = next((r for r in regs_dia if r.tipo == "salida"),           None)
            ini_alm  = next((r for r in regs_dia if r.tipo == "entrada_almuerzo"), None)
            fin_alm  = next((r for r in regs_dia if r.tipo == "salida_almuerzo"),  None)
            marcacion_incompleta = entrada is not None and salida is None

            req_horas_dia = 0.0
            turno_nombre  = None
            turno_hora_entrada = None
            turno_hora_salida  = None
            tipo_dia: str
            es_justificado = False
            motivo = None
            falta_dia = 0.0
            extra_bruto_dia = 0.0
            extra_pag_dia = 0.0
            extra25_dia = 0.0
            extra35_dia = 0.0

            if dia.weekday() == 6:
                # Domingo: día de descanso semanal (D.Leg. 713 Art. 3/4). Sin
                # meta propia — lo trabajado aquí paga sobretasa 100% aparte,
                # no participa de falta/extra por tramo.
                tipo_dia = "domingo"
                h = _horas_dia(regs_dia)
                horas_domingo += h
            elif dia in feriados:
                # Feriado no laborable (D.Leg. 713 Art. 8/9) — igual que
                # domingo: sobretasa aparte, sin falta/extra por tramo. Los
                # feriados que caen en domingo ya entraron por la rama de
                # arriba (weekday()==6 se evalúa primero), evitando duplicar.
                tipo_dia = "feriado"
                h = _horas_dia(regs_dia)
                horas_feriado += h
            else:
                req_h, dias_turno, turno_nombre, turno_hora_entrada, turno_hora_salida, almuerzo_min = _info_turno_dia(emp.id, dia)
                if dia.weekday() not in dias_turno:
                    # Día fuera del turno del empleado (ej. sábado si su
                    # turno es L-V) — no cuenta para meta/falta/extra, igual
                    # que antes (el `continue` original lo excluía del todo).
                    tipo_dia = "no_laborable_turno"
                    h = _horas_dia(regs_dia)
                else:
                    meta_horas_emp += req_h
                    req_horas_dia = req_h
                    tipo_dia = "laborable"
                    if dia in dias_justificados:
                        es_justificado = True
                        motivo = dias_justificados[dia]
                        horas_justificadas += req_h
                        h = _horas_dia(regs_dia)  # informativo: no genera falta ni extra
                    else:
                        # Ancladas al horario PACTADO del turno (FIX
                        # 2026-07-08): llegar antes de turno_hora_entrada NO
                        # cuenta para nada; el sobretiempo es EXCLUSIVAMENTE
                        # tiempo trabajado después de turno_hora_salida.
                        h, extra_bruto_dia = _horas_dia_ancladas(
                            regs_dia, dia, turno_hora_entrada, turno_hora_salida, almuerzo_min)
                        horas_reales += h
                        if h > 0:
                            dias_laborados += 1
                        falta_dia = max(0.0, req_h - h)
                        extra_pag_dia = float(math.floor(extra_bruto_dia))  # solo la hora YA completada
                        extra25_dia = min(extra_pag_dia, 2.0)               # primeras 2h después de salida → 25%
                        extra35_dia = max(0.0, extra_pag_dia - 2.0)         # resto → 35%

                        horas_faltantes += falta_dia
                        horas_extra      += extra_bruto_dia
                        horas_extra_25   += extra25_dia
                        horas_extra_35   += extra35_dia

            if incluir_detalle_dias:
                detalle_dias.append({
                    "fecha":                dia,
                    "dia_semana":           _DIAS_ES[dia.weekday()],
                    "tipo_dia":             tipo_dia,
                    "es_justificado":       es_justificado,
                    "motivo_justificacion": motivo,
                    "turno_nombre":         turno_nombre,
                    "turno_hora_entrada":   turno_hora_entrada,
                    "turno_hora_salida":    turno_hora_salida,
                    "req_horas":            req_horas_dia,
                    "marcaciones": {
                        "entrada":          _marcacion_punto(entrada),
                        "salida":           _marcacion_punto(salida),
                        "almuerzo_inicio":  _marcacion_punto(ini_alm),
                        "almuerzo_fin":     _marcacion_punto(fin_alm),
                    },
                    "horas_reales":         h,
                    "horas_extra_bruto":    extra_bruto_dia,
                    "horas_extra_pagable":  extra_pag_dia,
                    "extra_25":             extra25_dia,
                    "extra_35":             extra35_dia,
                    "falta":                falta_dia,
                    # "sin_tramite" se resuelve DESPUÉS del loop (necesita el
                    # total de horas aprobadas del período) — ver abajo.
                    "alerta":               "marcacion_incompleta" if marcacion_incompleta else None,
                })

        # Horas extras aprobadas (permanencia_extra) — columna real
        # `horas_solicitadas` (FIX 2026-07-16, ver permisos.py:enviar_solicitud
        # y el modelo SolicitudLaboral; antes no existía columna alguna y esto
        # siempre salía en 0 con un getattr defensivo).
        perm_extra_h = float(sum(
            (s.horas_solicitadas or 0) for s in solis if s.tipo == "permanencia_extra"
        ))
        horas_total           = horas_reales + horas_justificadas
        horas_extra_aprobadas = round(min(horas_extra, perm_extra_h), 2)
        horas_extra_no_autor  = round(max(0.0, horas_extra - horas_extra_aprobadas), 2)
        porcentaje            = round((horas_total / meta_horas_emp * 100) if meta_horas_emp > 0 else 0.0, 1)

        if incluir_detalle_dias:
            # Alerta "sin_tramite" por día: asignación secuencial (primero el
            # día más antiguo) del total de horas con trámite aprobado
            # (`perm_extra_h`, truncado a hora completa, igual criterio que
            # el motor legal) contra el sobretiempo pagable de cada día — el
            # remanente sin cubrir se marca. No pisa "marcacion_incompleta"
            # si ya estaba marcada (un día puede tener ambos problemas, pero
            # el campo es un único string: se prioriza el de datos crudos).
            restante = math.floor(perm_extra_h)
            for fila_dia in detalle_dias:
                pagable_dia = fila_dia["extra_25"] + fila_dia["extra_35"]
                if pagable_dia <= 0:
                    continue
                if restante >= pagable_dia:
                    restante -= pagable_dia
                elif fila_dia["alerta"] is None:
                    fila_dia["alerta"] = "sin_tramite"

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
            "horas_extra_25":        round(horas_extra_25,     2),
            "horas_extra_35":        round(horas_extra_35,     2),
            "horas_extra_aprobadas": horas_extra_aprobadas,
            "horas_extra_no_autor":  horas_extra_no_autor,
            "horas_domingo":         round(horas_domingo, 2),
            "horas_feriado":         round(horas_feriado, 2),
            "dias_laborados":        dias_laborados,
            "meta_horas":            round(meta_horas_emp, 2),
            "porcentaje":            porcentaje,
            "advertencias":          advertencias,
            "detalle_dias":          detalle_dias,
        })

    return resultado
