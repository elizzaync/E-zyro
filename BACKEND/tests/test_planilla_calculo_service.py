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
    config_keys = {"regimen_empresa", "periodo_pago", "descuento_tardanza_auto"}
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
        regimen_empresa="general",
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
