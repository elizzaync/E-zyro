"""
Router: /planilla — nómina / planilla (Fase 8).

Flujo: calcular → aprobar (provisión) → marcar-pagada (pago). Gestión del
catálogo de conceptos remunerativos. Todo el efecto contable pasa por
planilla_service → registrar_asiento. RBAC (modulo='planilla').
"""
from __future__ import annotations

import calendar as _cal
from datetime import date
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.empleado import Empleado
from ..models.usuario import Usuario
from ..models.empresa import Empresa
from ..models.contabilidad import PeriodoContable
from ..models.planilla import (
    ConceptoRemunerativo, Planilla, BoletaPago, BoletaPagoDetalle, EmpleadoConcepto,
)
from ..models.empleado_planilla_config import EmpleadoPlanillaConfig
from ..schemas.planilla import (
    ConceptoCreate, ConceptoUpdate, ConceptoOut, PlanillaOut, BoletaOut, BoletaDetalleOut,
    EmpleadoPlanillaOut, AsignacionOut, AsignacionItem,
    BoletaDetalleUpdate, ConfigPlanillaOut, ConfigPlanillaUpdate, ModalidadUpdate,
    PensionConfigOut, PensionConfigUpdate, SueldoBaseUpdate,
    PeriodoPreviewOut, PlanillaPreviewEmpleadoOut, PlanillaPreviewOut,
)
from ..services import planilla_service as planilla_svc
from ..services.planilla_asistencia_service import resumen_horas_periodo
from ..services.planilla_calculo_service import InsumoEmpleado, calcular_boleta_empleado

router = APIRouter(prefix="/planilla", tags=["planilla"])

PERIODOS_PAGO_VALIDOS = {"mes", "q1", "q2"}


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


@router.get("/empresa-info")
def info_empresa(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Datos de la propia empresa (razón social, RUC) para encabezar la
    Planilla Mensual de Remuneraciones en PDF."""
    exigir_permiso(db, payload, "planilla", "ver")
    emp = db.query(Empresa).filter(Empresa.id == payload["empresa_id"]).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empresa no encontrada.")
    return {
        "razon_social": emp.razon_social,
        "ruc": emp.ruc,
        "regimen_tributario": emp.regimen_tributario,
        "direccion": emp.direccion or "",
        "telefono": emp.telefono or "",
    }


def _planilla_out(p: Planilla, db: Session) -> PlanillaOut:
    periodo = db.query(PeriodoContable).filter(PeriodoContable.id == p.periodo_id).first()
    return PlanillaOut(
        id=str(p.id), periodo_id=str(p.periodo_id),
        anio=(periodo.anio if periodo else None), mes=(periodo.mes if periodo else None),
        fecha_proceso=p.fecha_proceso,
        estado=p.estado, total_ingresos=p.total_ingresos, total_descuentos=p.total_descuentos,
        total_aportes=p.total_aportes, total_neto=p.total_neto,
        total_cts=p.total_cts, total_gratificacion=p.total_gratificacion, total_vacaciones=p.total_vacaciones,
        asiento_provision_id=(str(p.asiento_provision_id) if p.asiento_provision_id else None),
        asiento_pago_id=(str(p.asiento_pago_id) if p.asiento_pago_id else None),
    )


# ── Conceptos remunerativos (catálogo configurable) ──────────────────────────
@router.get("/conceptos", response_model=List[ConceptoOut])
def listar_conceptos(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    filas = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.empresa_id == payload["empresa_id"]).order_by(ConceptoRemunerativo.codigo).all()
    return [ConceptoOut(id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
                        monto_referencial=c.monto_referencial, activo=(c.activo == "true"),
                        es_base=(getattr(c, "es_base", "false") == "true")) for c in filas]


@router.post("/conceptos", response_model=ConceptoOut, status_code=201)
def crear_concepto(
    body: ConceptoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "calcular")
    dup = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.empresa_id == payload["empresa_id"],
        ConceptoRemunerativo.codigo == body.codigo).first()
    if dup:
        raise HTTPException(status_code=409, detail="Ya existe un concepto con ese código.")
    c = ConceptoRemunerativo(
        empresa_id=payload["empresa_id"], codigo=body.codigo, nombre=body.nombre, tipo=body.tipo,
        monto_referencial=body.monto_referencial, formula_referencial=body.formula_referencial,
        cuenta_contable_id=body.cuenta_contable_id, activo="true",
        es_base="true" if body.es_base else "false",
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return ConceptoOut(id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
                       monto_referencial=c.monto_referencial, activo=True,
                       es_base=bool(body.es_base))


@router.patch("/conceptos/{concepto_id}", response_model=ConceptoOut)
def actualizar_concepto(
    concepto_id: str,
    body: ConceptoUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Actualiza un concepto (nombre/monto/activo) y permite marcarlo como BASE
    (es_base) para el valor día de los descuentos por asistencia. Solo un concepto
    base por empresa: marcar uno desmarca el resto."""
    exigir_permiso(db, payload, "planilla", "calcular")
    empresa_id = payload["empresa_id"]
    c = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.id == concepto_id,
        ConceptoRemunerativo.empresa_id == empresa_id).first()
    if c is None:
        raise HTTPException(status_code=404, detail="Concepto no encontrado.")
    if body.nombre is not None:
        c.nombre = body.nombre
    if body.monto_referencial is not None:
        c.monto_referencial = body.monto_referencial
    if body.activo is not None:
        c.activo = "true" if body.activo else "false"
    if body.es_base is not None:
        if body.es_base:
            # base único: desmarca cualquier otro concepto base de la empresa
            db.query(ConceptoRemunerativo).filter(
                ConceptoRemunerativo.empresa_id == empresa_id,
                ConceptoRemunerativo.id != c.id,
                ConceptoRemunerativo.es_base == "true").update(
                    {ConceptoRemunerativo.es_base: "false"}, synchronize_session=False)
        c.es_base = "true" if body.es_base else "false"
    db.commit()
    db.refresh(c)
    return ConceptoOut(id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
                       monto_referencial=c.monto_referencial, activo=(c.activo == "true"),
                       es_base=(c.es_base == "true"))


