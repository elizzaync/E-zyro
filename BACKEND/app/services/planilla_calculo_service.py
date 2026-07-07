"""
Motor de cálculo legal de Planilla (Fase 8 — Perú, 2026).

Puerto 1:1 de las fórmulas que hoy viven en el frontend
(`planillas.component.ts`, líneas 1-70 y 310-780). Sin acceso a base de
datos: recibe insumos ya resueltos (sueldo, asistencia, configuración
previsional) y devuelve el desglose completo de la boleta. Esto lo hace
100% testeable de forma aislada — deliberado, dado que es la pieza de mayor
riesgo de la migración (dinero real).

Reglas de fidelidad (no negociables sin volver a esta fuente):
  - Los valores intermedios NO se cuantizan a centavos; solo el resultado
    final se redondea al serializar (igual que el TS, que solo aplica
    `toFixed(2)` al mostrar, nunca en un cálculo intermedio). Cuantizar antes
    produce descuadres de céntimos frente a lo que el usuario ve hoy.
  - Se copian DOS particularidades ya existentes en el TS, sin "corregirlas"
    (ver notas inline en `impuesto_quinta_categoria` y `aporte_essalud`):
    la base de renta de 5ta no verifica que el régimen sea 'general' antes
    de sumar la asignación familiar (a diferencia de `asignacion_familiar`,
    que sí lo verifica); y EsSalud se calcula también para practicantes
    (no está condicionado por `es_dependiente` en el original).
  - `entidad_afp` sin definir cae a 'integra' (mismo default que
    `getAfpEntidad()` en el TS).

CORRECCIÓN DELIBERADA respecto al TS original (a pedido explícito del
usuario, 2026-07-06 — esto SÍ se corrige, a diferencia de las fidelidades de
arriba): el TS calculaba el pago base como "sueldo completo del período menos
un descuento aproximado por falta" (días completos ÷ 30 + una pequeña
corrección dominical), lo que dejaba un residuo de pago incluso con 100% de
inasistencia (ej. sueldo 1200, mes entero sin marcar asistencia → seguía
abonando ~S/73). Aquí el sueldo DEVENGADO se calcula proporcional a las horas
realmente trabajadas/justificadas frente a la meta del período
(`sueldo_devengado = sueldo_periodo × (meta_horas − horas_faltantes) /
meta_horas`), consistente con que `horas_reales` ya refleja fielmente
tardanzas (la duración entrada-salida ya sale más corta si llegó tarde, sin
descuento adicional que la duplique) y con la meta por turno de cada
empleado (practicantes u otros con jornada reducida cobran el 100% de SU
turno si lo cumplen, no se les exige la jornada estándar de 8h). Consecuencia
correcta: 0% de asistencia ⇒ sueldo devengado = 0 ⇒ neto = 0. `dias_faltantes`/
`minutos_tardanza`/`descuento_dominical` se conservan como campos
INFORMATIVOS (para mostrar en la boleta "por qué"), ya no participan en el
cálculo del neto — el descuento real ya está reflejado en `sueldo_devengado`.

CORRECCIONES 2026-07-07 (dos más, mismo criterio de fidelidad de arriba —
documentadas aquí porque cambian el CONTRATO de `InsumoEmpleado`, no solo un
número):
  - Comisión AFP por ESQUEMA (`tipo_comision_afp`): antes se sumaba SIEMPRE
    la comisión de la entidad al descuento; ahora solo se descuenta si el
    empleado está en esquema 'flujo' — el default legal 'saldo' (post-2013)
    no se descuenta en planilla (ver `_comision_afp_efectiva`).
  - Horas extra POR DÍA, no por acumulación de período: antes
    `horas_extra_pagables` se derivaba de `horas_reales - meta_horas` del
    PERÍODO completo (aplicaba el tramo 25%/35% una sola vez al mes y
    compensaba días cortos con días largos). Ahora `resumen_horas_periodo`
    agrega el sobretiempo día por día (D.S. 007-2002-TR: el tramo aplica por
    JORNADA) y el motor solo consume los buckets ya resueltos
    (`horas_extra_25`/`horas_extra_35`) — sin recalcular desde
    horas_reales/meta_horas. Se agrega además un gate configurable por
    empresa (`pagar_horas_extra_sin_tramite`, default False) que puede topar
    el pago a lo cubierto por trámite de Permanencia Extra aprobado.

Fuentes legales (idénticas al comentario original en TypeScript): SUNAFIL,
MTPE, SUNAT, SBS, Ley N.° 32353 (clasificación empresarial), D.L. 19990
(ONP), D.L. 25897 (AFP), D.L. 854 (jornada), Ley 28518 (modalidades
formativas), D.S. 035-90-TR (asignación familiar). Verificar vigencia antes
de procesar planilla real — un contador colegiado debe validar los casos
reales, igual que ya advertía el docstring de `models/planilla.py`.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, getcontext
from typing import Optional

getcontext().prec = 28  # explícito (coincide con el default de `decimal`, documentado a propósito)

CERO = Decimal("0")

# ── Divisores legales (D.L. 854, MTPE) — fijos por norma, no por calendario ──
DIVISOR_DIA = Decimal(30)
HORAS_JORNADA = Decimal(8)

# ── Parámetros legales vigentes 2026 (Perú) ──────────────────────────────────
PENSION_ONP_PCT = Decimal("0.13")      # ONP: aporte único fijo (D.L. 19990)
AFP_APORTE_PCT = Decimal("0.10")       # AFP: aporte obligatorio a cuenta individual (D.L. 25897)
AFP_SEGURO_PCT = Decimal("0.0137")     # AFP: prima de seguro 2026 — 1.37% (tope S/ 12,209.11)
ESSALUD_PCT = Decimal("0.09")          # EsSalud: aporte patronal 9% — NO se descuenta al trabajador (Ley 26790)
RMV_VIGENTE = Decimal(1130)            # RMV vigente desde enero 2025 (D.S. 001-2025-TR)
CTS_PEQUENA_FACTOR = Decimal(1) / Decimal(24)      # Pequeña Empresa: 15 rem. diarias/año (tope 90 días)
GRATIF_PEQUENA_FACTOR = Decimal(1) / Decimal(12)   # Pequeña Empresa: 2 medias remun./año
CTS_GENERAL_FACTOR = Decimal(1) / Decimal(12)      # Régimen General: 1 remuneración/año
GRATIF_GENERAL_FACTOR = Decimal(1) / Decimal(6)    # Régimen General: 2 sueldos completos/año
VACACIONES_DIAS_MYPE = 15               # Micro y Pequeña Empresa: 15 días/año (Ley N.° 32353)
VACACIONES_DIAS_GENERAL = 30            # Régimen General: 30 días/año
ASIG_FAMILIAR_PCT = Decimal("0.10")     # 10% RMV = S/ 113.00 — SOLO Régimen General (D.S. 035-90-TR)
UIT_VIGENTE = Decimal(5500)             # UIT 2026 (R.M. SUNAT)
RENTA_5TA_DEDUCCION_UIT = Decimal(7)    # Deducción anual: 7 UIT = S/ 38,500 (2026)

# Tramos progresivos Renta de 5ta Categoría (base imponible anual en UIT).
# `None` en el último tramo representa "sin límite" (Infinity en el TS).
RENTA_5TA_TRAMOS: list[tuple[Optional[Decimal], Decimal]] = [
    (Decimal(5),  Decimal("0.08")),
    (Decimal(20), Decimal("0.14")),
    (Decimal(35), Decimal("0.17")),
    (Decimal(45), Decimal("0.20")),
    (None,        Decimal("0.30")),
]

# Comisión por flujo de cada AFP (2026, modalidad flujo — verificar SBS)
AFP_COMISIONES: dict[str, Decimal] = {
    "integra":   Decimal("0.0155"),
    "prima":     Decimal("0.0160"),
    "profuturo": Decimal("0.0169"),
    "habitat":   Decimal("0.0147"),
}

TIPOS_DEPENDIENTE = ("planilla", "contrato")
TIPO_PRACTICANTE = "practicante"


@dataclass
class InsumoEmpleado:
    """Datos ya resueltos de un empleado para un período — sin acceso a BD."""
    empleado_id: str
    tipo_contrato: str                          # planilla|contrato|practicante
    sueldo_base: Decimal                        # mensual completo (0 si no configurado)
    horas_reales: Decimal
    horas_faltantes: Decimal
    meta_horas: Decimal
    sistema_pension: str = "onp"                # onp|afp
    entidad_afp: Optional[str] = None           # None ⇒ 'integra' (mismo default que el TS)
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: bool = False
    # Horas de sobretiempo con trámite de "Permanencia Extra" APROBADO
    # (SolicitudLaboral tipo=permanencia_extra, estado=aprobada) — alimenta
    # la alerta de documentación (horas_extra_sin_tramite) y, si la empresa
    # exige trámite (Empresa.pagar_horas_extra_sin_tramite=False), también
    # el TOPE de lo que se paga (ver calcular_boleta_empleado).
    horas_extra_aprobadas: Decimal = field(default_factory=lambda: Decimal(0))
    # Sistema de comisión SPP (2026-07-07): 'saldo' (default legal desde
    # 2013, ~0.78% anual sobre el FONDO acumulado — NO se descuenta en
    # planilla) o 'flujo' (sobre la remuneración — SÍ se descuenta cada mes).
    # Ver `_comision_afp_efectiva`.
    tipo_comision_afp: str = "saldo"
    # Sobretiempo YA agregado POR DÍA desde `resumen_horas_periodo`
    # (D.S. 007-2002-TR: el tramo 25%/35% se calcula por JORNADA, no por
    # período — sin netear un día corto con uno largo). `horas_extra` es el
    # total informativo sin truncar; `horas_extra_25`/`horas_extra_35` ya
    # vienen truncadas a la hora completa y clasificadas por tramo (25% las
    # primeras 2h de CADA día, 35% el resto de ese día), sumadas across todo
    # el período.
    horas_extra: Decimal = field(default_factory=lambda: Decimal(0))
    horas_extra_25: Decimal = field(default_factory=lambda: Decimal(0))
    horas_extra_35: Decimal = field(default_factory=lambda: Decimal(0))
    # Horas trabajadas en domingo (día de descanso semanal obligatorio,
    # D.Leg. 713 Art. 3/4) — independientes de horas_reales/meta_horas.
    horas_domingo: Decimal = field(default_factory=lambda: Decimal(0))
    # Horas trabajadas en un feriado no laborable sin descanso sustitutorio
    # (D.Leg. 713 Art. 8/9) — mismo tratamiento legal que el domingo, pero
    # ya excluye los feriados que caen en domingo (ver
    # planilla_asistencia_service._feriados_trabajables, evita duplicar la
    # sobretasa) — independientes de horas_reales/meta_horas.
    horas_feriado: Decimal = field(default_factory=lambda: Decimal(0))


@dataclass
class DesgloseBoleta:
    """Resultado completo del cálculo — 1:1 con lo que hoy muestra la boleta."""
    sueldo_periodo: Decimal
    sueldo_devengado: Decimal   # sueldo_periodo ya proporcional a lo asistido (ver corrección arriba)
    valor_dia: Decimal
    valor_hora: Decimal
    valor_minuto: Decimal
    dias_faltantes: int
    minutos_tardanza: int
    descuento_dominical: Decimal
    descuento_faltas: Decimal
    horas_extra: Decimal              # informativo: total de sobretiempo trabajado (sin redondear)
    horas_extra_25: Decimal           # informativo: horas COMPLETAS de sobretiempo en tramo 25% (antes del gate de trámite)
    horas_extra_35: Decimal           # informativo: horas COMPLETAS de sobretiempo en tramo 35% (antes del gate de trámite)
    horas_extra_pagables: Decimal     # horas COMPLETAS que SÍ se pagan (D.S. 007-2002-TR exige pagar
                                       # incluso la fracción de hora, pero a pedido explícito del usuario
                                       # solo se paga la hora ya completada; además puede quedar topado
                                       # por el gate de trámite, ver `pagar_horas_extra_sin_tramite`)
    horas_extra_sin_tramite: Decimal  # informativo: de todo el sobretiempo truncado, cuánto no tiene
                                       # trámite de Permanencia Extra aprobado (alerta para RRHH, SIEMPRE
                                       # se calcula, sin importar el gate)
    pago_horas_extra: Decimal
    horas_domingo: Decimal            # informativo: horas trabajadas el día de descanso semanal
    pago_domingo: Decimal             # retribución + sobretasa 100% (D.Leg. 713 Art. 3) — SÍ afecta el neto
    horas_feriado: Decimal            # informativo: horas trabajadas en feriado no laborable
    pago_feriado: Decimal             # retribución + sobretasa 100% (D.Leg. 713 Art. 8/9) — SÍ afecta el neto
    asignacion_familiar: Decimal
    es_afp: bool
    base_pension: Decimal
    descuento_pension: Decimal
    afp_aporte_obligatorio: Decimal
    afp_prima_seguro: Decimal
    afp_comision: Decimal
    comision_afp_pct: Decimal
    renta_5ta: Decimal
    total_ingresos: Decimal
    total_descuentos_legales: Decimal
    neto_a_pagar: Decimal
    aporte_essalud: Decimal
    provision_cts: Decimal
    provision_gratificacion: Decimal
    provision_vacaciones: Decimal
    dias_vacaciones: int
    bajo_rmv: bool


# ── Helpers de clasificación (TS: esDependiente / esPracticante) ────────────

def es_dependiente(tipo_contrato: str) -> bool:
    return tipo_contrato in TIPOS_DEPENDIENTE


def es_practicante(tipo_contrato: str) -> bool:
    return tipo_contrato == TIPO_PRACTICANTE


def dias_vacaciones(regimen_empresa: str) -> int:
    return VACACIONES_DIAS_GENERAL if regimen_empresa == "general" else VACACIONES_DIAS_MYPE


def _comision_afp_efectiva(insumo: InsumoEmpleado) -> Decimal:
    """Comisión SPP efectiva según el ESQUEMA (SBS, 2026-07-07):
      - 'saldo' (default legal desde 2013 para todo afiliado que no migró
        explícitamente a flujo): comisión ~0.78% ANUAL sobre el FONDO
        acumulado, la cobra la AFP directamente del fondo, NUNCA de la
        remuneración — en planilla es 0%.
      - 'flujo' (esquema anterior, aún vigente para quienes no migraron):
        comisión MENSUAL sobre la remuneración — SÍ se descuenta en
        planilla. Personalizada si el empleado la sobreescribió; si no, la
        tasa oficial de su entidad (default 'integra', igual que
        `getAfpEntidad()` en el TS)."""
    if insumo.tipo_comision_afp == "saldo":
        return CERO
    if insumo.comision_afp_personalizada is not None:
        return insumo.comision_afp_personalizada
    entidad = insumo.entidad_afp or "integra"
    return AFP_COMISIONES[entidad]


# ── Cálculo principal ────────────────────────────────────────────────────────

def calcular_boleta_empleado(
    insumo: InsumoEmpleado,
    *,
    regimen_empresa: str,
    periodo_pago: str,                  # 'mes' | 'q1' | 'q2' — solo 'mes' vs. resto importa aquí
    descuento_tardanza_auto: bool = True,
    pagar_horas_extra_sin_tramite: bool = False,
) -> DesgloseBoleta:
    """Calcula el desglose completo de la boleta de UN empleado para un
    período. Puerto 1:1 de `planillas.component.ts` (líneas 310-780)."""
    dependiente = es_dependiente(insumo.tipo_contrato)
    practicante = es_practicante(insumo.tipo_contrato)
    es_mes = periodo_pago == "mes"

    # sueldoPeriodo(): mes completo o mitad exacta en quincena (NO prorrateo
    # por días reales — es la convención peruana de "adelanto quincenal").
    sueldo_periodo = insumo.sueldo_base if es_mes else insumo.sueldo_base / Decimal(2)

    # valorDia/Hora/Minuto: usan SIEMPRE el sueldo MENSUAL completo (no el de
    # la quincena), tal como el TS (`valorDia` llama a `getSueldo`, no a
    # `sueldoPeriodo`).
    valor_dia = insumo.sueldo_base / DIVISOR_DIA
    valor_hora = valor_dia / HORAS_JORNADA
    valor_minuto = valor_hora / Decimal(60)

    # Faltas / tardanzas — SOLO INFORMATIVO (desglose para mostrar en la
    # boleta "por qué"). El descuento real de dinero ya no pasa por aquí:
    # ver sueldo_devengado más abajo (corrección deliberada, ver docstring
    # del módulo). `descuento_tardanza_auto` ya no tiene efecto monetario
    # directo — se preserva el parámetro por compatibilidad de firma/config,
    # pero la proporción de asistencia ya captura cualquier tardanza real
    # (horas_reales sale más corto si el empleado marcó tarde).
    horas_faltantes_int = insumo.horas_faltantes
    dias_faltantes_dec = (horas_faltantes_int / HORAS_JORNADA).to_integral_value(rounding="ROUND_FLOOR")
    dias_faltantes = int(dias_faltantes_dec)
    minutos_tardanza_dec = (horas_faltantes_int % HORAS_JORNADA) * Decimal(60)
    minutos_tardanza = int(minutos_tardanza_dec.to_integral_value(rounding="ROUND_HALF_UP"))
    descuento_dominical = Decimal(dias_faltantes) * valor_dia / DIVISOR_DIA

    # Sueldo DEVENGADO: proporcional a lo realmente asistido/justificado
    # frente a la meta del período (ya sea la jornada estándar o el turno
    # específico del empleado — meta_horas ya viene resuelta por turno desde
    # `resumen_horas_periodo`). horas_faltantes siempre cae en [0, meta_horas]
    # por construcción, así que la proporción siempre cae en [0, 1].
    if insumo.meta_horas > CERO:
        proporcion_asistencia = max(CERO, min(
            Decimal(1), (insumo.meta_horas - insumo.horas_faltantes) / insumo.meta_horas
        ))
    else:
        proporcion_asistencia = Decimal(1)  # sin meta definida (ej. rango sin días laborables): no penalizar
    sueldo_devengado = sueldo_periodo * proporcion_asistencia
    # descuento_faltas ahora es informativo: cuánto del sueldo del período NO
    # se devengó por inasistencia. Ya está reflejado en sueldo_devengado, no
    # se vuelve a restar en total_descuentos_legales (evita duplicar el
    # descuento).
    descuento_faltas = sueldo_periodo - sueldo_devengado

    # Horas extra: recargo legal 25%/35% (DL 854) solo para dependientes;
    # practicantes a tarifa simple (Ley 28518, sin "sobretiempo" legal). Ya
    # vienen agregadas POR DÍA desde `resumen_horas_periodo` (D.S.
    # 007-2002-TR: el tramo 25%/35% aplica por JORNADA, no una sola vez al
    # período — sin netear un día corto con uno largo) y truncadas a la hora
    # completa por día (decisión de negocio explícita del usuario,
    # 2026-07-06: solo se paga la hora ya completada, no la fracción).
    horas_extra = insumo.horas_extra              # informativo, sin truncar
    total_extra_pag = insumo.horas_extra_25 + insumo.horas_extra_35

    # Gate de trámite (decisión de negocio CON RIESGO LEGAL, configurable por
    # empresa, default False — Empresa.pagar_horas_extra_sin_tramite):
    #   - False: solo se paga el sobretiempo CUBIERTO por un trámite de
    #     Permanencia Extra APROBADO; el resto queda sin pagar (solo alerta).
    #   - True: se paga TODO el sobretiempo truncado registrado, sin
    #     importar el trámite (SUNAFIL presume autorización tácita con el
    #     solo registro de asistencia).
    aprobadas = insumo.horas_extra_aprobadas.to_integral_value(rounding="ROUND_FLOOR")
    if pagar_horas_extra_sin_tramite:
        pagables = total_extra_pag
    else:
        pagables = min(total_extra_pag, aprobadas)
    pagables_25 = min(pagables, insumo.horas_extra_25)   # llena el tramo 25% primero
    pagables_35 = pagables - pagables_25

    horas_extra_pagables = pagables   # horas COMPLETAS que SÍ se pagan (ya con el gate aplicado)
    if pagables <= CERO:
        pago_horas_extra = CERO
    elif practicante:
        pago_horas_extra = pagables * valor_hora
    else:
        pago_horas_extra = (
            pagables_25 * valor_hora * Decimal("1.25")
            + pagables_35 * valor_hora * Decimal("1.35")
        )

    # Alerta de documentación: SIEMPRE informativa, sin importar el gate — de
    # todo el sobretiempo truncado, cuánto no tiene trámite de Permanencia
    # Extra aprobado. Avisa a RRHH para que regularice el trámite antes de
    # aprobar la planilla (y, con el gate en False, también explica por qué
    # esa parte no se pagó).
    horas_extra_sin_tramite = max(CERO, total_extra_pag - aprobadas)

    # Trabajo en el día de descanso semanal obligatorio (domingo, D.Leg. 713
    # Art. 3/4): "retribución correspondiente a la labor efectuada MÁS una
    # sobretasa del 100%" = doble. Independiente de horas_extra (no cuenta
    # contra la meta ni contra el sobretiempo ordinario). Mismo criterio que
    # horas extra para practicantes (Ley 28518: sin relación laboral, sin el
    # beneficio de sobretasa — se reconoce a tarifa simple, 1x).
    factor_domingo = Decimal(1) if practicante else Decimal(2)
    pago_domingo = insumo.horas_domingo * valor_hora * factor_domingo

    # Trabajo en feriado no laborable sin descanso sustitutorio (D.Leg. 713
    # Art. 8/9): idéntico tratamiento legal que el domingo — "retribución
    # correspondiente a la labor efectuada MÁS una sobretasa del 100%" para
    # dependientes; tarifa simple para practicantes (Ley 28518).
    factor_feriado = Decimal(1) if practicante else Decimal(2)
    pago_feriado = insumo.horas_feriado * valor_hora * factor_feriado

    # Asignación Familiar: 10% RMV, SOLO Régimen General, solo dependientes
    # con el flag activo (D.S. N.° 035-90-TR).
    #
    # CORRECCIÓN DELIBERADA (misma sesión, 2026-07-06): igual que el sueldo
    # base, es remuneración computable del período — se prorratea por la
    # proporción de asistencia. Sin esto, un empleado con 0% de asistencia
    # igual "cobraba" la asignación familiar completa, y ese residuo generaba
    # a su vez base de pensión y (en el Caso E-like) renta 5ta sobre un
    # ingreso que en la práctica no correspondía. Es el mismo principio que
    # motivó la corrección de sueldo_devengado: si no trabajó nada, ningún
    # concepto ligado a la remuneración del período debería pagarse.
    if not dependiente or regimen_empresa != "general" or not insumo.tiene_asignacion_familiar:
        asignacion_familiar = CERO
    else:
        mensual = RMV_VIGENTE * ASIG_FAMILIAR_PCT
        mensual = mensual if es_mes else mensual / Decimal(2)
        asignacion_familiar = mensual * proporcion_asistencia

    # Base imponible para pensiones = remuneración computable del período
    # (ya con sueldo_devengado, que refleja la asistencia real). Incluye el
    # pago de domingo/feriado: es remuneración regular sujeta a aportes, no
    # un concepto no computable.
    if not dependiente:
        base_pension = CERO
    else:
        base = sueldo_devengado + pago_horas_extra + asignacion_familiar + pago_domingo + pago_feriado
        base_pension = max(CERO, base)

    es_afp = dependiente and insumo.sistema_pension == "afp"
    comision_pct = _comision_afp_efectiva(insumo)

    if not dependiente:
        descuento_pension = CERO
        pension_pct = CERO
    else:
        pension_pct = PENSION_ONP_PCT if insumo.sistema_pension == "onp" else (
            AFP_APORTE_PCT + AFP_SEGURO_PCT + comision_pct
        )
        descuento_pension = base_pension * pension_pct

    afp_aporte_obligatorio = base_pension * AFP_APORTE_PCT if es_afp else CERO
    afp_prima_seguro = base_pension * AFP_SEGURO_PCT if es_afp else CERO
    afp_comision = base_pension * comision_pct if es_afp else CERO

    # EsSalud: costo del EMPLEADOR, nunca se descuenta al trabajador. Sobre
    # sueldo_devengado (no se aporta EsSalud sobre remuneración no devengada).
    # Fidelidad deliberada: se calcula para AMBAS modalidades (no está
    # condicionado por es_dependiente en el original) — se copia tal cual.
    aporte_essalud = sueldo_devengado * ESSALUD_PCT

    # CTS / Gratificación / Vacaciones: SOLO informativos (provisión
    # mensualizada sobre lo devengado). NO afectan el neto de este mes — se
    # pagan en su fecha legal real (CTS mayo/noviembre, gratificación
    # julio/diciembre).
    if not dependiente or regimen_empresa == "micro":
        provision_cts = CERO
        provision_gratificacion = CERO
    else:
        factor_cts = CTS_GENERAL_FACTOR if regimen_empresa == "general" else CTS_PEQUENA_FACTOR
        factor_grat = GRATIF_GENERAL_FACTOR if regimen_empresa == "general" else GRATIF_PEQUENA_FACTOR
        provision_cts = sueldo_devengado * factor_cts
        provision_gratificacion = sueldo_devengado * factor_grat

    dv = dias_vacaciones(regimen_empresa)
    provision_vacaciones = (
        sueldo_devengado * (Decimal(dv) / Decimal(360)) if dependiente else CERO
    )

    # Renta de 5ta categoría — proyección anual, tramos progresivos.
    # Fidelidad deliberada: a diferencia de `asignacion_familiar`, esta base
    # NO verifica que el régimen sea 'general' antes de sumar la asignación
    # familiar a la renta anual — inconsistencia YA presente en el TS
    # original, se copia tal cual (no se corrige en esta migración).
    #
    # CORRECCIÓN DELIBERADA (misma sesión, 2026-07-06): la proyección anual
    # se hace sobre `sueldo_devengado` (lo realmente ganado este período), NO
    # sobre `insumo.sueldo_base` (el teórico). Con el sueldo teórico, un
    # empleado con 0% de asistencia (sueldo_devengado=0) igual generaba una
    # retención >0 — no se puede retener impuesto sobre un pago que nunca se
    # hizo; eso producía un NETO NEGATIVO al persistir la boleta (la
    # retención superaba unos ingresos de 0). Consistente además con la
    # práctica real de SUNAT: la proyección se reajusta según la
    # remuneración efectivamente percibida, no la contractual fija.
    if not dependiente or sueldo_devengado <= CERO:
        renta_5ta = CERO
    else:
        asig_mensual_renta = RMV_VIGENTE * ASIG_FAMILIAR_PCT if insumo.tiene_asignacion_familiar else CERO
        renta_anual = (sueldo_devengado + asig_mensual_renta) * Decimal(12)
        deduccion = RENTA_5TA_DEDUCCION_UIT * UIT_VIGENTE
        base_imponible = max(CERO, renta_anual - deduccion)
        if base_imponible == CERO:
            renta_5ta = CERO
        else:
            impuesto_anual = _renta_5ta_progresiva(base_imponible)
            impuesto_mensual = impuesto_anual / Decimal(12)
            renta_5ta = impuesto_mensual if es_mes else impuesto_mensual / Decimal(2)

    # total_ingresos parte de sueldo_devengado (ya proporcional a la
    # asistencia real) — el descuento por faltas NO se resta de nuevo en
    # total_descuentos_legales (sería duplicarlo). Los únicos descuentos
    # "legales" reales son pensión y renta de 5ta.
    total_ingresos = sueldo_devengado + pago_horas_extra + asignacion_familiar + pago_domingo + pago_feriado
    total_descuentos_legales = descuento_pension + renta_5ta
    neto_a_pagar = CERO if sueldo_periodo <= CERO else max(CERO, total_ingresos - total_descuentos_legales)

    bajo_rmv = insumo.sueldo_base > CERO and insumo.sueldo_base < RMV_VIGENTE

    return DesgloseBoleta(
        sueldo_periodo=sueldo_periodo, sueldo_devengado=sueldo_devengado,
        valor_dia=valor_dia, valor_hora=valor_hora, valor_minuto=valor_minuto,
        dias_faltantes=dias_faltantes, minutos_tardanza=minutos_tardanza,
        descuento_dominical=descuento_dominical, descuento_faltas=descuento_faltas,
        horas_extra=horas_extra, horas_extra_25=insumo.horas_extra_25, horas_extra_35=insumo.horas_extra_35,
        horas_extra_pagables=horas_extra_pagables,
        horas_extra_sin_tramite=horas_extra_sin_tramite, pago_horas_extra=pago_horas_extra,
        horas_domingo=insumo.horas_domingo, pago_domingo=pago_domingo,
        horas_feriado=insumo.horas_feriado, pago_feriado=pago_feriado,
        asignacion_familiar=asignacion_familiar,
        es_afp=es_afp, base_pension=base_pension, descuento_pension=descuento_pension,
        afp_aporte_obligatorio=afp_aporte_obligatorio, afp_prima_seguro=afp_prima_seguro,
        afp_comision=afp_comision, comision_afp_pct=comision_pct,
        renta_5ta=renta_5ta,
        total_ingresos=total_ingresos, total_descuentos_legales=total_descuentos_legales,
        neto_a_pagar=neto_a_pagar,
        aporte_essalud=aporte_essalud,
        provision_cts=provision_cts, provision_gratificacion=provision_gratificacion,
        provision_vacaciones=provision_vacaciones, dias_vacaciones=dv,
        bajo_rmv=bajo_rmv,
    )


def _renta_5ta_progresiva(base_imponible: Decimal) -> Decimal:
    """Recorre `RENTA_5TA_TRAMOS` acumulando el impuesto anual por tramos
    progresivos. Traducción exacta del bucle `for (const tramo of
    RENTA_5TA_TRAMOS)` del TS, incluyendo el `break` temprano cuando la base
    ya quedó cubierta por el tramo actual."""
    impuesto_anual = CERO
    limite_anterior = CERO
    for limite_uit, tasa in RENTA_5TA_TRAMOS:
        if limite_uit is None:  # último tramo, "sin límite" (Infinity en TS)
            monto_en_tramo = max(CERO, base_imponible - limite_anterior)
            impuesto_anual += monto_en_tramo * tasa
            break
        limite_uit_soles = limite_uit * UIT_VIGENTE
        monto_en_tramo = max(CERO, min(base_imponible, limite_uit_soles) - limite_anterior)
        impuesto_anual += monto_en_tramo * tasa
        limite_anterior = limite_uit_soles
        if base_imponible <= limite_uit_soles:
            break
    return impuesto_anual
