"""
Pruebas de `resumen_horas_periodo` con `incluir_detalle_dias=True` (Fase 9 —
modal "Ver asistencia" de Planilla).

A diferencia de `test_planilla_calculo_service.py` (motor puro, sin BD), esta
función SÍ necesita base de datos (turnos, marcaciones, solicitudes). Se usa
un SQLite en memoria con solo las tablas necesarias — no se toca Postgres.

El objetivo central: garantizar que el detalle día-por-día NUNCA contradiga
los totales que ya usa la boleta (`totales.horas_faltantes` debe ser
EXACTAMENTE `sum(detalle_dias[].falta)`, redondeado igual — y lo mismo para
extra_25/extra_35). Si esto se rompe, el modal mentiría sobre de dónde salen
los números de la boleta.

Ejecutar:  cd BACKEND && pytest tests/test_planilla_asistencia_service.py -v
"""
import importlib
import pkgutil
from datetime import date, datetime, time

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import app.models as _models_pkg
from app.db.database import Base
from app.models.empresa import Empresa
from app.models.usuario import Usuario
from app.models.empleado import Empleado
from app.models.turno import Turno, TurnoEmpleado
from app.models.registro_asistencia import RegistroAsistencia
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.documento_laboral import DocumentoLaboral
from app.models.area import Area
from app.models.geolocalizacion_asistencia import GeolocalizacionAsistencia
from app.models.feriado_empresa import FeriadoEmpresa

from app.services.planilla_asistencia_service import resumen_horas_periodo

# Importa TODOS los módulos de app.models — no para crearlos en el SQLite de
# prueba, solo para que sus Table queden registradas en Base.metadata: Area
# tiene FKs a ubicacion/zona (jerarquía física), y sin esos módulos importados
# SQLAlchemy no puede resolver la cadena de FKs al armar `create_all(tables=[...])`
# aunque esas tablas no se vayan a crear.
for _mod in pkgutil.iter_modules(_models_pkg.__path__):
    importlib.import_module(f"app.models.{_mod.name}")


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine, tables=[
        Empresa.__table__, Usuario.__table__, Empleado.__table__,
        Turno.__table__, TurnoEmpleado.__table__, RegistroAsistencia.__table__,
        SolicitudLaboral.__table__, DocumentoLaboral.__table__, Area.__table__,
        GeolocalizacionAsistencia.__table__, FeriadoEmpresa.__table__,
    ])
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def _reg(empresa_id, empleado_id, tipo, dia: date, hh: int, mm: int = 0) -> RegistroAsistencia:
    return RegistroAsistencia(
        empresa_id=empresa_id, empleado_id=empleado_id, tipo=tipo,
        fecha_hora=datetime(dia.year, dia.month, dia.day, hh, mm),
        estado="validado",
    )


def _setup_empleado_con_turno(db, *, dias_laborales="1,2,3,4,5", tipo_contrato="planilla"):
    """Empresa + Usuario + Empleado + Turno L-V 08:00-17:00 (8h netas, 1h de
    almuerzo) vigente desde 2026-01-01. Devuelve (empresa_id, empleado_id)."""
    empresa = Empresa(
        razon_social="Test SAC", ruc="20123456789", email_contacto="x@test.com",
        slug="test-sac", estado="activo",
    )
    usuario = Usuario(
        id="usr-1", empresa_id="emp-1", nombre="Harold", apellido="Ortiz",
        username="harold", email="harold@test.com", password_hash="x",
    )
    db.add_all([empresa, usuario])
    db.commit()

    empleado = Empleado(
        id="emp-empleado-1", usuario_id=usuario.id, empresa_id=empresa.id,
        cargo="Técnico", tipo=tipo_contrato, fecha_ingreso=date(2026, 1, 1),
    )
    turno = Turno(
        empresa_id=empresa.id, nombre="Turno Oficina", hora_entrada=time(8, 0),
        hora_salida=time(17, 0), duracion_almuerzo_minutos=60, dias_laborales=dias_laborales,
    )
    db.add_all([empleado, turno])
    db.commit()

    turno_emp = TurnoEmpleado(
        empleado_id=empleado.id, turno_id=turno.id, fecha_desde=date(2026, 1, 1),
    )
    db.add(turno_emp)
    db.commit()

    return empresa.id, empleado.id


