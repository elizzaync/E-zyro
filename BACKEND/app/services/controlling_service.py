"""
Servicio de controlling / centros de costo (Fase 2).

SOLO LECTURA sobre el libro mayor: agrega las líneas de asiento imputadas a
un centro de costo. NUNCA genera ni modifica asientos — no importa
`registrar_asiento` a propósito (la imputación la pone el módulo de origen al
crear el asiento en la Fase 1; aquí solo se consulta).

Todos los montos en Decimal.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date
from decimal import Decimal

from sqlalchemy import case, func
from sqlalchemy.orm import Session

from app.models.contabilidad import AsientoContable, AsientoLinea, CentroCosto

CERO = Decimal("0.00")
# Convención de planilla: valor_día = sueldo_base/30 → valor_hora = sueldo_base/240 (jornada 8h)
HORAS_MES = Decimal("240")


def _d(valor) -> Decimal:
    return Decimal(str(valor if valor is not None else 0)).quantize(Decimal("0.01"))


def costo_real_por_centro(
    db: Session, empresa_id: str, centro_costo_id: str,
    periodo_desde: date | None = None, periodo_hasta: date | None = None,
) -> dict:
    """Agrega débitos y créditos de todas las líneas imputadas a un centro.

    `costo_real` = SUM(debito) - SUM(credito): para un centro que acumula
    gastos (lo habitual) el resultado es positivo y representa el costo neto
    cargado al centro en el rango de fechas.
    """
    q = (
        db.query(
            func.coalesce(func.sum(AsientoLinea.debito), 0),
            func.coalesce(func.sum(AsientoLinea.credito), 0),
        )
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(
            AsientoContable.empresa_id == empresa_id,
            AsientoLinea.centro_costo_id == centro_costo_id,
        )
    )
    if periodo_desde:
        q = q.filter(AsientoContable.fecha >= periodo_desde)
    if periodo_hasta:
        q = q.filter(AsientoContable.fecha <= periodo_hasta)
    deb, cre = q.first()
    deb, cre = _d(deb), _d(cre)
    return {
        "centro_costo_id": centro_costo_id,
        "total_debito": deb,
        "total_credito": cre,
        "costo_real": deb - cre,
    }


def comparativo_presupuesto_vs_real(
    db: Session, empresa_id: str, centro_costo_id: str,
    periodo_desde: date | None = None, periodo_hasta: date | None = None,
) -> dict:
    """Cruza el presupuesto referencial del centro contra su costo real."""
    cc = (
        db.query(CentroCosto)
        .filter(CentroCosto.id == centro_costo_id, CentroCosto.empresa_id == empresa_id)
        .first()
    )
    if cc is None:
        return {}
    real = costo_real_por_centro(db, empresa_id, centro_costo_id, periodo_desde, periodo_hasta)
    presupuesto = _d(cc.presupuesto_referencial) if cc.presupuesto_referencial is not None else None
    costo_real = real["costo_real"]
    desviacion = (costo_real - presupuesto) if presupuesto is not None else None
    return {
        "centro_costo_id": centro_costo_id,
        "codigo": cc.codigo,
        "nombre": cc.nombre,
        "presupuesto_referencial": presupuesto,
        "costo_real": costo_real,
        "desviacion": desviacion,  # >0: sobre-ejecutado; <0: bajo presupuesto
        "ejecucion_pct": (
            (costo_real / presupuesto * Decimal("100")).quantize(Decimal("0.01"))
            if presupuesto and presupuesto != CERO else None
        ),
    }


# ── Rentabilidad por proyecto ────────────────────────────────────────────────
# Cruce SOLO LECTURA de tres fuentes que ya existen:
#   ingresos  = facturas del proyecto (CxC, sin IGV; notas de crédito restan)
#   costos    = líneas de asiento imputadas a centros de costo del proyecto
#   mano_obra = horas de asistencia en el proyecto × valor-hora del sueldo base
# La mano de obra es ESTIMADA (misma convención que planilla: sueldo_base/240);
# se reporta aparte de los costos imputados para no ocultar doble conteo si la
# empresa además imputa planilla al centro del proyecto.


def _horas_jornada(registros: list) -> Decimal:
    """Horas de una jornada a partir de sus registros [(tipo, fecha_hora), ...].

    entrada→salida menos el intervalo de almuerzo si ambos extremos existen.
    Sin par entrada/salida completo la jornada no suma (misma regla que el
    resumen diario de asistencia).
    """
    t = {tipo: fh for tipo, fh in registros}  # último registro de cada tipo gana
    entrada, salida = t.get("entrada"), t.get("salida")
    if not entrada or not salida or salida <= entrada:
        return CERO
    segundos = (salida - entrada).total_seconds()
    ini_alm, fin_alm = t.get("entrada_almuerzo"), t.get("salida_almuerzo")
    if ini_alm and fin_alm and fin_alm > ini_alm:
        segundos -= (fin_alm - ini_alm).total_seconds()
    return _d(Decimal(segundos) / Decimal(3600))


def _ingresos_por_proyecto(
    db: Session, empresa_id: str,
    desde: date | None, hasta: date | None,
) -> dict[str, Decimal]:
    """proyecto_id → ingresos netos (subtotal sin IGV; notas de crédito restan)."""
    from app.models.cuentas_por_cobrar import FacturaCliente

    signo = case(
        (FacturaCliente.tipo_documento == "nota_credito", -FacturaCliente.subtotal),
        else_=FacturaCliente.subtotal,
    )
    q = (
        db.query(FacturaCliente.proyecto_id, func.coalesce(func.sum(signo), 0))
        .filter(
            FacturaCliente.empresa_id == empresa_id,
            FacturaCliente.proyecto_id.isnot(None),
            FacturaCliente.estado != "anulada",
        )
    )
    if desde:
        q = q.filter(FacturaCliente.fecha_emision >= desde)
    if hasta:
        q = q.filter(FacturaCliente.fecha_emision <= hasta)
    return {str(pid): _d(total) for pid, total in q.group_by(FacturaCliente.proyecto_id)}


def _costos_por_proyecto(
    db: Session, empresa_id: str,
    desde: date | None, hasta: date | None,
) -> tuple[dict[str, Decimal], dict[str, list[dict]]]:
    """(proyecto_id → costo neto, proyecto_id → desglose por centro)."""
    q = (
        db.query(
            CentroCosto.referencia_id, CentroCosto.id,
            CentroCosto.codigo, CentroCosto.nombre,
            func.coalesce(func.sum(AsientoLinea.debito), 0),
            func.coalesce(func.sum(AsientoLinea.credito), 0),
        )
        .join(AsientoLinea, AsientoLinea.centro_costo_id == CentroCosto.id)
        .join(AsientoContable, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(
            CentroCosto.empresa_id == empresa_id,
            CentroCosto.tipo_referencia == "proyecto",
            CentroCosto.referencia_id.isnot(None),
            AsientoContable.empresa_id == empresa_id,
        )
    )
    if desde:
        q = q.filter(AsientoContable.fecha >= desde)
    if hasta:
        q = q.filter(AsientoContable.fecha <= hasta)
    q = q.group_by(CentroCosto.referencia_id, CentroCosto.id,
                   CentroCosto.codigo, CentroCosto.nombre)

    totales: dict[str, Decimal] = defaultdict(lambda: CERO)
    desglose: dict[str, list[dict]] = defaultdict(list)
    for ref_id, cc_id, codigo, nombre, deb, cre in q:
        costo = _d(deb) - _d(cre)
        pid = str(ref_id)
        totales[pid] += costo
        desglose[pid].append({
            "centro_costo_id": str(cc_id), "codigo": codigo,
            "nombre": nombre, "costo_real": costo,
        })
    return dict(totales), dict(desglose)


def _mano_obra_por_proyecto(
    db: Session, empresa_id: str,
    desde: date | None, hasta: date | None,
) -> tuple[dict[str, dict], dict[str, list[dict]]]:
    """(proyecto_id → {horas, costo}, proyecto_id → desglose por empleado).

    Sin concepto base configurado el costo es 0 pero las horas sí se reportan
    (misma regla que planilla: sin base no hay montos automáticos).
    """
    from sqlalchemy import cast, Date

    from app.models.planilla import ConceptoRemunerativo, EmpleadoConcepto
    from app.models.registro_asistencia import RegistroAsistencia
    from app.models.empleado import Empleado
    from app.models.usuario import Usuario

    q = (
        db.query(RegistroAsistencia)
        .filter(
            RegistroAsistencia.empresa_id == empresa_id,
            RegistroAsistencia.proyecto_id.isnot(None),
        )
    )
    if desde:
        q = q.filter(cast(RegistroAsistencia.fecha_hora, Date) >= desde)
    if hasta:
        q = q.filter(cast(RegistroAsistencia.fecha_hora, Date) <= hasta)
    registros = q.order_by(RegistroAsistencia.fecha_hora).all()
    if not registros:
        return {}, {}

    # ponytail: pareo en Python, O(n) sobre los registros del rango; si el
    # volumen crece, mover el pareo a SQL con window functions.
    jornadas: dict[tuple, list] = defaultdict(list)  # (pid, emp, día) → [(tipo, fh)]
    for r in registros:
        jornadas[(str(r.proyecto_id), str(r.empleado_id), r.fecha_hora.date())].append(
            (r.tipo, r.fecha_hora))

    horas_emp: dict[tuple, Decimal] = defaultdict(lambda: CERO)  # (pid, emp) → horas
    for (pid, emp, _dia), regs in jornadas.items():
        horas_emp[(pid, emp)] += _horas_jornada(regs)

    base = (
        db.query(ConceptoRemunerativo)
        .filter(
            ConceptoRemunerativo.empresa_id == empresa_id,
            ConceptoRemunerativo.es_base == "true",
            ConceptoRemunerativo.activo == "true",
        )
        .first()
    )
    sueldos: dict[str, Decimal] = {}
    if base is not None:
        sueldos = {
            str(ec.empleado_id): _d(ec.monto)
            for ec in db.query(EmpleadoConcepto).filter(
                EmpleadoConcepto.empresa_id == empresa_id,
                EmpleadoConcepto.concepto_id == base.id,
            )
        }
    sueldo_ref = _d(base.monto_referencial) if base is not None and base.monto_referencial else CERO

    nombres = {
        str(e.id): f"{u.nombre} {u.apellido}"
        for e, u in db.query(Empleado, Usuario)
        .join(Usuario, Empleado.usuario_id == Usuario.id)
        .filter(Empleado.empresa_id == empresa_id)
    }

    totales: dict[str, dict] = defaultdict(lambda: {"horas": CERO, "costo": CERO})
    desglose: dict[str, list[dict]] = defaultdict(list)
    for (pid, emp), horas in horas_emp.items():
        if horas == CERO:
            continue
        valor_hora = sueldos.get(emp, sueldo_ref) / HORAS_MES
        costo = _d(horas * valor_hora)
        totales[pid]["horas"] += horas
        totales[pid]["costo"] += costo
        desglose[pid].append({
            "empleado_id": emp,
            "nombre": nombres.get(emp, emp),
            "horas": horas,
            "costo": costo,
        })
    return dict(totales), dict(desglose)


def rentabilidad_proyectos(
    db: Session, empresa_id: str,
    desde: date | None = None, hasta: date | None = None,
    proyecto_id: str | None = None,
) -> list[dict]:
    """Resumen de rentabilidad por proyecto: ingresos − costos − mano de obra.

    Con `proyecto_id` devuelve solo ese proyecto e incluye los desgloses por
    centro de costo y por empleado.
    """
    from app.models.cliente import Cliente
    from app.models.proyecto import Proyecto

    q = (
        db.query(Proyecto, Cliente.razon_social)
        .join(Cliente, Proyecto.cliente_id == Cliente.id)
        .filter(Proyecto.empresa_id == empresa_id)
    )
    if proyecto_id:
        q = q.filter(Proyecto.id == proyecto_id)
    proyectos = q.order_by(Proyecto.created_at.desc()).all()
    if not proyectos:
        return []

    ingresos = _ingresos_por_proyecto(db, empresa_id, desde, hasta)
    costos, desg_centros = _costos_por_proyecto(db, empresa_id, desde, hasta)
    mano_obra, desg_emps = _mano_obra_por_proyecto(db, empresa_id, desde, hasta)

    filas = []
    for p, razon_social in proyectos:
        pid = str(p.id)
        ing = ingresos.get(pid, CERO)
        cos = costos.get(pid, CERO)
        mo = mano_obra.get(pid, {"horas": CERO, "costo": CERO})
        margen = ing - cos - mo["costo"]
        fila = {
            "proyecto_id": pid,
            "nombre_proyecto": p.nombre_proyecto,
            "cliente_id": str(p.cliente_id),
            "cliente": razon_social,
            "estado": p.estado,
            "ingresos": ing,
            "costos_imputados": cos,
            "mano_obra": mo["costo"],
            "horas_mano_obra": mo["horas"],
            "margen": margen,
            "margen_pct": (
                (margen / ing * Decimal("100")).quantize(Decimal("0.01"))
                if ing != CERO else None
            ),
        }
        if proyecto_id:
            fila["centros"] = desg_centros.get(pid, [])
            fila["empleados"] = desg_emps.get(pid, [])
        filas.append(fila)
    return filas


if __name__ == "__main__":  # self-check del pareo de horas (sin DB)
    from datetime import datetime as _dt

    _e = _dt(2026, 7, 1, 8, 0)
    _sa = _dt(2026, 7, 1, 13, 0)
    _fa = _dt(2026, 7, 1, 14, 0)
    _s = _dt(2026, 7, 1, 18, 0)
    assert _horas_jornada([("entrada", _e), ("salida", _s)]) == Decimal("10.00")
    assert _horas_jornada([
        ("entrada", _e), ("entrada_almuerzo", _sa),
        ("salida_almuerzo", _fa), ("salida", _s),
    ]) == Decimal("9.00")
    assert _horas_jornada([("entrada", _e)]) == CERO            # jornada incompleta
    assert _horas_jornada([("salida", _e), ("entrada", _s)]) == CERO  # salida antes de entrada
    assert _horas_jornada([("entrada", _e), ("entrada_almuerzo", _sa), ("salida", _s)]) == Decimal("10.00")
    print("OK: _horas_jornada")
