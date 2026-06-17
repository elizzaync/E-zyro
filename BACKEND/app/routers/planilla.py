"""
Router: /planilla — nómina / planilla (Fase 8).

Flujo: calcular → aprobar (provisión) → marcar-pagada (pago). Gestión del
catálogo de conceptos remunerativos. Todo el efecto contable pasa por
planilla_service → registrar_asiento. RBAC (modulo='planilla').
"""
from __future__ import annotations

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
from ..schemas.planilla import (
    ConceptoCreate, ConceptoUpdate, ConceptoOut, PlanillaOut, BoletaOut, BoletaDetalleOut,
    EmpleadoPlanillaOut, AsignacionOut, AsignacionItem,
    BoletaDetalleUpdate, ConfigPlanillaOut, ConfigPlanillaUpdate, ModalidadUpdate,
)
from ..services import planilla_service as planilla_svc

router = APIRouter(prefix="/planilla", tags=["planilla"])


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


def _planilla_out(p: Planilla) -> PlanillaOut:
    return PlanillaOut(
        id=str(p.id), periodo_id=str(p.periodo_id), fecha_proceso=p.fecha_proceso,
        estado=p.estado, total_ingresos=p.total_ingresos, total_descuentos=p.total_descuentos,
        total_aportes=p.total_aportes, total_neto=p.total_neto,
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
        descuento_tardanza_auto=bool(getattr(emp, "descuento_tardanza_auto", True)) if emp else True)


@router.patch("/config", response_model=ConfigPlanillaOut)
def actualizar_config(
    body: ConfigPlanillaUpdate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "calcular")
    emp = db.query(Empresa).filter(Empresa.id == payload["empresa_id"]).first()
    if emp is None:
        raise HTTPException(status_code=404, detail="Empresa no encontrada.")
    emp.descuento_tardanza_auto = bool(body.descuento_tardanza_auto)
    db.commit()
    return ConfigPlanillaOut(descuento_tardanza_auto=bool(emp.descuento_tardanza_auto))


# ── Planilla ─────────────────────────────────────────────────────────────────
@router.get("", response_model=List[PlanillaOut])
def listar_planillas(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "ver")
    filas = db.query(Planilla).filter(Planilla.empresa_id == payload["empresa_id"]).order_by(Planilla.created_at.desc()).all()
    return [_planilla_out(p) for p in filas]


def _periodo(db: Session, empresa_id: str, periodo: str) -> PeriodoContable:
    try:
        anio, mes = (int(x) for x in periodo.split("-"))
    except Exception:
        raise HTTPException(status_code=422, detail="periodo inválido; use 'YYYY-MM'.")
    p = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == empresa_id, PeriodoContable.anio == anio,
        PeriodoContable.mes == mes).first()
    if not p:
        raise HTTPException(status_code=404, detail=f"No existe periodo {periodo}.")
    return p


@router.post("/calcular", response_model=PlanillaOut, status_code=201)
def calcular(
    periodo: str = Query(..., description="YYYY-MM"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "calcular")
    p = _periodo(db, payload["empresa_id"], periodo)
    return _planilla_out(planilla_svc.calcular_planilla(db, payload["empresa_id"], p.id))


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
    return [EmpleadoPlanillaOut(
        id=str(e.id),
        nombre=(f"{u.nombre} {u.apellido}".strip() if u else None),
        cargo=e.cargo,
    ) for e, u in rows]


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
    return _planilla_out(planilla_svc.get_planilla(db, payload["empresa_id"], planilla_id))


@router.post("/{planilla_id}/aprobar", response_model=PlanillaOut)
def aprobar(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "aprobar")
    return _planilla_out(planilla_svc.aprobar_planilla(db, payload["empresa_id"], planilla_id, _empleado_id(db, payload)))


@router.post("/{planilla_id}/marcar-pagada", response_model=PlanillaOut)
def marcar_pagada(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "aprobar")
    return _planilla_out(planilla_svc.marcar_pagada(db, payload["empresa_id"], planilla_id, _empleado_id(db, payload)))


@router.post("/{planilla_id}/anular", response_model=PlanillaOut)
def anular(
    planilla_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "planilla", "anular")
    return _planilla_out(planilla_svc.anular_planilla(db, payload["empresa_id"], planilla_id))


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
        db, payload["empresa_id"], planilla_id, boleta_id, body.concepto_id, body.monto))
