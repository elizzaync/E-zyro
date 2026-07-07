"""Schemas del módulo de planilla (Fase 8)."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, field_validator

TIPOS_CONCEPTO = {"ingreso", "descuento", "aporte_empleador"}


class ConceptoCreate(BaseModel):
    codigo: str
    nombre: str
    tipo: str
    monto_referencial: Optional[Decimal] = None
    formula_referencial: Optional[str] = None
    cuenta_contable_id: Optional[str] = None
    es_base: bool = False   # concepto base (sueldo) → valor día = monto/30

    @field_validator("tipo")
    @classmethod
    def _tipo(cls, v: str) -> str:
        if v not in TIPOS_CONCEPTO:
            raise ValueError(f"tipo debe ser uno de {sorted(TIPOS_CONCEPTO)}")
        return v


class ConceptoUpdate(BaseModel):
    """Actualización parcial de un concepto (p. ej. marcarlo como base)."""
    nombre: Optional[str] = None
    monto_referencial: Optional[Decimal] = None
    activo: Optional[bool] = None
    es_base: Optional[bool] = None


class ConceptoOut(BaseModel):
    id: str
    codigo: str
    nombre: str
    tipo: str
    monto_referencial: Optional[Decimal] = None
    activo: bool
    es_base: bool = False


class BoletaDetalleUpdate(BaseModel):
    """Override manual de un concepto en una boleta (antes de aprobar).
    monto = 0 elimina el concepto de la boleta."""
    concepto_id: str
    monto: Decimal


TIPOS_REGIMEN_LABORAL = {"micro", "pequena", "general"}
TIPOS_ESQUEMA_PAGO = {"mensual", "quincenal"}


class ConfigPlanillaOut(BaseModel):
    descuento_tardanza_auto: bool
    regimen_laboral: str
    esquema_pago_planilla: str
    # Gate de trámite (2026-07-07, decisión de negocio con riesgo legal,
    # default False): si es False, solo se paga sobretiempo respaldado por
    # un trámite de Permanencia Extra aprobado. Ver planilla_calculo_service.
    pagar_horas_extra_sin_tramite: bool = False


class ConfigPlanillaUpdate(BaseModel):
    descuento_tardanza_auto: Optional[bool] = None
    regimen_laboral: Optional[str] = None
    esquema_pago_planilla: Optional[str] = None
    pagar_horas_extra_sin_tramite: Optional[bool] = None

    @field_validator("regimen_laboral")
    @classmethod
    def _regimen(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_REGIMEN_LABORAL:
            raise ValueError(f"regimen_laboral debe ser uno de {sorted(TIPOS_REGIMEN_LABORAL)}")
        return v

    @field_validator("esquema_pago_planilla")
    @classmethod
    def _esquema(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_ESQUEMA_PAGO:
            raise ValueError(f"esquema_pago_planilla debe ser uno de {sorted(TIPOS_ESQUEMA_PAGO)}")
        return v


# ── Configuración previsional por empleado (Fase 8) ───────────────────────────
TIPOS_SISTEMA_PENSION = {"onp", "afp"}
TIPOS_ENTIDAD_AFP = {"integra", "prima", "profuturo", "habitat"}
TIPOS_COMISION_AFP = {"flujo", "saldo"}


class PensionConfigOut(BaseModel):
    empleado_id: str
    sistema_pension: str
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: bool
    # 'saldo' (default legal post-2013, NO se descuenta en planilla) o
    # 'flujo' (SÍ se descuenta sobre la remuneración cada mes).
    tipo_comision_afp: str = "saldo"


class PensionConfigUpdate(BaseModel):
    """Actualización parcial (PATCH semántico): solo los campos presentes
    en el body se modifican. comision_afp_personalizada=None restablece
    la comisión oficial de la AFP (ver AFP_COMISIONES)."""
    sistema_pension: Optional[str] = None
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: Optional[bool] = None
    tipo_comision_afp: Optional[str] = None

    @field_validator("tipo_comision_afp")
    @classmethod
    def _tipo_comision(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_COMISION_AFP:
            raise ValueError(f"tipo_comision_afp debe ser uno de {sorted(TIPOS_COMISION_AFP)}")
        return v

    @field_validator("sistema_pension")
    @classmethod
    def _sistema(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_SISTEMA_PENSION:
            raise ValueError(f"sistema_pension debe ser uno de {sorted(TIPOS_SISTEMA_PENSION)}")
        return v

    @field_validator("entidad_afp")
    @classmethod
    def _entidad(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in TIPOS_ENTIDAD_AFP:
            raise ValueError(f"entidad_afp debe ser uno de {sorted(TIPOS_ENTIDAD_AFP)}")
        return v

    @field_validator("comision_afp_personalizada")
    @classmethod
    def _comision(cls, v: Optional[Decimal]) -> Optional[Decimal]:
        if v is not None and (v < 0 or v > Decimal("0.5")):
            raise ValueError("comision_afp_personalizada debe estar entre 0 y 0.5 (50%)")
        return v


class SueldoBaseUpdate(BaseModel):
    monto: Decimal

    @field_validator("monto")
    @classmethod
    def _monto(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("monto no puede ser negativo")
        return v


# ── Vista previa de planilla (Fase 8, GET /planilla/preview) ────────────────
# NO persiste nada — combina resumen_horas_periodo (asistencia real) +
# calcular_boleta_empleado (motor legal puro) para mostrar el desglose
# completo de cada empleado antes de comprometerlo con POST /calcular.

class PeriodoPreviewOut(BaseModel):
    fecha_inicio: date
    fecha_fin: date
    meta_horas: float


class PlanillaPreviewEmpleadoOut(BaseModel):
    # Identidad / asistencia (paridad con ResumenEmpleadoDto del frontend)
    id: str
    nombre_completo: Optional[str] = None
    cargo: Optional[str] = None
    area: Optional[str] = None
    iniciales: str
    foto_url: str
    tipo_contrato: str
    codigo: Optional[str] = None
    tipo_documento: Optional[str] = None
    numero_documento: Optional[str] = None
    cuspp: Optional[str] = None
    fecha_ingreso: Optional[date] = None
    horas_reales: float
    horas_justificadas: float
    horas_total: float
    horas_faltantes: float
    horas_extra: float
    horas_extra_aprobadas: float = 0
    horas_extra_no_autor: float = 0
    dias_laborados: int = 0
    meta_horas: float
    porcentaje: float
    advertencias: int = 0

    # Configuración previsional vigente (para reflejar selects sin otra llamada)
    sistema_pension: str
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    comision_afp_pct: Decimal
    tipo_comision_afp: str = "saldo"
    tiene_asignacion_familiar: bool

    sueldo_base: Decimal
    sueldo_periodo: Decimal
    sueldo_devengado: Decimal   # sueldo_periodo ya proporcional a la asistencia real

    valor_dia: Decimal
    valor_hora: Decimal
    valor_minuto: Decimal

    dias_faltantes: int
    minutos_tardanza: int
    descuento_dominical: Decimal
    descuento_faltas: Decimal

    horas_extra_25: Decimal          # informativo: horas completas en tramo 25% (antes del gate de trámite)
    horas_extra_35: Decimal          # informativo: horas completas en tramo 35% (antes del gate de trámite)
    horas_extra_pagables: Decimal    # horas COMPLETAS que sí se pagan (fracción no se paga; puede topar por el gate)
    horas_extra_sin_tramite: Decimal # alerta: de todo lo truncado, cuánto sin Permanencia Extra aprobada
    pago_horas_extra: Decimal
    horas_domingo: Decimal           # horas trabajadas el día de descanso semanal
    pago_domingo: Decimal            # retribución + sobretasa 100% (D.Leg. 713 Art. 3)
    horas_feriado: Decimal           # horas trabajadas en día feriado no laborable
    pago_feriado: Decimal            # retribución + sobretasa 100% (D.Leg. 713 Art. 8/9)
    asignacion_familiar: Decimal

    es_afp: bool
    base_pension: Decimal
    descuento_pension: Decimal
    afp_aporte_obligatorio: Decimal
    afp_prima_seguro: Decimal
    afp_comision: Decimal

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


class PlanillaPreviewOut(BaseModel):
    periodo: PeriodoPreviewOut
    regimen_empresa: str
    esquema_pago: str
    periodo_pago: str
    rmv_vigente: Decimal  # parámetro legal (D.S. 001-2025-TR) — evita duplicarlo en el frontend
    empleados: List[PlanillaPreviewEmpleadoOut]
    total: int
    page: int
    limit: int
    total_paginas: int


class PlanillaOut(BaseModel):
    id: str
    periodo_id: str
    anio: Optional[int] = None
    mes: Optional[int] = None
    fecha_proceso: date
    estado: str
    total_ingresos: Decimal
    total_descuentos: Decimal
    total_aportes: Decimal
    total_neto: Decimal
    total_cts: Decimal = Decimal(0)
    total_gratificacion: Decimal = Decimal(0)
    total_vacaciones: Decimal = Decimal(0)
    asiento_provision_id: Optional[str] = None
    asiento_pago_id: Optional[str] = None


class BoletaDetalleOut(BaseModel):
    concepto_id: str
    concepto_nombre: Optional[str] = None
    concepto_codigo: Optional[str] = None
    monto: Decimal


class BoletaOut(BaseModel):
    id: str
    empleado_id: str
    empleado_nombre: Optional[str] = None
    total_ingresos: Decimal
    total_descuentos: Decimal
    total_aportes: Decimal
    total_neto: Decimal
    detalles: List[BoletaDetalleOut]


# ── Sueldos por empleado (asignación de montos por concepto) ──────────────────
class EmpleadoPlanillaOut(BaseModel):
    """Empleado activo, para asignarle montos por concepto en Planilla."""
    id: str
    nombre: Optional[str] = None
    cargo: Optional[str] = None
    # Configuración previsional vigente (Fase 8) — de empleado_planilla_config,
    # con los defaults de código si el empleado no tiene fila propia todavía.
    sistema_pension: str = "onp"
    entidad_afp: Optional[str] = None
    comision_afp_personalizada: Optional[Decimal] = None
    tiene_asignacion_familiar: bool = False
    tipo_comision_afp: str = "saldo"


class AsignacionOut(BaseModel):
    empleado_id: str
    concepto_id: str
    monto: Decimal


class AsignacionItem(BaseModel):
    """Una asignación a guardar. monto None elimina el override (vuelve al referencial)."""
    concepto_id: str
    monto: Optional[Decimal] = None


TIPOS_MODALIDAD = {"planilla", "contrato", "practicante"}


class ModalidadUpdate(BaseModel):
    """Modalidad laboral del empleado (afecta el cálculo de planilla)."""
    tipo: str

    @field_validator("tipo")
    @classmethod
    def _tipo(cls, v: str) -> str:
        if v not in TIPOS_MODALIDAD:
            raise ValueError(f"tipo debe ser uno de {sorted(TIPOS_MODALIDAD)}")
        return v


# ── Detalle diario de asistencia (2026-07-08, modal "Ver" de Planilla) ──────
# Solo lectura — reusa `resumen_horas_periodo(..., incluir_detalle_dias=True)`,
# NUNCA recalcula: los `totales` de acá son la SUMA de `detalle_dias`, así el
# modal siempre reconcilia exacto con la fila de la boleta.

class MarcacionPuntoOut(BaseModel):
    hora: Optional[datetime] = None
    lat: Optional[float] = None   # None si no hay geolocalización para esa marcación
    lng: Optional[float] = None


class MarcacionesDiaOut(BaseModel):
    entrada:         Optional[MarcacionPuntoOut] = None
    salida:           Optional[MarcacionPuntoOut] = None
    almuerzo_inicio:  Optional[MarcacionPuntoOut] = None
    almuerzo_fin:     Optional[MarcacionPuntoOut] = None


TIPOS_DIA_DETALLE = {"laborable", "domingo", "feriado", "no_laborable_turno"}


class DetalleDiaOut(BaseModel):
    fecha: date
    dia_semana: str
    tipo_dia: str                              # laborable|domingo|feriado|no_laborable_turno
    es_justificado: bool
    motivo_justificacion: Optional[str] = None  # tipo de la SolicitudLaboral que cubre el día
    turno_nombre: Optional[str] = None
    req_horas: Decimal                          # horas requeridas del turno ese día (0 si no aplica)
    marcaciones: MarcacionesDiaOut
    horas_reales: Decimal
    horas_extra_bruto: Decimal                  # informativo, sin truncar
    horas_extra_pagable: Decimal                # floor por día
    extra_25: Decimal                           # min(pagable, 2)
    extra_35: Decimal                           # max(0, pagable-2)
    falta: Decimal                              # max(0, req_horas - horas_reales), NO neteado con otros días
    alerta: Optional[str] = None                # "marcacion_incompleta" | "sin_tramite" | null


class TotalesAsistenciaDetalleOut(BaseModel):
    meta_horas: Decimal
    horas_reales: Decimal
    horas_justificadas: Decimal
    horas_faltantes: Decimal
    horas_extra_bruto: Decimal
    extra_25: Decimal
    extra_35: Decimal
    horas_domingo: Decimal
    horas_feriado: Decimal
    dias_laborados: int


class EmpleadoAsistenciaDetalleOut(BaseModel):
    id: str
    nombre_completo: Optional[str] = None
    codigo: Optional[str] = None
    tipo_contrato: str


class PeriodoAsistenciaDetalleOut(BaseModel):
    inicio: date
    fin: date


class AsistenciaDetalleOut(BaseModel):
    empleado: EmpleadoAsistenciaDetalleOut
    periodo: PeriodoAsistenciaDetalleOut
    totales: TotalesAsistenciaDetalleOut
    detalle_dias: List[DetalleDiaOut]
