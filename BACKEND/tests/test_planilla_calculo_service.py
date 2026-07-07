"""
Pruebas del motor de cálculo legal de Planilla (Fase 8).

Los valores esperados de cada caso fueron calculados con un script de
referencia INDEPENDIENTE (no importa `planilla_calculo_service`, reimplementa
las fórmulas por separado con `Decimal` a partir de la especificación legal),
no a mano ni re-ejecutando el TypeScript. Tolerancia: exacta a 2 decimales
(lo único que importa para dinero real); los valores intermedios del motor NO
se cuantizan, solo se comparan ya redondeados aquí.

Ejecutar:  cd BACKEND && pytest tests/test_planilla_calculo_service.py -v
"""
from decimal import Decimal

import pytest

from app.services.planilla_calculo_service import (
    InsumoEmpleado, calcular_boleta_empleado,
)


def q2(v: Decimal) -> Decimal:
    return v.quantize(Decimal("0.01"))


def calc(**kwargs):
    """Atajo: separa los kwargs de InsumoEmpleado de los de configuración
    (regimen_empresa, periodo_pago, descuento_tardanza_auto)."""
    config_keys = {"regimen_empresa", "periodo_pago", "descuento_tardanza_auto",
                    "pagar_horas_extra_sin_tramite"}
    config = {k: v for k, v in kwargs.items() if k in config_keys}
    insumo_kwargs = {k: v for k, v in kwargs.items() if k not in config_keys}
    config.setdefault("periodo_pago", "mes")
    config.setdefault("descuento_tardanza_auto", True)
    insumo = InsumoEmpleado(empleado_id="test", **insumo_kwargs)
    return calcular_boleta_empleado(insumo, **config)


# ── Caso A: dependiente, ONP, régimen general, con horas extra y faltas ─────
def test_caso_a_dependiente_onp_general_con_extras_y_faltas():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2500),
        horas_faltantes=Decimal(10), horas_reales=Decimal(180), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=True,
        regimen_empresa="general",
        # FIX 2026-07-07: la hora extra ya no se deriva de horas_reales-meta_horas
        # (acumulación de período) — se pasa explícita, ya agregada por día y
        # truncada (equivalente al escenario original: 4h de sobretiempo en un
        # solo día, 2h@25% + 2h@35%). Sin trámite formal, así que se necesita el
        # gate en True para reproducir "se paga toda la hora extra registrada".
        horas_extra=Decimal(4), horas_extra_25=Decimal(2), horas_extra_35=Decimal(2),
        pagar_horas_extra_sin_tramite=True,
    )
    # Informativos (ya no afectan el dinero, solo describen la asistencia)
    assert d.dias_faltantes == 1
    assert d.minutos_tardanza == 120
    assert q2(d.descuento_dominical) == Decimal("2.78")
    # Sueldo devengado: proporcional a (meta_horas - horas_faltantes)/meta_horas = 166/176
    assert q2(d.sueldo_devengado) == Decimal("2357.95")
    assert q2(d.descuento_faltas) == Decimal("142.05")          # informativo: 2500 - 2357.95
    assert d.horas_extra == Decimal(4)
    assert q2(d.pago_horas_extra) == Decimal("54.17")          # 2h@25% + 2h@35%
    # Asignación familiar TAMBIÉN proporcional a la asistencia (106.58, no 113
    # completo): mismo principio que el sueldo — remuneración computable del
    # período, no un monto fijo ajeno a si el empleado trabajó o no.
    assert q2(d.asignacion_familiar) == Decimal("106.58")
    assert d.es_afp is False
    assert q2(d.base_pension) == Decimal("2518.70")
    assert q2(d.descuento_pension) == Decimal("327.43")         # ONP 13% plano sobre la base ya proporcional
    assert q2(d.afp_aporte_obligatorio) == Decimal("0.00")
    assert d.renta_5ta == Decimal(0)                            # no supera las 7 UIT de deducción
    assert q2(d.total_ingresos) == Decimal("2518.70")
    assert q2(d.total_descuentos_legales) == Decimal("327.43")
    assert q2(d.neto_a_pagar) == Decimal("2191.27")
    # Informativos (EsSalud/provisiones): sobre lo DEVENGADO, no el sueldo teórico completo
    assert q2(d.aporte_essalud) == Decimal("212.22")
    assert q2(d.provision_cts) == Decimal("196.50")
    assert q2(d.provision_gratificacion) == Decimal("392.99")
    assert q2(d.provision_vacaciones) == Decimal("196.50")
    assert d.dias_vacaciones == 30
    assert d.bajo_rmv is False


