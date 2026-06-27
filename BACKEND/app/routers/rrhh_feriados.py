"""
Gestión de Feriados por Empresa

Endpoints:
  GET    /rrhh/feriados              lista feriados del año para la empresa
  POST   /rrhh/feriados              crea un feriado
  DELETE /rrhh/feriados/{id}         elimina un feriado
  GET    /rrhh/feriados/nacionales   feriados nacionales del Perú por año
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token
from app.core.permisos import exigir_no_tecnico
from app.models.feriado_empresa import FeriadoEmpresa

router = APIRouter(tags=["RRHH · Feriados"])

# ── Feriados nacionales del Perú (fijos + movibles comunes) ──────────────────
# Formato: (mes, dia, nombre)  — los movibles se ajustan por año cuando aplica.
_FERIADOS_PE_FIJOS = [
    (1,  1,  "Año Nuevo"),
    (5,  1,  "Día del Trabajo"),
    (6,  29, "San Pedro y San Pablo"),
    (7,  23, "Día de la Fuerza Aérea"),
    (7,  28, "Fiestas Patrias — Independencia"),
    (7,  29, "Fiestas Patrias — Gran Unidad Nacional"),
    (8,  6,  "Batalla de Junín"),
    (8,  30, "Santa Rosa de Lima"),
    (10, 8,  "Combate de Angamos"),
    (11, 1,  "Todos los Santos"),
    (12, 8,  "Inmaculada Concepción"),
    (12, 9,  "Batalla de Ayacucho"),
    (12, 25, "Navidad"),
]

# Semana Santa es móvil — incluimos solo si el anio es solicitado.
# Calculado con el algoritmo de Butcher.
def _semana_santa(anio: int) -> list[tuple[int, int, str]]:
    a = anio % 19
    b, c = divmod(anio, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    mes = (h + l - 7 * m + 114) // 31
    dia = ((h + l - 7 * m + 114) % 31) + 1
    # Jueves Santo = 2 días antes, Viernes Santo = 1 día antes
    from datetime import timedelta
    pascua = date(anio, mes, dia)
    jueves = pascua - timedelta(days=3)
    viernes = pascua - timedelta(days=2)
    return [
        (jueves.month,  jueves.day,  "Jueves Santo"),
        (viernes.month, viernes.day, "Viernes Santo"),
    ]


def _feriados_nacionales(anio: int) -> list[dict]:
    items = [(m, d, n) for m, d, n in _FERIADOS_PE_FIJOS]
    items += _semana_santa(anio)
    result = []
    for mes, dia, nombre in sorted(items, key=lambda x: (x[0], x[1])):
        try:
            result.append({
                "fecha": date(anio, mes, dia).isoformat(),
                "nombre": nombre,
                "tipo": "nacional",
            })
        except ValueError:
            pass
    return result


# ── Schemas ───────────────────────────────────────────────────────────────────

class FeriadoIn(BaseModel):
    fecha:  date
    nombre: str
    tipo:   str = "empresa"   # 'nacional' | 'empresa'


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/rrhh/feriados/nacionales")
def listar_nacionales(
    anio: int = Query(default=None, ge=2020, le=2100),
):
    """Devuelve los feriados nacionales del Perú para el año indicado."""
    year = anio or date.today().year
    return {"feriados": _feriados_nacionales(year)}


@router.get("/rrhh/feriados")
def listar_feriados(
    anio:    Optional[int] = Query(default=None, ge=2020, le=2100),
    db:      Session       = Depends(get_db),
    payload: dict          = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]
    year = anio or date.today().year

    items = (
        db.query(FeriadoEmpresa)
        .filter(
            FeriadoEmpresa.empresa_id == empresa_id,
            FeriadoEmpresa.fecha >= date(year, 1, 1),
            FeriadoEmpresa.fecha <= date(year, 12, 31),
        )
        .order_by(FeriadoEmpresa.fecha)
        .all()
    )
    return {
        "feriados": [
            {
                "id":     f.id,
                "fecha":  f.fecha.isoformat(),
                "nombre": f.nombre,
                "tipo":   f.tipo,
            }
            for f in items
        ]
    }


@router.post("/rrhh/feriados", status_code=201)
def crear_feriado(
    body:    FeriadoIn,
    db:      Session = Depends(get_db),
    payload: dict    = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]
    user_id    = payload.get("sub") or payload.get("usuario_id") or ""

    # Verificar duplicado
    existe = (
        db.query(FeriadoEmpresa)
        .filter(FeriadoEmpresa.empresa_id == empresa_id,
                FeriadoEmpresa.fecha == body.fecha)
        .first()
    )
    if existe:
        raise HTTPException(400, f"Ya existe un feriado para el {body.fecha.isoformat()}")

    feriado = FeriadoEmpresa(
        empresa_id = empresa_id,
        fecha      = body.fecha,
        nombre     = body.nombre.strip(),
        tipo       = body.tipo,
        created_by = user_id,
    )
    db.add(feriado)
    db.commit()
    db.refresh(feriado)
    return {
        "id":     feriado.id,
        "fecha":  feriado.fecha.isoformat(),
        "nombre": feriado.nombre,
        "tipo":   feriado.tipo,
    }


@router.delete("/rrhh/feriados/{feriado_id}", status_code=200)
def eliminar_feriado(
    feriado_id: str,
    db:      Session = Depends(get_db),
    payload: dict    = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    feriado = (
        db.query(FeriadoEmpresa)
        .filter(FeriadoEmpresa.id == feriado_id,
                FeriadoEmpresa.empresa_id == empresa_id)
        .first()
    )
    if not feriado:
        raise HTTPException(404, "Feriado no encontrado")
    db.delete(feriado)
    db.commit()
    return {"mensaje": "Feriado eliminado"}
