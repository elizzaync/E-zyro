"""
Motor de auditoría global y silencioso.

Intercepta INSERT / UPDATE / DELETE de cualquier modelo SQLAlchemy
y genera registros en la tabla `auditoria` dentro de la misma
transacción, sin contaminar la lógica de negocio.

El listener se registra automáticamente sobre SessionLocal
cuando este módulo es importado.
"""
from __future__ import annotations

import uuid
from datetime import datetime, date
from decimal import Decimal
from typing import Any

from sqlalchemy import event
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.orm import Session

from ..db.database import SessionLocal
from ..models.auditoria import Auditoria
from .audit_context import get_audit_context


# ── Modelos excluidos — evitan recursión y ruido ──────────────────────────────
_EXCLUIDAS: frozenset[str] = frozenset({
    "auditoria",
    "sesion_usuario",
    "lectura_mensaje",
    "mensaje_chat",
})

# ── Mapa tabla → módulo de negocio ────────────────────────────────────────────
_MODULO: dict[str, str] = {
    "usuario":               "USUARIOS",
    "empleado":              "EMPLEADOS",
    "empresa":               "EMPRESA",
    "rol":                   "SEGURIDAD",
    "permiso":               "SEGURIDAD",
    "rol_permiso":           "SEGURIDAD",
    "usuario_rol":           "SEGURIDAD",
    "usuario_permiso":       "SEGURIDAD",
    "contrato":              "RRHH",
    "solicitud_laboral":     "RRHH",
    "documento_laboral":     "RRHH",
    "proyecto":              "PROYECTOS",
    "proyecto_servicio":     "OPERACIONES",
    "procedimiento":         "OPERACIONES",
    "evidencia_procedimiento": "OPERACIONES",
    "registro_asistencia":   "ASISTENCIA",
    "requerimiento":         "REQUERIMIENTOS",
    "requerimiento_entrega": "REQUERIMIENTOS",
    "material":              "INVENTARIO",
    "movimiento_inventario": "INVENTARIO",
    "orden_compra":          "COMPRAS",
    "recepcion_compra":      "COMPRAS",
    "cliente":               "CLIENTES",
    "caja_chica":            "FINANZAS",
    "cuenta_bancaria":       "FINANZAS",
    "movimiento_bancario":   "FINANZAS",
    "equipo":                "MANTENIMIENTO",
    "orden_mantenimiento":   "MANTENIMIENTO",
    "comunicado":            "COMUNICADOS",
    "evaluacion":            "EVALUACIONES",
    "informe_tecnico":       "OPERACIONES",
}


# ── Serializador de un único propósito ────────────────────────────────────────

def _coerce(val: Any) -> Any:
    """Convierte tipos no nativos de JSON a sus equivalentes seguros."""
    if isinstance(val, uuid.UUID):          return str(val)
    if isinstance(val, (datetime, date)):   return val.isoformat()
    if isinstance(val, Decimal):            return float(val)
    return val


def _serialize_for_audit(obj: Any) -> dict[str, Any] | None:
    """
    Convierte un modelo ORM a dict compatible con PostgreSQL JSONB.
    Solo itera columnas mapeadas; ignora relaciones para evitar lazy-loads.
    """
    if obj is None:
        return None
    return {
        col.key: _coerce(getattr(obj, col.key, None))
        for col in sa_inspect(type(obj)).columns
    }


def _estado_anterior(obj: Any) -> dict[str, Any]:
    """
    Reconstruye el estado previo del objeto usando el history de SQLAlchemy.
    Para cada columna usa el valor eliminado del history si existe,
    o el valor actual como fallback.
    """
    insp = sa_inspect(obj)
    return {
        col.key: _coerce(
            insp.attrs[col.key].history.deleted[0]
            if insp.attrs[col.key].history.deleted
            else getattr(obj, col.key, None)
        )
        for col in sa_inspect(type(obj)).columns
    }


# ── Micro-helpers ─────────────────────────────────────────────────────────────

def _pk(obj: Any) -> str | None:
    """Extrae el valor de la PK como string (asume PK simple)."""
    for pk in sa_inspect(type(obj)).primary_key:
        val = getattr(obj, pk.key, None)
        return str(val) if val is not None else None
    return None


def _tiene_cambios(obj: Any) -> bool:
    """Retorna True solo si algún atributo mapeado cambió realmente."""
    insp = sa_inspect(obj)
    return any(
        insp.attrs[col.key].history.has_changes()
        for col in sa_inspect(type(obj)).columns
    )


def _auditable(obj: Any) -> bool:
    """Descarta modelos sin __tablename__ y los de la lista de exclusión."""
    return (
        hasattr(obj, "__tablename__")
        and obj.__tablename__ not in _EXCLUIDAS
    )


def _nuevo_registro(
    tabla:  str,
    pk:     str | None,
    accion: str,
    ant:    dict | None,
    nvo:    dict | None,
    ctx:    dict,
) -> Auditoria:
    return Auditoria(
        id               = str(uuid.uuid4()),
        empresa_id       = ctx["empresa_id"],
        usuario_id       = ctx["usuario_id"],
        tabla_afectada   = tabla,
        registro_id      = pk,
        accion           = accion,
        modulo           = _MODULO.get(tabla, tabla.upper()),
        datos_anteriores = ant,
        datos_nuevos     = nvo,
        ip               = ctx["ip"],
        fecha            = datetime.utcnow(),
    )


# ── Listener principal ────────────────────────────────────────────────────────

def capturar_auditoria(
    session:       Session,
    flush_context: Any,
    instances:     Any,
) -> None:
    """
    before_flush — genera registros de auditoría para INSERT / UPDATE / DELETE.
    Envuelto en try/except: un fallo aquí nunca interrumpe la operación de negocio.
    """
    try:
        ctx     = get_audit_context()
        lote: list[Auditoria] = []

        # ── INSERT ─────────────────────────────────────────────────────────
        for obj in list(session.new):
            if not _auditable(obj):
                continue
            lote.append(_nuevo_registro(
                obj.__tablename__, _pk(obj), "INSERT",
                None, _serialize_for_audit(obj), ctx,
            ))

        # ── UPDATE ─────────────────────────────────────────────────────────
        for obj in list(session.dirty):
            if not _auditable(obj) or not _tiene_cambios(obj):
                continue
            lote.append(_nuevo_registro(
                obj.__tablename__, _pk(obj), "UPDATE",
                _estado_anterior(obj), _serialize_for_audit(obj), ctx,
            ))

        # ── DELETE ─────────────────────────────────────────────────────────
        for obj in list(session.deleted):
            if not _auditable(obj):
                continue
            lote.append(_nuevo_registro(
                obj.__tablename__, _pk(obj), "DELETE",
                _serialize_for_audit(obj), None, ctx,
            ))

        if lote:
            session.add_all(lote)

    except Exception:  # noqa: BLE001
        pass  # auditoría silenciosa — nunca rompe la transacción de negocio


# ── Auto-registro sobre SessionLocal al importar ─────────────────────────────
event.listen(SessionLocal, "before_flush", capturar_auditoria)