# ── Caso B: dependiente, AFP con comisión personalizada, pequeña empresa ────
def test_caso_b_afp_comision_personalizada_pequena_empresa():
    d = calc(
        tipo_contrato="contrato", sueldo_base=Decimal(1800),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="afp", entidad_afp="prima",
        comision_afp_personalizada=Decimal("0.0175"), tiene_asignacion_familiar=False,
        regimen_empresa="pequena",
        # FIX 2026-07-07: la comisión personalizada solo se aplica en esquema
        # 'flujo' (en 'saldo', el default, la comisión no se descuenta en planilla).
        tipo_comision_afp="flujo",
    )
    assert d.es_afp is True
    assert d.comision_afp_pct == Decimal("0.0175")               # pisa la tabla oficial (0.0160)
    assert q2(d.afp_aporte_obligatorio) == Decimal("180.00")     # 10% de 1800
    assert q2(d.afp_prima_seguro) == Decimal("24.66")            # 1.37% de 1800
    assert q2(d.afp_comision) == Decimal("31.50")                # 1.75% de 1800 (custom)
    # El desglose de las 3 líneas debe sumar exacto al descuento total
    assert q2(d.afp_aporte_obligatorio + d.afp_prima_seguro + d.afp_comision) == q2(d.descuento_pension)
    assert q2(d.descuento_pension) == Decimal("236.16")
    assert q2(d.neto_a_pagar) == Decimal("1563.84")
    # Factores de pequeña empresa (distintos de régimen general)
    assert q2(d.provision_cts) == Decimal("75.00")               # 1/24 de 1800
    assert q2(d.provision_gratificacion) == Decimal("150.00")    # 1/12 de 1800
    assert d.dias_vacaciones == 15


# ── Caso C: practicante ─────────────────────────────────────────────────────
def test_caso_c_practicante():
    d = calc(
        tipo_contrato="practicante", sueldo_base=Decimal(1200),
        horas_faltantes=Decimal(4), horas_reales=Decimal(170), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=False,
        regimen_empresa="general",
    )
    assert d.es_afp is False
    assert q2(d.descuento_pension) == Decimal("0.00")            # sin afiliación obligatoria (Ley 28518)
    assert d.renta_5ta == Decimal(0)
    assert q2(d.asignacion_familiar) == Decimal("0.00")
    assert q2(d.provision_cts) == Decimal("0.00")
    assert q2(d.provision_gratificacion) == Decimal("0.00")
    assert q2(d.provision_vacaciones) == Decimal("0.00")
    # Sueldo devengado proporcional: (176-4)/176 = 172/176 de 1200
    assert q2(d.sueldo_devengado) == Decimal("1172.73")
    assert q2(d.descuento_faltas) == Decimal("27.27")            # informativo
    # Fidelidad deliberada: EsSalud se calcula IGUAL para practicantes (no
    # condicionado por es_dependiente en el original) — no es un bug, se copia tal cual.
    # Ahora sobre lo devengado, no sobre el sueldo teórico completo.
    assert q2(d.aporte_essalud) == Decimal("105.55")
    assert q2(d.neto_a_pagar) == Decimal("1172.73")


