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
    assert d.dias_faltantes == 1
    assert d.minutos_tardanza == 120
    assert q2(d.descuento_dominical) == Decimal("2.78")
    assert q2(d.descuento_faltas) == Decimal("106.94")
    assert d.horas_extra == Decimal(4)
    assert q2(d.pago_horas_extra) == Decimal("54.17")          # 2h@25% + 2h@35%
    assert q2(d.asignacion_familiar) == Decimal("113.00")       # 10% RMV, régimen general
    assert d.es_afp is False
    assert q2(d.base_pension) == Decimal("2560.22")
    assert q2(d.descuento_pension) == Decimal("332.83")         # ONP 13% plano
    assert q2(d.afp_aporte_obligatorio) == Decimal("0.00")
    assert d.renta_5ta == Decimal(0)                            # no supera las 7 UIT de deducción
    assert q2(d.total_ingresos) == Decimal("2667.17")
    assert q2(d.total_descuentos_legales) == Decimal("439.77")
    assert q2(d.neto_a_pagar) == Decimal("2227.39")
    # Informativos: NO deben tocar el neto ni los ingresos
    assert q2(d.aporte_essalud) == Decimal("225.00")
    assert q2(d.provision_cts) == Decimal("208.33")
    assert q2(d.provision_gratificacion) == Decimal("416.67")
    assert q2(d.provision_vacaciones) == Decimal("208.33")
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
    # Tarifa simple en horas faltantes (sin recargo), pero SÍ hay descuento por faltas
    assert q2(d.descuento_faltas) == Decimal("20.00")
    # Fidelidad deliberada: EsSalud se calcula IGUAL para practicantes (no
    # condicionado por es_dependiente en el original) — no es un bug, se copia tal cual.
    assert q2(d.aporte_essalud) == Decimal("108.00")
    assert q2(d.neto_a_pagar) == Decimal("1180.00")


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


# ── Caso G: descuento_tardanza_auto = False tiene efecto real ──────────────
def test_caso_g_descuento_tardanza_auto_desactivado():
    base_kwargs = dict(
        tipo_contrato="planilla", sueldo_base=Decimal(2000),
        horas_faltantes=Decimal(2), horas_reales=Decimal(174), meta_horas=Decimal(176),
        sistema_pension="onp", tiene_asignacion_familiar=False, regimen_empresa="general",
    )
    con_auto = calc(**base_kwargs, descuento_tardanza_auto=True)
    sin_auto = calc(**base_kwargs, descuento_tardanza_auto=False)

    assert con_auto.minutos_tardanza == sin_auto.minutos_tardanza == 120
    # Con el descuento automático activo, la tardanza SÍ se descuenta
    assert q2(con_auto.descuento_faltas) == Decimal("16.67")
    # Desactivado, el término de tardanza se omite (día completo y dominical
    # igual dan 0 porque con 2h faltantes no hay ningún día completo perdido)
    assert q2(sin_auto.descuento_faltas) == Decimal("0.00")


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