def test_detalle_dias_reconcilia_exacto_con_los_totales(db):
    """Semana 2026-06-01 (lunes) a 2026-06-07 (domingo), con un día de cada
    escenario: hora extra (25%/35%), marcación incompleta (falta inflada),
    falta parcial por almuerzo excedido, día perfecto, sábado fuera de turno
    y domingo sin marcar."""
    empresa_id, empleado_id = _setup_empleado_con_turno(db)

    registros = [
        # Lunes 6/1: entrada 08:00, salida 19:00, SIN marcar almuerzo -> 11h
        # crudas sin descuento -> 3h de sobretiempo (2h@25% + 1h@35%).
        _reg(empresa_id, empleado_id, "entrada", date(2026, 6, 1), 8, 0),
        _reg(empresa_id, empleado_id, "salida",  date(2026, 6, 1), 19, 0),
        # Martes 6/2: entrada sin salida -> _horas_dia da 0h -> falta 8h
        # completa (marcación incompleta, NO error de asistencia real).
        _reg(empresa_id, empleado_id, "entrada", date(2026, 6, 2), 8, 0),
        # Miércoles 6/3: sin ningún registro -> falta 8h.
        # Jueves 6/4: jornada con almuerzo de 1h, sale 1h antes -> falta 1h.
        _reg(empresa_id, empleado_id, "entrada",          date(2026, 6, 4), 8, 0),
        _reg(empresa_id, empleado_id, "entrada_almuerzo", date(2026, 6, 4), 12, 0),
        _reg(empresa_id, empleado_id, "salida_almuerzo",  date(2026, 6, 4), 13, 0),
        _reg(empresa_id, empleado_id, "salida",           date(2026, 6, 4), 16, 0),
        # Viernes 6/5: jornada perfecta de 8h netas (9h - 1h de almuerzo).
        _reg(empresa_id, empleado_id, "entrada",          date(2026, 6, 5), 8, 0),
        _reg(empresa_id, empleado_id, "entrada_almuerzo", date(2026, 6, 5), 12, 0),
        _reg(empresa_id, empleado_id, "salida_almuerzo",  date(2026, 6, 5), 13, 0),
        _reg(empresa_id, empleado_id, "salida",           date(2026, 6, 5), 17, 0),
        # Sábado 6/6 (fuera de turno L-V) y domingo 6/7: sin registros.
    ]
    db.add_all(registros)
    db.commit()

    filas = resumen_horas_periodo(
        db, empresa_id, date(2026, 6, 1), date(2026, 6, 7), incluir_detalle_dias=True,
    )
    assert len(filas) == 1
    fila = filas[0]

    # ── Totales esperados (calculados a mano, ver docstring del caso) ──────
    assert fila["meta_horas"]      == 40.0   # 5 días laborables x 8h (sábado y domingo no meten meta)
    assert fila["horas_faltantes"] == 17.0   # 0 + 8 + 8 + 1 + 0
    assert fila["horas_extra"]     == 3.0    # solo el lunes
    assert fila["horas_extra_25"]  == 2.0
    assert fila["horas_extra_35"]  == 1.0
    assert fila["horas_domingo"]   == 0.0
    assert fila["horas_feriado"]   == 0.0

    detalle = fila["detalle_dias"]
    assert len(detalle) == 7   # un día por cada fecha del rango, sin excepción

    por_fecha = {d["fecha"]: d for d in detalle}
    assert por_fecha[date(2026, 6, 1)]["tipo_dia"] == "laborable"
    assert por_fecha[date(2026, 6, 1)]["extra_25"] == 2.0
    assert por_fecha[date(2026, 6, 1)]["extra_35"] == 1.0
    assert por_fecha[date(2026, 6, 2)]["falta"] == 8.0
    assert por_fecha[date(2026, 6, 2)]["alerta"] == "marcacion_incompleta"
    assert por_fecha[date(2026, 6, 3)]["falta"] == 8.0
    assert por_fecha[date(2026, 6, 3)]["alerta"] is None
    assert por_fecha[date(2026, 6, 4)]["falta"] == 1.0
    assert por_fecha[date(2026, 6, 5)]["falta"] == 0.0
    assert por_fecha[date(2026, 6, 6)]["tipo_dia"] == "no_laborable_turno"
    assert por_fecha[date(2026, 6, 7)]["tipo_dia"] == "domingo"

    # ── LA garantía central: el detalle SIEMPRE reconcilia con los totales ──
    assert round(sum(d["falta"] for d in detalle), 2)             == fila["horas_faltantes"]
    assert round(sum(d["horas_extra_bruto"] for d in detalle), 2) == fila["horas_extra"]
    assert round(sum(d["extra_25"] for d in detalle), 2)          == fila["horas_extra_25"]
    assert round(sum(d["extra_35"] for d in detalle), 2)          == fila["horas_extra_35"]


def test_sin_incluir_detalle_dias_no_arma_el_detalle(db):
    """Default `incluir_detalle_dias=False` (usado por /rrhh/asistencia/resumen
    y /planilla/preview): los totales deben salir IDÉNTICOS, pero sin el
    costo de armar detalle_dias ni consultar geolocalización."""
    empresa_id, empleado_id = _setup_empleado_con_turno(db)
    db.add_all([
        _reg(empresa_id, empleado_id, "entrada", date(2026, 6, 1), 8, 0),
        _reg(empresa_id, empleado_id, "salida",  date(2026, 6, 1), 19, 0),
    ])
    db.commit()

    filas = resumen_horas_periodo(db, empresa_id, date(2026, 6, 1), date(2026, 6, 7))
    assert filas[0]["detalle_dias"] == []
    assert filas[0]["horas_extra"] == 3.0
    assert filas[0]["horas_extra_25"] == 2.0
    assert filas[0]["horas_extra_35"] == 1.0


def test_marcacion_incompleta_no_pisa_alerta_sin_geolocalizacion(db):
    """Marcación sin coordenadas registradas: lat/lng deben salir None, sin
    romper la construcción del detalle (RegistroAsistencia no tiene columnas
    de geolocalización propias; vienen de GeolocalizacionAsistencia aparte)."""
    empresa_id, empleado_id = _setup_empleado_con_turno(db)
    db.add_all([
        _reg(empresa_id, empleado_id, "entrada", date(2026, 6, 5), 8, 0),
        _reg(empresa_id, empleado_id, "salida",  date(2026, 6, 5), 17, 0),
    ])
    db.commit()

    filas = resumen_horas_periodo(
        db, empresa_id, date(2026, 6, 5), date(2026, 6, 5), incluir_detalle_dias=True,
    )
    dia = filas[0]["detalle_dias"][0]
    assert dia["marcaciones"]["entrada"]["lat"] is None
    assert dia["marcaciones"]["entrada"]["lng"] is None
    assert dia["marcaciones"]["entrada"]["hora"] is not None