# ── Caso H: 100% de inasistencia — el neto DEBE ser exactamente 0 ──────────
def test_caso_h_inasistencia_total_no_debe_pagar_nada():
    """Escenario reportado por el usuario: sueldo 1200, mes entero sin marcar
    asistencia (horas_faltantes == meta_horas). Antes de la corrección esto
    dejaba un residuo (~S/73) por el método de 'descuento aproximado sobre
    sueldo completo'; ahora el sueldo devengado es proporcional y da 0 exacto."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(1200),
        horas_faltantes=Decimal(216), horas_reales=Decimal(0), meta_horas=Decimal(216),
        sistema_pension="onp", tiene_asignacion_familiar=False, regimen_empresa="micro",
    )
    assert q2(d.sueldo_devengado) == Decimal("0.00")
    assert q2(d.descuento_faltas) == Decimal("1200.00")          # informativo: se perdió el sueldo completo
    assert q2(d.total_ingresos) == Decimal("0.00")
    assert q2(d.descuento_pension) == Decimal("0.00")
    assert q2(d.neto_a_pagar) == Decimal("0.00")
    assert q2(d.aporte_essalud) == Decimal("0.00")               # tampoco se aporta EsSalud sobre nada devengado


# ── Caso J: 100% inasistencia CON sueldo alto — renta 5ta no debe generarse
# sobre un sueldo que nunca se pagó (bug real encontrado al probar Fase 4
# contra producción: sin este fix, neto quedaba NEGATIVO) ──────────────────
def test_caso_j_inasistencia_total_con_sueldo_alto_no_genera_renta_5ta_fantasma():
    """Mismo sueldo que el Caso E (6000, con asignación familiar, régimen
    general) que SÍ generaba renta 5ta > 0 con asistencia completa — pero acá
    con 0% de asistencia. Antes de la corrección doble (sueldo_devengado +
    asignación familiar proporcionales), quedaba un residuo de asignación
    familiar fija que generaba base de pensión y renta 5ta sobre un ingreso
    que en la práctica no correspondía — llegando incluso a un NETO NEGATIVO
    al persistir la boleta real. Debe dar exactamente 0 en absolutamente
    todo: sin asistencia, no hay remuneración computable del período."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(6000),
        horas_faltantes=Decimal(176), horas_reales=Decimal(0), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=True, regimen_empresa="general",
    )
    assert q2(d.sueldo_devengado) == Decimal("0.00")
    assert q2(d.asignacion_familiar) == Decimal("0.00")  # antes: 113.00 fijo (residuo)
    assert q2(d.base_pension) == Decimal("0.00")
    assert q2(d.descuento_pension) == Decimal("0.00")
    assert q2(d.renta_5ta) == Decimal("0.00")            # antes: 269.15 (fantasma)
    assert q2(d.total_ingresos) == Decimal("0.00")
    assert q2(d.total_descuentos_legales) == Decimal("0.00")
    assert q2(d.neto_a_pagar) == Decimal("0.00")         # nunca negativo


# ── Caso I: practicante con turno reducido, asistencia completa ────────────
def test_caso_i_turno_reducido_con_asistencia_completa_cobra_el_100pct():
    """meta_horas ya viene resuelta por el TURNO específico del empleado
    (Fase 0, resumen_horas_periodo) — un practicante con una jornada más
    corta que la estándar de 8h NO debe verse penalizado por eso: si cumple
    SU turno completo, cobra el 100% de su sueldo, sin importar que sea menos
    horas que un puesto de jornada completa."""
    d = calc(
        tipo_contrato="practicante", sueldo_base=Decimal(600),
        horas_faltantes=Decimal(0), horas_reales=Decimal(88), meta_horas=Decimal(88),
        sistema_pension="onp", tiene_asignacion_familiar=False, regimen_empresa="general",
    )
    assert q2(d.sueldo_devengado) == Decimal("600.00")
    assert q2(d.descuento_faltas) == Decimal("0.00")
    assert q2(d.neto_a_pagar) == Decimal("600.00")


# ── Caso D: sueldo bajo la RMV ───────────────────────────────────────────────
def test_caso_d_bajo_rmv_es_solo_informativo():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(900),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=False,
        regimen_empresa="micro",
    )
    assert d.bajo_rmv is True
    # El flag no debe alterar ningún otro cálculo: ONP 13% normal sobre 900
    assert q2(d.descuento_pension) == Decimal("117.00")
    assert q2(d.neto_a_pagar) == Decimal("783.00")
    # Microempresa: CTS y gratificación exonerados, pero vacaciones (15 días) sí aplican
    assert q2(d.provision_cts) == Decimal("0.00")
    assert q2(d.provision_gratificacion) == Decimal("0.00")
    assert q2(d.provision_vacaciones) == Decimal("37.50")
    assert d.dias_vacaciones == 15


