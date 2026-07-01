"""
Router: /contabilidad — núcleo contable (Fase 1, Libro Mayor).

Lecturas: empresa del token (RBAC 'contabilidad.ver').
Escrituras de asientos: SIEMPRE vía contabilizacion_service.registrar_asiento.
El catálogo PCGE no se edita libremente: solo se activa/desactiva.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.contabilidad import (
    CuentaContable, PeriodoContable, AsientoContable, AsientoLinea,
)
from ..models.empleado import Empleado
from ..schemas.contabilidad import (
    CuentaOut, CuentaActivarIn,
    PeriodoCreate, PeriodoOut,
    AsientoCreate, AsientoOut, AsientoLineaOut,
    BalanceComprobacionOut, BalanceComprobacionFila,
)
from ..services import contabilizacion_service as contab

router = APIRouter(prefix="/contabilidad", tags=["contabilidad"])


def _empleado_id(db: Session, payload: dict) -> Optional[str]:
    emp = db.query(Empleado).filter(Empleado.usuario_id == payload.get("id")).first()
    return str(emp.id) if emp else None


# ── Plan de cuentas ──────────────────────────────────────────────────────────
@router.get("/plan-cuentas", response_model=List[CuentaOut])
def listar_plan_cuentas(
    tipo: Optional[str] = Query(None),
    nivel: Optional[str] = Query(None),
    activo: Optional[bool] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    q = db.query(CuentaContable).filter(CuentaContable.empresa_id == payload["empresa_id"])
    if tipo:
        q = q.filter(CuentaContable.tipo == tipo)
    if nivel:
        q = q.filter(CuentaContable.nivel == nivel)
    if activo is not None:
        q = q.filter(CuentaContable.activo.is_(activo))
    return [CuentaOut(
        id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
        naturaleza=c.naturaleza, nivel=c.nivel,
        cuenta_padre_id=(str(c.cuenta_padre_id) if c.cuenta_padre_id else None),
        activo=bool(c.activo),
    ) for c in q.order_by(CuentaContable.codigo).all()]


@router.put("/plan-cuentas/{cuenta_id}", response_model=CuentaOut)
def activar_desactivar_cuenta(
    cuenta_id: str, body: CuentaActivarIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "gestionar_cuentas")
    c = db.query(CuentaContable).filter(
        CuentaContable.id == cuenta_id, CuentaContable.empresa_id == payload["empresa_id"],
    ).first()
    if not c:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada")
    c.activo = body.activo
    db.commit()
    db.refresh(c)
    return CuentaOut(
        id=str(c.id), codigo=c.codigo, nombre=c.nombre, tipo=c.tipo,
        naturaleza=c.naturaleza, nivel=c.nivel,
        cuenta_padre_id=(str(c.cuenta_padre_id) if c.cuenta_padre_id else None),
        activo=bool(c.activo),
    )


# ── Periodos ─────────────────────────────────────────────────────────────────
@router.get("/periodos", response_model=List[PeriodoOut])
def listar_periodos(payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "contabilidad", "ver")
    q = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == payload["empresa_id"]
    ).order_by(PeriodoContable.anio.desc(), PeriodoContable.mes.desc())
    return [PeriodoOut(id=str(p.id), anio=p.anio, mes=p.mes, estado=p.estado, cerrado_at=p.cerrado_at) for p in q.all()]


@router.post("/periodos", response_model=PeriodoOut, status_code=201)
def abrir_periodo(
    body: PeriodoCreate,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "abrir_periodo")
    existe = db.query(PeriodoContable).filter(
        PeriodoContable.empresa_id == payload["empresa_id"],
        PeriodoContable.anio == body.anio, PeriodoContable.mes == body.mes,
    ).first()
    if existe:
        raise HTTPException(status_code=409, detail="El periodo ya existe")
    p = PeriodoContable(
        empresa_id=payload["empresa_id"], anio=body.anio, mes=body.mes, estado="abierto",
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return PeriodoOut(id=str(p.id), anio=p.anio, mes=p.mes, estado=p.estado, cerrado_at=p.cerrado_at)


@router.post("/periodos/{periodo_id}/cerrar", response_model=PeriodoOut)
def cerrar_periodo(
    periodo_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "cerrar_periodo")
    p = db.query(PeriodoContable).filter(
        PeriodoContable.id == periodo_id, PeriodoContable.empresa_id == payload["empresa_id"],
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Periodo no encontrado")
    if p.estado == "cerrado":
        raise HTTPException(status_code=409, detail="El periodo ya está cerrado")
    p.estado = "cerrado"
    p.cerrado_por_id = _empleado_id(db, payload)
    p.cerrado_at = datetime.utcnow()
    db.commit()
    db.refresh(p)
    return PeriodoOut(id=str(p.id), anio=p.anio, mes=p.mes, estado=p.estado, cerrado_at=p.cerrado_at)


@router.post("/periodos/{periodo_id}/reabrir", response_model=PeriodoOut)
def reabrir_periodo(
    periodo_id: str,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    # Reapertura controlada: requiere un permiso distinto y queda en auditoría.
    exigir_permiso(db, payload, "contabilidad", "reabrir_periodo")
    p = db.query(PeriodoContable).filter(
        PeriodoContable.id == periodo_id, PeriodoContable.empresa_id == payload["empresa_id"],
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="Periodo no encontrado")
    if p.estado == "abierto":
        raise HTTPException(status_code=409, detail="El periodo ya está abierto")
    p.estado = "abierto"
    p.cerrado_por_id = None
    p.cerrado_at = None
    db.commit()
    db.refresh(p)
    return PeriodoOut(id=str(p.id), anio=p.anio, mes=p.mes, estado=p.estado, cerrado_at=p.cerrado_at)


# ── Asientos ─────────────────────────────────────────────────────────────────
def _asiento_out(db: Session, a: AsientoContable) -> AsientoOut:
    lineas = db.query(AsientoLinea).filter(AsientoLinea.asiento_id == a.id).all()
    codigos = {}
    if lineas:
        for c in db.query(CuentaContable.id, CuentaContable.codigo).filter(
            CuentaContable.id.in_([l.cuenta_id for l in lineas])
        ).all():
            codigos[str(c.id)] = c.codigo
    return AsientoOut(
        id=str(a.id), numero=a.numero, fecha=a.fecha, periodo_id=str(a.periodo_id),
        descripcion=a.descripcion, origen=a.origen,
        referencia_id=(str(a.referencia_id) if a.referencia_id else None),
        lineas=[AsientoLineaOut(
            id=str(l.id), cuenta_id=str(l.cuenta_id),
            cuenta_codigo=codigos.get(str(l.cuenta_id)),
            debito=l.debito, credito=l.credito,
            centro_costo_id=(str(l.centro_costo_id) if l.centro_costo_id else None),
            glosa=l.glosa,
        ) for l in lineas],
    )


@router.get("/asientos", response_model=List[AsientoOut])
def listar_asientos(
    periodo_id: Optional[str] = Query(None),
    origen: Optional[str] = Query(None),
    desde: Optional[date] = Query(None),
    hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    q = db.query(AsientoContable).filter(AsientoContable.empresa_id == payload["empresa_id"])
    if periodo_id:
        q = q.filter(AsientoContable.periodo_id == periodo_id)
    if origen:
        q = q.filter(AsientoContable.origen == origen)
    if desde:
        q = q.filter(AsientoContable.fecha >= desde)
    if hasta:
        q = q.filter(AsientoContable.fecha <= hasta)
    return [_asiento_out(db, a) for a in q.order_by(AsientoContable.fecha.desc(), AsientoContable.numero.desc()).limit(500).all()]


@router.get("/asientos/{asiento_id}", response_model=AsientoOut)
def obtener_asiento(
    asiento_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    a = db.query(AsientoContable).filter(
        AsientoContable.id == asiento_id, AsientoContable.empresa_id == payload["empresa_id"],
    ).first()
    if not a:
        raise HTTPException(status_code=404, detail="Asiento no encontrado")
    return _asiento_out(db, a)


@router.post("/asientos/manual", response_model=AsientoOut, status_code=201)
def crear_asiento_manual(
    body: AsientoCreate, payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "crear_asiento")
    lineas = [
        contab.LineaAsiento(
            cuenta_id=ln.cuenta_id, debito=ln.debito, credito=ln.credito,
            centro_costo_id=ln.centro_costo_id, glosa=ln.glosa,
        ) for ln in body.lineas
    ]
    asiento = contab.registrar_asiento(
        db=db, empresa_id=payload["empresa_id"], fecha=body.fecha,
        descripcion=body.descripcion, origen="manual", lineas=lineas,
        referencia_id=body.referencia_id, creado_por_id=_empleado_id(db, payload),
    )
    return _asiento_out(db, asiento)


# ── Mayor + balance de comprobación ──────────────────────────────────────────
@router.get("/mayor/{cuenta_id}")
def mayor_de_cuenta(
    cuenta_id: str,
    desde: Optional[date] = Query(None), hasta: Optional[date] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    cuenta = db.query(CuentaContable).filter(
        CuentaContable.id == cuenta_id, CuentaContable.empresa_id == payload["empresa_id"],
    ).first()
    if not cuenta:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada")
    q = (
        db.query(AsientoContable.numero, AsientoContable.fecha, AsientoContable.descripcion,
                 AsientoLinea.debito, AsientoLinea.credito, AsientoLinea.glosa)
        .join(AsientoLinea, AsientoLinea.asiento_id == AsientoContable.id)
        .filter(AsientoContable.empresa_id == payload["empresa_id"], AsientoLinea.cuenta_id == cuenta_id)
    )
    if desde:
        q = q.filter(AsientoContable.fecha >= desde)
    if hasta:
        q = q.filter(AsientoContable.fecha <= hasta)
    movimientos = [
        {"numero": n, "fecha": f.isoformat(), "descripcion": d,
         "debito": str(deb), "credito": str(cre), "glosa": g}
        for n, f, d, deb, cre, g in q.order_by(AsientoContable.fecha, AsientoContable.numero).all()
    ]
    saldo = contab.obtener_saldo_cuenta(db, payload["empresa_id"], cuenta_id, desde, hasta)
    return {
        "cuenta": {"id": str(cuenta.id), "codigo": cuenta.codigo, "nombre": cuenta.nombre,
                   "naturaleza": cuenta.naturaleza},
        "movimientos": movimientos,
        "saldo": str(saldo),
    }


@router.get("/balance-comprobacion", response_model=BalanceComprobacionOut)
def balance_comprobacion(
    periodo_id: str = Query(...),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    periodo = db.query(PeriodoContable).filter(
        PeriodoContable.id == periodo_id, PeriodoContable.empresa_id == payload["empresa_id"],
    ).first()
    if not periodo:
        raise HTTPException(status_code=404, detail="Periodo no encontrado")
    filas = contab.balance_comprobacion(db, payload["empresa_id"], periodo_id)
    total_deudor = sum((f["saldo_deudor"] for f in filas), Decimal("0.00"))
    total_acreedor = sum((f["saldo_acreedor"] for f in filas), Decimal("0.00"))
    return BalanceComprobacionOut(
        periodo_id=periodo_id,
        filas=[BalanceComprobacionFila(**f) for f in filas],
        total_deudor=total_deudor,
        total_acreedor=total_acreedor,
        cuadra=(total_deudor == total_acreedor),
    )


# ── Configuración contable y cierre de ejercicio (Fase 11) ───────────────────
from pydantic import BaseModel  # noqa: E402  (schemas locales, patrón eventos_contables)
from ..services import cierre_ejercicio_service as cierre  # noqa: E402


class ConfigContableOut(BaseModel):
    cuenta_cierre_codigo: str
    cuenta_utilidad_codigo: str
    cuenta_perdida_codigo: str


class ConfigContableIn(BaseModel):
    cuenta_cierre_codigo: Optional[str] = None
    cuenta_utilidad_codigo: Optional[str] = None
    cuenta_perdida_codigo: Optional[str] = None


def _config_out(cfg) -> ConfigContableOut:
    return ConfigContableOut(
        cuenta_cierre_codigo=cfg.cuenta_cierre_codigo,
        cuenta_utilidad_codigo=cfg.cuenta_utilidad_codigo,
        cuenta_perdida_codigo=cfg.cuenta_perdida_codigo,
    )


@router.get("/configuracion", response_model=ConfigContableOut)
def obtener_configuracion(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return _config_out(cierre.obtener_config(db, payload["empresa_id"]))


@router.put("/configuracion", response_model=ConfigContableOut)
def actualizar_configuracion(
    datos: ConfigContableIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "configurar")
    cfg = cierre.actualizar_config(db, payload["empresa_id"],
                                   datos.dict(exclude_unset=True))
    return _config_out(cfg)


@router.get("/ejercicios/{anio}")
def estado_ejercicio(
    anio: int,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return cierre.estado_ejercicio(db, payload["empresa_id"], anio)


@router.post("/ejercicios/{anio}/cerrar")
def cerrar_ejercicio(
    anio: int,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "cerrar_ejercicio")
    return cierre.cerrar_ejercicio(db, payload["empresa_id"], anio,
                                   creado_por_id=_empleado_id(db, payload))


@router.post("/ejercicios/{anio}/revertir-cierre")
def revertir_cierre_ejercicio(
    anio: int,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "cerrar_ejercicio")
    return cierre.revertir_cierre(db, payload["empresa_id"], anio,
                                  creado_por_id=_empleado_id(db, payload))


# ── Saldos iniciales / asiento de apertura (Fase 11) ─────────────────────────
from ..services import apertura_service as apertura  # noqa: E402


class LineaAperturaIn(BaseModel):
    cuenta_codigo: str
    monto: Decimal


class AperturaIn(BaseModel):
    fecha: date
    lineas: List[LineaAperturaIn]


@router.get("/apertura")
def estado_apertura(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "ver")
    return apertura.estado_apertura(db, payload["empresa_id"])


@router.post("/apertura")
def cargar_apertura(
    datos: AperturaIn,
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "cargar_apertura")
    return apertura.cargar_apertura(
        db, payload["empresa_id"], datos.fecha,
        [{"cuenta_codigo": l.cuenta_codigo, "monto": l.monto} for l in datos.lineas],
        creado_por_id=_empleado_id(db, payload),
    )


@router.post("/apertura/revertir")
def revertir_apertura(
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    exigir_permiso(db, payload, "contabilidad", "cargar_apertura")
    return apertura.revertir_apertura(db, payload["empresa_id"],
                                      creado_por_id=_empleado_id(db, payload))