@router.get("/config", response_model=ConfigPlanillaOut)
def obtener_config(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    emp = db.query(Empresa).filter(Empresa.id == payload["empresa_id"]).first()
    return ConfigPlanillaOut(
        descuento_tardanza_auto=bool(getattr(emp, "descuento_tardanza_auto", True)) if emp else True,
        regimen_laboral=getattr(emp, "regimen_laboral", None) or "micro",
        esquema_pago_planilla=getattr(emp, "esquema_pago_planilla", None) or "quincenal",
    )


@router.patch("/config", response_model=ConfigPlanillaOut)
def actualizar_config(
    body: ConfigPlanillaUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Actualización parcial (PATCH semántico): solo los campos presentes
    en el body se modifican."""
    exigir_permiso(db, payload, "planilla", "calcular")
    emp = db.query(Empresa).filter(Empresa.id == payload["empresa_id"]).first()
    if emp is None:
        raise HTTPException(status_code=404, detail="Empresa no encontrada.")
    if body.descuento_tardanza_auto is not None:
        emp.descuento_tardanza_auto = bool(body.descuento_tardanza_auto)
    if body.regimen_laboral is not None:
        emp.regimen_laboral = body.regimen_laboral
    if body.esquema_pago_planilla is not None:
        emp.esquema_pago_planilla = body.esquema_pago_planilla
    db.commit()
    db.refresh(emp)
    return ConfigPlanillaOut(
        descuento_tardanza_auto=bool(emp.descuento_tardanza_auto),
        regimen_laboral=emp.regimen_laboral,
        esquema_pago_planilla=emp.esquema_pago_planilla,
    )


# ── Vista previa (Fase 8) — NO persiste nada ─────────────────────────────────
@router.get("/preview", response_model=PlanillaPreviewOut)
def preview_planilla(
    fecha_inicio: Optional[date] = Query(None),
    fecha_fin:    Optional[date] = Query(None),
    periodo_pago: str            = Query("mes", description="mes | q1 | q2"),
    page:         int            = Query(1,  ge=1),
    limit:        int            = Query(10, ge=1, le=100),
    payload:      dict           = Depends(verificar_token),
    db:           Session        = Depends(get_db),
):
    """Desglose completo de la boleta de cada empleado para el rango dado,
    SIN escribir nada en BD (ni Planilla, ni BoletaPago, ni EmpleadoConcepto).
    Combina `resumen_horas_periodo` (asistencia real, Fase 0) con
    `calcular_boleta_empleado` (motor legal puro, Fase 2). El sueldo base y
    la config previsional se leen de la misma fuente que usará `POST
    /calcular` cuando esta vista se comprometa a BD (Fase 4)."""
    exigir_permiso(db, payload, "planilla", "ver")
    empresa_id = payload["empresa_id"]

    if periodo_pago not in PERIODOS_PAGO_VALIDOS:
        raise HTTPException(status_code=422, detail=f"periodo_pago debe ser uno de {sorted(PERIODOS_PAGO_VALIDOS)}")

    hoy = date.today()
    if fecha_inicio is None or fecha_fin is None:
        # Default: mes calendario completo (a diferencia de /rrhh/asistencia/resumen,
        # que por defecto usa la semana — planilla es de naturaleza mensual).
        ultimo_dia = _cal.monthrange(hoy.year, hoy.month)[1]
        fecha_inicio = fecha_inicio or date(hoy.year, hoy.month, 1)
        fecha_fin = fecha_fin or date(hoy.year, hoy.month, ultimo_dia)
    if fecha_fin < fecha_inicio:
        raise HTTPException(status_code=400, detail="fecha_fin debe ser >= fecha_inicio")

    empresa = db.query(Empresa).filter(Empresa.id == empresa_id).first()
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada.")
    regimen_empresa = getattr(empresa, "regimen_laboral", None) or "micro"
    esquema_pago = getattr(empresa, "esquema_pago_planilla", None) or "quincenal"
    descuento_tardanza_auto = bool(getattr(empresa, "descuento_tardanza_auto", True))

    filas_asistencia = resumen_horas_periodo(db, empresa_id, fecha_inicio, fecha_fin)

    # Sueldo base: EmpleadoConcepto sobre el concepto SUELDO_BASE (es_base).
    # Si el catálogo aún no existe (nadie ha guardado ningún sueldo todavía),
    # sueldo_base=0 para todos — mismo comportamiento que "sin sueldo" hoy.
    concepto_base = db.query(ConceptoRemunerativo).filter(
        ConceptoRemunerativo.empresa_id == empresa_id,
        ConceptoRemunerativo.codigo == planilla_svc.COD_SUELDO_BASE,
    ).first()
    sueldos_por_emp: dict[str, Decimal] = {}
    if concepto_base:
        sueldos_por_emp = {
            str(ec.empleado_id): ec.monto
            for ec in db.query(EmpleadoConcepto).filter(
                EmpleadoConcepto.empresa_id == empresa_id,
                EmpleadoConcepto.concepto_id == concepto_base.id,
            ).all()
        }

    config_por_emp = {
        str(c.empleado_id): c
        for c in db.query(EmpleadoPlanillaConfig).filter(
            EmpleadoPlanillaConfig.empresa_id == empresa_id).all()
    }

    empleados_out: list[PlanillaPreviewEmpleadoOut] = []
    for fila in filas_asistencia:
        emp_id = str(fila["id"])
        cfg = config_por_emp.get(emp_id)
        sueldo_base = sueldos_por_emp.get(emp_id, Decimal("0"))

        insumo = InsumoEmpleado(
            empleado_id=emp_id,
            tipo_contrato=fila["tipo_contrato"],
            sueldo_base=Decimal(sueldo_base),
            horas_reales=Decimal(str(fila["horas_reales"])),
            horas_faltantes=Decimal(str(fila["horas_faltantes"])),
            meta_horas=Decimal(str(fila["meta_horas"])),
            sistema_pension=(cfg.sistema_pension if cfg else "onp"),
            entidad_afp=(cfg.entidad_afp if cfg else None),
            comision_afp_personalizada=(cfg.comision_afp_personalizada if cfg else None),
            tiene_asignacion_familiar=(bool(cfg.tiene_asignacion_familiar) if cfg else False),
        )
        desglose = calcular_boleta_empleado(
            insumo, regimen_empresa=regimen_empresa, periodo_pago=periodo_pago,
            descuento_tardanza_auto=descuento_tardanza_auto,
        )

        empleados_out.append(PlanillaPreviewEmpleadoOut(
            id=emp_id, nombre_completo=fila.get("nombreCompleto"), cargo=fila.get("cargo"),
            area=fila.get("area"), iniciales=fila.get("iniciales", "?"),
            foto_url=fila.get("fotoUrl", ""), tipo_contrato=fila["tipo_contrato"],
            codigo=fila.get("codigo"), tipo_documento=fila.get("tipo_documento"),
            numero_documento=fila.get("numero_documento"), cuspp=fila.get("cuspp"),
            fecha_ingreso=fila.get("fecha_ingreso"),
            horas_reales=fila["horas_reales"], horas_justificadas=fila["horas_justificadas"],
            horas_total=fila["horas_total"], horas_faltantes=fila["horas_faltantes"],
            horas_extra=fila["horas_extra"], horas_extra_aprobadas=fila["horas_extra_aprobadas"],
            horas_extra_no_autor=fila["horas_extra_no_autor"], dias_laborados=fila["dias_laborados"],
            meta_horas=fila["meta_horas"], porcentaje=fila["porcentaje"],
            advertencias=fila["advertencias"],
            sistema_pension=insumo.sistema_pension, entidad_afp=insumo.entidad_afp,
            comision_afp_personalizada=insumo.comision_afp_personalizada,
            comision_afp_pct=desglose.comision_afp_pct,
            tiene_asignacion_familiar=insumo.tiene_asignacion_familiar,
            sueldo_base=insumo.sueldo_base, sueldo_periodo=desglose.sueldo_periodo,
            sueldo_devengado=desglose.sueldo_devengado,
            valor_dia=desglose.valor_dia, valor_hora=desglose.valor_hora,
            valor_minuto=desglose.valor_minuto, dias_faltantes=desglose.dias_faltantes,
            minutos_tardanza=desglose.minutos_tardanza,
            descuento_dominical=desglose.descuento_dominical,
            descuento_faltas=desglose.descuento_faltas, pago_horas_extra=desglose.pago_horas_extra,
            asignacion_familiar=desglose.asignacion_familiar, es_afp=desglose.es_afp,
            base_pension=desglose.base_pension, descuento_pension=desglose.descuento_pension,
            afp_aporte_obligatorio=desglose.afp_aporte_obligatorio,
            afp_prima_seguro=desglose.afp_prima_seguro, afp_comision=desglose.afp_comision,
            renta_5ta=desglose.renta_5ta, total_ingresos=desglose.total_ingresos,
            total_descuentos_legales=desglose.total_descuentos_legales,
            neto_a_pagar=desglose.neto_a_pagar, aporte_essalud=desglose.aporte_essalud,
            provision_cts=desglose.provision_cts,
            provision_gratificacion=desglose.provision_gratificacion,
            provision_vacaciones=desglose.provision_vacaciones,
            dias_vacaciones=desglose.dias_vacaciones, bajo_rmv=desglose.bajo_rmv,
        ))

    # Mismo criterio de orden que /rrhh/asistencia/resumen (déficit de horas
    # primero), luego paginación en memoria.
    empleados_out.sort(key=lambda e: e.horas_faltantes, reverse=True)
    total = len(empleados_out)
    offset = (page - 1) * limit
    pagina = empleados_out[offset: offset + limit]

    dias_lab_ef = [
        d for d in _dias_laborables_rango(fecha_inicio, fecha_fin)
    ]
    meta_horas_global = len(dias_lab_ef) * 8.0

    return PlanillaPreviewOut(
        periodo=PeriodoPreviewOut(fecha_inicio=fecha_inicio, fecha_fin=fecha_fin, meta_horas=meta_horas_global),
        regimen_empresa=regimen_empresa, esquema_pago=esquema_pago, periodo_pago=periodo_pago,
        empleados=pagina, total=total, page=page, limit=limit,
        total_paginas=max(1, -(-total // limit)),
    )


def _dias_laborables_rango(inicio: date, fin: date) -> list[date]:
    """Días L-V del rango, sin descontar feriados (solo para el chip global
    de meta_horas del preview — no participa en el cálculo por empleado, que
    ya usa la meta real de `resumen_horas_periodo`, considerando turno propio
    y feriados)."""
    from ..routers.rrhh_asistencia import _dias_laborables
    return _dias_laborables(inicio, fin)


# ── Planilla ─────────────────────────────────────────────────────────────────
@router.get("", response_model=List[PlanillaOut])
def listar_planillas(
    periodo: Optional[str] = Query(None, description="Filtro opcional YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    empresa_id = payload["empresa_id"]
    q = db.query(Planilla).filter(Planilla.empresa_id == empresa_id)
    if periodo:
        try:
            anio, mes = (int(x) for x in periodo.split("-"))
        except Exception:
            raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")
        p = db.query(PeriodoContable).filter(
            PeriodoContable.empresa_id == empresa_id, PeriodoContable.anio == anio,
            PeriodoContable.mes == mes).first()
        if not p:
            return []  # el período no existe todavía -> ninguna planilla puede existir para él
        q = q.filter(Planilla.periodo_id == p.id)
    filas = q.order_by(Planilla.created_at.desc()).all()
    return [_planilla_out(p, db) for p in filas]


def _periodo(db: Session, empresa_id: str, periodo: str) -> PeriodoContable:
    """Get-or-create: Planilla no debe depender de que Contabilidad haya
    abierto el período antes (son módulos distintos operados por roles
    distintos). Si no existe, se crea 'abierto' — Contabilidad sigue siendo
    quien lo cierra/reabre normalmente."""
    try:
        anio, mes = (int(x) for x in periodo.split("-"))
    except Exception:
        raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")
    p = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == empresa_id, PeriodoContable.anio == anio,
        PeriodoContable.mes == mes).first()
    if not p:
        p = PeriodoContable(empresa_id=empresa_id, anio=anio, mes=mes, estado="abierto")
        db.add(p)
        db.commit()
        db.refresh(p)
    return p


@router.post("/calcular", response_model=PlanillaOut, status_code=201)
def calcular(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "calcular")
    p = _periodo(db, payload["empresa_id"], periodo)
    return _planilla_out(planilla_svc.calcular_planilla(db, payload["empresa_id"], p.id), db)


# ── Sueldos por empleado (asignación de montos por concepto) ──────────────────
# IMPORTANTE: rutas estáticas declaradas ANTES de "/{planilla_id}" para que no
# sean capturadas por el parámetro de ruta.
@router.get("/empleados", response_model=List[EmpleadoPlanillaOut])
def listar_empleados_planilla(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    empresa_id = payload["empresa_id"]
    rows = (
        db.query(Empleado, Usuario)
        .outerjoin(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id, Empleado.activo.is_(True))
        .order_by(Usuario.nombre)
        .all()
    )
    config_por_emp = {
        str(c.empleado_id): c
        for c in db.query(EmpleadoPlanillaConfig).filter(
            EmpleadoPlanillaConfig.empresa_id == empresa_id).all()
    }
    salida = []
    for e, u in rows:
        cfg = config_por_emp.get(str(e.id))
        salida.append(EmpleadoPlanillaOut(
            id=str(e.id),
            nombre=(f"{u.nombre} {u.apellido}".strip() if u else None),
            cargo=e.cargo,
            sistema_pension=(cfg.sistema_pension if cfg else "onp"),
            entidad_afp=(cfg.entidad_afp if cfg else None),
            comision_afp_personalizada=(cfg.comision_afp_personalizada if cfg else None),
            tiene_asignacion_familiar=(bool(cfg.tiene_asignacion_familiar) if cfg else False),
        ))
    return salida


@router.patch("/empleados/{empleado_id}/pension", response_model=PensionConfigOut)
def actualizar_pension_empleado(
    empleado_id: str,
    body: PensionConfigUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Actualización parcial (PATCH semántico) de la configuración previsional
    del empleado: sistema de pensión (ONP/AFP), entidad AFP, comisión
    personalizada y asignación familiar. Upsert en empleado_planilla_config."""
    exigir_permiso(db, payload, "planilla", "calcular")
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado.")

    cfg = db.query(EmpleadoPlanillaConfig).filter(
        EmpleadoPlanillaConfig.empleado_id == empleado_id).first()
    if cfg is None:
        cfg = EmpleadoPlanillaConfig(empresa_id=empresa_id, empleado_id=empleado_id)
        db.add(cfg)

    if body.sistema_pension is not None:
        cfg.sistema_pension = body.sistema_pension
    if "entidad_afp" in body.model_fields_set:
        cfg.entidad_afp = body.entidad_afp
    if "comision_afp_personalizada" in body.model_fields_set:
        cfg.comision_afp_personalizada = body.comision_afp_personalizada
    if body.tiene_asignacion_familiar is not None:
        cfg.tiene_asignacion_familiar = body.tiene_asignacion_familiar

    db.commit()
    db.refresh(cfg)
    return PensionConfigOut(
        empleado_id=str(cfg.empleado_id), sistema_pension=cfg.sistema_pension,
        entidad_afp=cfg.entidad_afp, comision_afp_personalizada=cfg.comision_afp_personalizada,
        tiene_asignacion_familiar=bool(cfg.tiene_asignacion_familiar),
    )


@router.put("/empleados/{empleado_id}/sueldo-base")
def actualizar_sueldo_base(
    empleado_id: str,
    body: SueldoBaseUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Guarda el sueldo base real del empleado (reemplaza el antiguo
    localStorage del frontend). Wrapper delgado sobre el mismo mecanismo de
    `guardar_asignaciones`: resuelve/crea el concepto SUELDO_BASE (es_base) y
    hace upsert del monto en EmpleadoConcepto."""
    exigir_permiso(db, payload, "planilla", "calcular")
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado.")

    concepto = planilla_svc._get_or_create_concepto(
        db, empresa_id, planilla_svc.COD_SUELDO_BASE, "Remuneración Básica",
        "ingreso", es_base=True,
    )
    existe = db.query(EmpleadoConcepto).filter(
        EmpleadoConcepto.empleado_id == empleado_id,
        EmpleadoConcepto.concepto_id == concepto.id).first()
    if existe:
        existe.monto = body.monto
    else:
        db.add(EmpleadoConcepto(
            empresa_id=empresa_id, empleado_id=empleado_id,
            concepto_id=concepto.id, monto=body.monto))
    db.commit()
    return {"empleado_id": empleado_id, "sueldo_base": str(body.monto)}


@router.post("/conceptos/inicializar-estandar", response_model=List[ConceptoOut])
def inicializar_catalogo_estandar(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Siembra el catálogo estándar de conceptos legales (Sueldo Base, Horas
    Extra, Asignación Familiar, ONP/AFP desglosado, Renta 5ta, EsSalud, etc.)
    para la empresa, si aún no existen. Idempotente."""
    exigir_permiso(db, payload, "planilla", "calcular")
    conceptos = planilla_svc.asegurar_catalogo_estandar(db, payload["empresa_id"])
    return [ConceptoOut(id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
                        monto_referencial=c.monto_referencial, activo=(c.activo == "true"),
                        es_base=(c.es_base == "true")) for c in conceptos]


@router.put("/empleados/{empleado_id}/modalidad")
def actualizar_modalidad(
    empleado_id: str,
    body: ModalidadUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Cambia la modalidad laboral del empleado (planilla/contrato/practicante),
    usada por RRHH para clasificar correctamente el cálculo de planilla."""
    exigir_permiso(db, payload, "planilla", "calcular")
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado.")
    emp.tipo = body.tipo
    db.commit()
    return {"id": emp.id, "tipo": emp.tipo}


@router.get("/asignaciones", response_model=List[AsignacionOut])
def listar_asignaciones(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    filas = db.query(EmpleadoConcepto).filter(
        EmpleadoConcepto.empresa_id == payload["empresa_id"]).all()
    return [AsignacionOut(
        empleado_id=str(a.empleado_id), concepto_id=str(a.concepto_id), monto=a.monto,
    ) for a in filas]


@router.put("/empleados/{empleado_id}/asignaciones", response_model=List[AsignacionOut])
def guardar_asignaciones(
    empleado_id: str,
    items: List[AsignacionItem],
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Upsert de montos por concepto para un empleado. monto None elimina el
    override (el concepto vuelve a usar su monto_referencial)."""
    exigir_permiso(db, payload, "planilla", "calcular")
    empresa_id = payload["empresa_id"]
    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado.")

    for it in items:
        existe = db.query(EmpleadoConcepto).filter(
            EmpleadoConcepto.empleado_id == empleado_id,
            EmpleadoConcepto.concepto_id == it.concepto_id).first()
        if it.monto is None:
            if existe:
                db.delete(existe)
            continue
        if existe:
            existe.monto = it.monto
        else:
            # valida que el concepto exista en la empresa
            c = db.query(ConceptoRemunerativo).filter(
                ConceptoRemunerativo.id == it.concepto_id,
                ConceptoRemunerativo.empresa_id == empresa_id).first()
            if not c:
                raise HTTPException(status_code=404, detail=f"Concepto {it.concepto_id} no encontrado.")
            db.add(EmpleadoConcepto(
                empresa_id=empresa_id, empleado_id=empleado_id,
                concepto_id=it.concepto_id, monto=it.monto))
    db.commit()

    filas = db.query(EmpleadoConcepto).filter(
        EmpleadoConcepto.empleado_id == empleado_id).all()
    return [AsignacionOut(
        empleado_id=str(a.empleado_id), concepto_id=str(a.concepto_id), monto=a.monto,
    ) for a in filas]


@router.get("/{planilla_id}", response_model=PlanillaOut)
def obtener(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    return _planilla_out(planilla_svc.get_planilla(db, payload["empresa_id"], planilla_id), db)


@router.post("/{planilla_id}/aprobar", response_model=PlanillaOut)
def aprobar(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "aprobar")
    return _planilla_out(planilla_svc.aprobar_planilla(db, payload["empresa_id"], planilla_id, _empleado_id(db, payload)), db)


@router.post("/{planilla_id}/marcar-pagada", response_model=PlanillaOut)
def marcar_pagada(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "aprobar")
    return _planilla_out(planilla_svc.marcar_pagada(db, payload["empresa_id"], planilla_id, _empleado_id(db, payload)), db)


@router.post("/{planilla_id}/anular", response_model=PlanillaOut)
def anular(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "anular")
    return _planilla_out(planilla_svc.anular_planilla(db, payload["empresa_id"], planilla_id), db)


@router.get("/{planilla_id}/boletas", response_model=List[BoletaOut])
def listar_boletas(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    empresa_id = payload["empresa_id"]
    planilla_svc.get_planilla(db, empresa_id, planilla_id)  # valida pertenencia
    boletas = db.query(BoletaPago).filter(BoletaPago.planilla_id == planilla_id).all()

    # Mapas nombre por empleado y por concepto (evita N+1).
    nombres_emp = {
        str(e.id): f"{u.nombre} {u.apellido}".strip() if u else None
        for e, u in db.query(Empleado, Usuario)
        .outerjoin(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id).all()
    }
    conceptos = {
        str(c.id): (c.nombre, c.codigo)
        for c in db.query(ConceptoRemunerativo).filter(
            ConceptoRemunerativo.empresa_id == empresa_id).all()
    }

    salida = []
    for b in boletas:
        detalles = db.query(BoletaPagoDetalle).filter(BoletaPagoDetalle.boleta_id == b.id).all()
        salida.append(BoletaOut(
            id=str(b.id), empleado_id=str(b.empleado_id),
            empleado_nombre=nombres_emp.get(str(b.empleado_id)),
            total_ingresos=b.total_ingresos,
            total_descuentos=b.total_descuentos, total_aportes=b.total_aportes, total_neto=b.total_neto,
            detalles=[BoletaDetalleOut(
                concepto_id=str(d.concepto_id),
                concepto_nombre=conceptos.get(str(d.concepto_id), (None, None))[0],
                concepto_codigo=conceptos.get(str(d.concepto_id), (None, None))[1],
                monto=d.monto,
            ) for d in detalles],
        ))
    return salida


@router.patch("/{planilla_id}/boletas/{boleta_id}/detalle", response_model=PlanillaOut)
def editar_detalle_boleta(
    planilla_id: str,
    boleta_id: str,
    body: BoletaDetalleUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    """Override manual de un concepto en la boleta (p. ej. corregir el descuento
    automático por falta/tardanza) mientras la planilla está 'calculada'.
    monto=0 elimina el concepto. Recalcula totales de boleta y planilla."""
    exigir_permiso(db, payload, "planilla", "calcular")
    return _planilla_out(planilla_svc.editar_boleta_detalle(
        db, payload["empresa_id"], planilla_id, boleta_id, body.concepto_id, body.monto), db)