# ── Caso E: renta de 5ta categoría SÍ se activa (sueldo alto) ───────────────
def test_caso_e_renta_5ta_se_activa_con_sueldo_alto():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(6000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=True,
        regimen_empresa="general",
    )
    assert q2(d.renta_5ta) == Decimal("269.15")
    assert q2(d.neto_a_pagar) == Decimal("5049.16")
    # Asistencia completa (0 horas faltantes) -> asignación familiar íntegra,
    # sin prorrateo (100% de la proporción de asistencia = 100% del monto).
    assert q2(d.asignacion_familiar) == Decimal("113.00")
    # Fidelidad deliberada: la base de renta 5ta suma la asignación familiar
    # SIN verificar el régimen (a diferencia de asignacion_familiar, que sí lo
    # verifica) — inconsistencia ya presente en el TS original, se preserva.


# ── Caso F: quincena — solo vista, divide el sueldo a la mitad exacta ───────
def test_caso_f_quincena_divide_sueldo_a_la_mitad():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(3000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(88), meta_horas=Decimal(88),
        sistema_pension="afp", entidad_afp="habitat", tiene_asignacion_familiar=True,
        regimen_empresa="general", periodo_pago="q1",
        tipo_comision_afp="flujo",
    )
    assert q2(d.sueldo_periodo) == Decimal("1500.00")            # 3000 / 2, no prorrateo por días
    assert q2(d.asignacion_familiar) == Decimal("56.50")         # 113 / 2
    assert d.comision_afp_pct == Decimal("0.0147")               # tabla oficial Habitat
    assert q2(d.neto_a_pagar) == Decimal("1356.65")
    # valor_dia usa el sueldo MENSUAL completo, NO el de la quincena
    assert q2(d.valor_dia) == Decimal("100.00")                  # 3000/30, no 1500/30


# ── Caso G: descuento_tardanza_auto ya no tiene efecto monetario ───────────
def test_caso_g_descuento_tardanza_auto_es_no_op_bajo_el_modelo_proporcional():
    """Con el modelo corregido (sueldo devengado proporcional a la asistencia
    real), la tardanza YA queda reflejada en horas_faltantes/meta_horas — no
    hay un término aparte de 'minutos de tardanza × valor minuto' que este
    flag pudiera apagar. Se preserva el parámetro por compatibilidad de
    config (Empresa.descuento_tardanza_auto, Fase 1), pero debe dar el mismo
    resultado con True o False: si algún día deja de ser así, esta prueba
    avisa del cambio de contrato."""
    base_kwargs = dict(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(2), horas_reales=Decimal(174), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=False, regimen_empresa="general",
    )
    con_auto = calc(**base_kwargs, descuento_tardanza_auto=True)
    sin_auto = calc(**base_kwargs, descuento_tardanza_auto=False)

    assert con_auto.minutos_tardanza == sin_auto.minutos_tardanza == 120
    assert con_auto == sin_auto
    assert q2(con_auto.sueldo_devengado) == Decimal("1977.27")
    assert q2(con_auto.neto_a_pagar) == Decimal("1720.23")


# ── Defaults y validaciones puntuales ───────────────────────────────────────
def test_entidad_afp_no_definida_cae_a_integra():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(1000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="afp", entidad_afp=None, tiene_asignacion_familiar=False,
        regimen_empresa="general", tipo_comision_afp="flujo",
    )
    assert d.comision_afp_pct == Decimal("0.0155")               # tabla oficial Integra (default)


def test_calculo_es_puro_y_determinista():
    kwargs = dict(
        tipo_contrato="planilla", sueldo_base=Decimal(2500),
        horas_faltantes=Decimal(10), horas_reales=Decimal(180), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=True, regimen_empresa="general",
    )
    d1 = calc(**kwargs)
    d2 = calc(**kwargs)
    assert d1 == d2  # misma entrada -> mismo resultado, sin efectos de lado


@pytest.mark.parametrize("regimen", ["micro", "pequena", "general"])
def test_provision_vacaciones_siempre_positiva_para_dependiente(regimen):
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(1000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=False, regimen_empresa=regimen,
    )
    assert d.provision_vacaciones > Decimal(0)
    assert d.dias_vacaciones == (30 if regimen == "general" else 15)


# ── Caso K: fracción de hora extra menor a 1h — NO se paga (decisión de
# negocio explícita del usuario; el D.S. 007-2002-TR en realidad exige pagar
# la parte proporcional, pero aquí solo se paga la hora ya completada) ──────
def test_caso_k_fraccion_de_hora_extra_no_se_paga():
    """Escenario reportado: Harold trabajó 61.1h de una meta de 60.5h (0.6h de
    sobretiempo). Al no completar la hora, no se paga nada — pero el total
    trabajado (horas_extra) se sigue mostrando como informativo."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal("60.5") + Decimal("0.6"),
        meta_horas=Decimal("60.5"), sistema_pension="onp", regimen_empresa="general",
        # 0.6h de sobretiempo en el día: floor(0.6) = 0 → no cae en ningún tramo.
        horas_extra=Decimal("0.6"), horas_extra_25=Decimal(0), horas_extra_35=Decimal(0),
    )
    assert q2(d.horas_extra) == Decimal("0.60")          # informativo: sí trabajó 0.6h de más
    assert d.horas_extra_pagables == Decimal(0)           # pero no completó la hora
    assert q2(d.pago_horas_extra) == Decimal("0.00")


# ── Caso L: 2.6h extra — se pagan 2 horas completas al 25% ──────────────────
def test_caso_l_horas_extra_pagables_trunca_a_entero_tramo_25pct():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176) + Decimal("2.6"),
        meta_horas=Decimal(176), sistema_pension="onp", regimen_empresa="general",
        # 2.6h en el día: floor(2.6) = 2 → las 2 primeras horas, tramo 25%.
        horas_extra=Decimal("2.6"), horas_extra_25=Decimal(2), horas_extra_35=Decimal(0),
        pagar_horas_extra_sin_tramite=True,
    )
    assert d.horas_extra_pagables == Decimal(2)
    assert q2(d.pago_horas_extra) == Decimal("20.83")     # 2h × valor_hora(8.333) × 1.25


# ── Caso M: 3.9h extra — 2h al 25% + 1h al 35% (la fracción .9 no se paga) ──
def test_caso_m_horas_extra_pagables_tramo_25_y_35pct():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176) + Decimal("3.9"),
        meta_horas=Decimal(176), sistema_pension="onp", regimen_empresa="general",
        # 3.9h en el día: floor(3.9) = 3 → 2h al tramo 25%, 1h al tramo 35%.
        horas_extra=Decimal("3.9"), horas_extra_25=Decimal(2), horas_extra_35=Decimal(1),
        pagar_horas_extra_sin_tramite=True,
    )
    assert d.horas_extra_pagables == Decimal(3)
    assert q2(d.pago_horas_extra) == Decimal("32.08")     # 2h×1.25 + 1h×1.35, sobre valor_hora=8.333


# ── Caso N: alerta de horas extra sin trámite de Permanencia Extra ──────────
def test_caso_n_alerta_horas_extra_sin_tramite_no_reduce_el_pago():
    """3.15h trabajadas de más (3 pagables), solo 1h con trámite de
    Permanencia Extra aprobado. El pago sigue siendo por las 3h completas
    (SUNAFIL presume autorización tácita con el registro de asistencia) —
    la alerta es solo informativa, para que RRHH regularice el trámite."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176) + Decimal("3.15"),
        meta_horas=Decimal(176), sistema_pension="onp", regimen_empresa="general",
        horas_extra_aprobadas=Decimal(1),
        # 3.15h en el día: floor(3.15) = 3 → 2h@25% + 1h@35%. Empresa con el
        # gate en True (paga todo el sobretiempo registrado, el trámite es
        # solo alerta) — ver Caso "gate false" para el escenario contrario.
        horas_extra=Decimal("3.15"), horas_extra_25=Decimal(2), horas_extra_35=Decimal(1),
        pagar_horas_extra_sin_tramite=True,
    )
    assert d.horas_extra_pagables == Decimal(3)
    assert q2(d.pago_horas_extra) == Decimal("32.08")     # SIN reducir por falta de trámite
    assert d.horas_extra_sin_tramite == Decimal(2)         # alerta: 3 pagables - 1 aprobada


# ── Caso O: domingo trabajado, dependiente — retribución + sobretasa 100% ───
def test_caso_o_domingo_trabajado_dependiente_paga_doble():
    """D.Leg. 713 Art. 3: trabajar el día de descanso semanal sin sustituirlo
    da derecho a la retribución de la labor efectuada MÁS una sobretasa del
    100% — es decir, el doble del valor hora normal."""
    base_kwargs = dict(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
    )
    sin_domingo = calc(**base_kwargs)
    con_domingo = calc(**base_kwargs, horas_domingo=Decimal(8))

    assert q2(con_domingo.pago_domingo) == Decimal("133.33")   # 8h × 8.333 × 2
    # El pago de domingo entra a total_ingresos y a la base de pensión (es
    # remuneración computable real, no informativa como CTS/gratificación).
    assert q2(con_domingo.total_ingresos) == q2(sin_domingo.total_ingresos + con_domingo.pago_domingo)
    assert q2(con_domingo.base_pension) == q2(sin_domingo.base_pension + con_domingo.pago_domingo)
    # El neto SÍ sube frente al mismo caso sin domingo (aunque la pensión
    # también crezca al ampliarse la base imponible, el neto extra siempre
    # queda positivo porque ninguna tasa de pensión llega al 100%).
    assert con_domingo.neto_a_pagar > sin_domingo.neto_a_pagar


# ── Caso P: domingo trabajado, PRACTICANTE — tarifa simple (sin sobretasa) ──
def test_caso_p_domingo_trabajado_practicante_tarifa_simple():
    """Mismo criterio que horas extra: el practicante (Ley 28518, sin
    relación laboral) no tiene el beneficio de sobretasa del D.Leg. 713 —
    se le reconoce el trabajo de domingo a tarifa simple (1x), no doble."""
    d = calc(
        tipo_contrato="practicante", sueldo_base=Decimal(1200),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_domingo=Decimal(8),
    )
    assert q2(d.pago_domingo) == Decimal("40.00")          # 8h × 5.00 × 1 (SIN doblar)


# ── Caso Q: feriado trabajado, DEPENDIENTE — paga doble ─────────────────────
def test_caso_q_feriado_trabajado_dependiente_paga_doble():
    """D.Leg. 713 Art. 8/9: trabajar un feriado no laborable sin descanso
    sustitutorio da el mismo derecho que el domingo — retribución de la
    labor efectuada MÁS sobretasa del 100%."""
    base_kwargs = dict(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
    )
    sin_feriado = calc(**base_kwargs)
    con_feriado = calc(**base_kwargs, horas_feriado=Decimal(8))

    assert q2(con_feriado.pago_feriado) == Decimal("133.33")   # 8h × 8.333 × 2
    assert q2(con_feriado.total_ingresos) == q2(sin_feriado.total_ingresos + con_feriado.pago_feriado)
    assert q2(con_feriado.base_pension) == q2(sin_feriado.base_pension + con_feriado.pago_feriado)
    assert con_feriado.neto_a_pagar > sin_feriado.neto_a_pagar


# ── Caso R: feriado trabajado, PRACTICANTE — tarifa simple (sin sobretasa) ──
def test_caso_r_feriado_trabajado_practicante_tarifa_simple():
    d = calc(
        tipo_contrato="practicante", sueldo_base=Decimal(1200),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_feriado=Decimal(8),
    )
    assert q2(d.pago_feriado) == Decimal("40.00")          # 8h × 5.00 × 1 (SIN doblar)


# ── Caso S: domingo y feriado no se suman doble cuando coinciden ────────────
def test_caso_s_domingo_y_feriado_no_se_solapan():
    """planilla_asistencia_service excluye del cómputo de horas_feriado los
    feriados que caen en domingo (ya cubiertos por horas_domingo) — el motor
    de cálculo en sí no deduplica, así que esta prueba fija el contrato: si
    ambos insumos llegan con horas > 0, cada uno se paga por separado (la
    deduplicación es responsabilidad de la capa de asistencia, no de este
    motor puro)."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_domingo=Decimal(8), horas_feriado=Decimal(8),
    )
    assert q2(d.pago_domingo) == Decimal("133.33")
    assert q2(d.pago_feriado) == Decimal("133.33")


# ── FIX 2026-07-07 — Comisión AFP por esquema (flujo vs saldo) ──────────────
def test_comision_afp_saldo_no_se_descuenta():
    """'saldo' es el default legal desde 2013: la comisión SPP (~0.78% anual
    sobre el FONDO acumulado) la cobra la AFP directamente del fondo, nunca
    de la remuneración — en planilla debe salir en 0."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(1000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="afp", entidad_afp="integra", tiene_asignacion_familiar=False,
        regimen_empresa="general", tipo_comision_afp="saldo",
    )
    assert d.comision_afp_pct == Decimal("0")
    assert q2(d.afp_comision) == Decimal("0.00")
    assert q2(d.descuento_pension) == Decimal("113.70")   # base × (10% + 1.37% + 0%) = 11.37%


def test_comision_afp_flujo_se_descuenta():
    """'flujo' es el esquema anterior (aún vigente para quienes no
    migraron): la comisión SÍ se descuenta cada mes sobre la remuneración."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(1000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="afp", entidad_afp="integra", tiene_asignacion_familiar=False,
        regimen_empresa="general", tipo_comision_afp="flujo",
    )
    assert d.comision_afp_pct == Decimal("0.0155")
    assert q2(d.afp_comision) == Decimal("15.50")          # 1.55% de 1000
    assert q2(d.descuento_pension) == Decimal("129.20")    # base × (10% + 1.37% + 1.55%) = 12.92%


# ── FIX 2026-07-07 — Hora extra por DÍA, no por acumulación de período ─────
def test_horas_extra_por_dia_suma_buckets_sin_recalcular_desde_periodo():
    """Escenario de referencia: día 1 con 1h de sobretiempo (floor(1)=1 → va
    al tramo 25%) y día 2 con 5h de sobretiempo (floor(5)=5 → 2h al tramo
    25%, 3h al tramo 35%). El AGREGADO por período es extra_25=1+2=3,
    extra_35=0+3=3 — el motor solo suma los buckets ya resueltos por
    `resumen_horas_periodo`, no vuelve a derivar nada de horas_reales/meta."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_extra_25=Decimal(3), horas_extra_35=Decimal(3),
        pagar_horas_extra_sin_tramite=True,
    )
    assert d.horas_extra_pagables == Decimal(6)
    assert q2(d.pago_horas_extra) == Decimal("65.00")     # 3×8.333×1.25 + 3×8.333×1.35


def test_falta_de_un_dia_no_cancela_extra_de_otro_dia():
    """Antes (acumulación de período): un día corto y un día largo se
    NETEABAN entre sí (horas_extra = max(0, total - meta)), así que una
    falta podía anular el sobretiempo de otro día del mismo período. Ahora
    (2026-07-07) ambos vienen ya agregados por separado desde
    `resumen_horas_periodo` — la falta SIGUE descontando el sueldo Y el
    extra SIGUE pagándose completo, sin compensarse entre sí."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(2), horas_reales=Decimal(174), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_extra_25=Decimal(2), horas_extra_35=Decimal(0),
        pagar_horas_extra_sin_tramite=True,
    )
    assert q2(d.sueldo_devengado) == Decimal("1977.27")   # la falta de 2h SÍ se descuenta
    assert q2(d.pago_horas_extra) == Decimal("20.83")     # Y el extra de 2h SÍ se paga completo


# ── FIX 2026-07-07 — Gate de pago de sobretiempo sin trámite (por empresa) ──
def test_gate_false_sin_tramite_no_paga():
    """Empresa con `pagar_horas_extra_sin_tramite=False` (default, más
    conservador legalmente): sin trámite de Permanencia Extra aprobado, el
    sobretiempo NO se paga — pero la alerta informativa SIEMPRE se calcula."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_extra_25=Decimal(2), horas_extra_35=Decimal(0),
        pagar_horas_extra_sin_tramite=False,
    )
    assert q2(d.pago_horas_extra) == Decimal("0.00")
    assert d.horas_extra_sin_tramite == Decimal(2)


def test_gate_true_sin_tramite_paga_completo():
    """Mismo escenario que el anterior, pero con
    `pagar_horas_extra_sin_tramite=True`: se paga TODO el sobretiempo
    registrado (presunción de autorización tácita, SUNAFIL); la alerta sigue
    apareciendo igual, es puramente informativa."""
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(0), horas_reales=Decimal(176), meta_horas=Decimal(176),
        sistema_pension="onp", regimen_empresa="general",
        horas_extra_25=Decimal(2), horas_extra_35=Decimal(0),
        pagar_horas_extra_sin_tramite=True,
    )
    assert q2(d.pago_horas_extra) == Decimal("20.83")
    assert d.horas_extra_sin_tramite == Decimal(2)


# ── FIX 2026-07-08 — Consistencia de la Boleta de Pago (PDF) ────────────────
# La boleta agrupa los conceptos en 3 bloques que DEBEN cuadrar fila por fila
# con su subtotal; si esto se rompe, el documento muestra un "TOTAL" que no
# coincide con lo listado (bug reportado: las inasistencias aparecían en
# "Descuentos" pero el total de descuentos no las incluía). Este test fija las
# 4 identidades de las que depende la plantilla `construirVoucherHtml`.
def _assert_boleta_cuadra(d) -> None:
    # Bloque A — Ajustes: Remuneración Básica − Inasistencias = Computable.
    assert d.sueldo_devengado == d.sueldo_periodo - d.descuento_faltas
    # Bloque B — Ingresos: las filas suman EXACTO el Total Remuneración Bruta.
    assert d.total_ingresos == (
        d.sueldo_devengado + d.pago_horas_extra + d.asignacion_familiar
        + d.pago_domingo + d.pago_feriado
    )
    # Bloque C — Descuentos: SOLO pensión + renta (las inasistencias NO van
    # aquí, ya se restaron en el bloque de Ajustes).
    assert d.total_descuentos_legales == d.descuento_pension + d.renta_5ta
    # AFP: el desglose de 3 componentes suma el descuento total de pensión.
    if d.es_afp:
        assert q2(d.afp_aporte_obligatorio + d.afp_prima_seguro + d.afp_comision) == q2(d.descuento_pension)
    # Resumen de Liquidación: Neto = Bruta − Descuentos (piso 0).
    if d.sueldo_periodo > Decimal(0):
        assert d.neto_a_pagar == max(Decimal(0), d.total_ingresos - d.total_descuentos_legales)


def test_boleta_cuadra_dependiente_onp_con_faltas_y_extras():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(2500),
        horas_faltantes=Decimal(10), horas_reales=Decimal(180), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=True, regimen_empresa="general",
        horas_extra=Decimal(4), horas_extra_25=Decimal(2), horas_extra_35=Decimal(2),
        pagar_horas_extra_sin_tramite=True,
    )
    _assert_boleta_cuadra(d)


def test_boleta_cuadra_afp_flujo_con_domingo_y_feriado():
    d = calc(
        tipo_contrato="planilla", sueldo_base=Decimal(3000),
        horas_faltantes=Decimal(6), horas_reales=Decimal(170), meta_horas=Decimal(176),
        sistema_pension="afp", entidad_afp="prima", tipo_comision_afp="flujo",
        tiene_asignacion_familiar=True, regimen_empresa="general",
        horas_domingo=Decimal(8), horas_feriado=Decimal(8),
    )
    _assert_boleta_cuadra(d)


def test_boleta_cuadra_practicante_y_bajo_rmv_y_quincena():
    for kw in (
        dict(tipo_contrato="practicante", sueldo_base=Decimal(1200), regimen_empresa="general"),
        dict(tipo_contrato="planilla", sueldo_base=Decimal(900), regimen_empresa="micro"),
        dict(tipo_contrato="planilla", sueldo_base=Decimal(6000), tiene_asignacion_familiar=True,
             regimen_empresa="general", periodo_pago="q1"),
    ):
        d = calc(
            horas_faltantes=Decimal(4), horas_reales=Decimal(172), meta_horas=Decimal(176),
            sistema_pension="onp", **kw,
        )
        _assert_boleta_cuadra(d)
