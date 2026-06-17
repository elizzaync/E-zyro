"""
HU-30 Fase 1 — Legajo Digital y Firma Electrónica

Endpoints:
  GET  /rrhh/legajo/empleados                 lista empleados + conteo de docs (paginado)
  GET  /rrhh/legajo/{empleado_id}             detalle empleado + documentos
  GET  /rrhh/legajo/{empleado_id}/documentos  solo documentos (paginado)
  POST /rrhh/legajo/{empleado_id}/documento   subir PDF (admin)
  DELETE /rrhh/documento/{doc_id}             eliminar doc (admin)
  POST /rrhh/documento/{doc_id}/firmar        empleado firma su doc
  GET  /rrhh/mis-documentos-pendientes        docs pendientes de firma (self)
  GET  /rrhh/mi-firma                         firma digital del usuario actual
"""
from __future__ import annotations

import io
import uuid as _uuid
from datetime import datetime
from typing import Optional

import cloudinary.uploader as _cu
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile
from sqlalchemy import exists, and_, func
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.core.security import verificar_token
from app.core.permisos import exigir_no_tecnico, exigir_solo_admin
from app.models.empleado import Empleado
from app.models.usuario import Usuario
from app.models.documento_laboral import DocumentoLaboral
from app.models.firma_digital import FirmaDigital
from app.models.documento_firmado import DocumentoFirmado
from app.models.notificacion import Notificacion
from app.services.fcm_service import notificar_usuario

router = APIRouter(tags=["RRHH · Legajo"])

_MAX_BYTES = 20 * 1024 * 1024  # 20 MB

# Tipos que requieren firma automáticamente
_TIPOS_CON_FIRMA = {"contrato"}


# ── Helpers ──────────────────────────────────────────────────────────────────

def _empusr_dict(emp: Empleado, usr: Usuario, docs_count: int, ultima_fecha) -> dict:
    nombre = f"{usr.nombre} {usr.apellido}".strip()
    iniciales = (
        (usr.nombre[0] if usr.nombre else "") +
        (usr.apellido[0] if usr.apellido else "")
    ).upper() or "?"
    return {
        "id": emp.id,
        "nombreCompleto": nombre,
        "cargo": emp.cargo,
        "area": emp.area or "",
        "estado": "Activo" if emp.activo else "Inactivo",
        "documentosCount": docs_count,
        "iniciales": iniciales,
        "fotoUrl": usr.foto_url or "",
        "ultimaActualizacion": ultima_fecha.strftime("%d/%m/%Y") if ultima_fecha else "—",
        "fechaIngreso": emp.fecha_ingreso.isoformat() if emp.fecha_ingreso else None,
    }


def _doc_dict(doc: DocumentoLaboral, firmado: bool, firmado_en) -> dict:
    # firma_estado derivado: solo aplica para docs que requieren firma
    if not doc.requiere_firma:
        firma_estado = "no_aplica"
    elif firmado:
        firma_estado = "firmado"
    else:
        firma_estado = "pendiente"

    return {
        "id": doc.id,
        "tipo": doc.tipo,
        "nombre": doc.nombre,
        "url_archivo": doc.url_archivo or "",
        "fecha_emision": doc.fecha_emision.isoformat() if doc.fecha_emision else None,
        "created_at": doc.created_at.isoformat() if doc.created_at else None,
        "requiere_firma": doc.requiere_firma,
        "firma_estado": firma_estado,
        "firmado": firmado,
        "firmado_en": firmado_en.isoformat() if firmado_en else None,
    }


# ── 1. GET /rrhh/legajo/empleados ────────────────────────────────────────────

@router.get("/rrhh/legajo/empleados")
def listar_empleados(
    page:  int = Query(1,  ge=1),
    limit: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    total_q = (
        db.query(func.count(Empleado.id))
        .filter(Empleado.empresa_id == empresa_id)
        .scalar()
    )

    rows = (
        db.query(Empleado, Usuario)
        .join(Usuario, Usuario.id == Empleado.usuario_id)
        .filter(Empleado.empresa_id == empresa_id)
        .order_by(Usuario.nombre, Usuario.apellido)
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    emp_ids = [e.id for e, _ in rows]
    counts: dict = {}
    last_dates: dict = {}
    if emp_ids:
        for eid, cnt in (
            db.query(DocumentoLaboral.empleado_id, func.count(DocumentoLaboral.id))
            .filter(DocumentoLaboral.empleado_id.in_(emp_ids))
            .group_by(DocumentoLaboral.empleado_id)
            .all()
        ):
            counts[eid] = cnt
        for eid, dt in (
            db.query(DocumentoLaboral.empleado_id, func.max(DocumentoLaboral.created_at))
            .filter(DocumentoLaboral.empleado_id.in_(emp_ids))
            .group_by(DocumentoLaboral.empleado_id)
            .all()
        ):
            last_dates[eid] = dt

    return {
        "empleados": [
            _empusr_dict(emp, usr, counts.get(emp.id, 0), last_dates.get(emp.id))
            for emp, usr in rows
        ],
        "total": total_q,
        "page": page,
        "limit": limit,
        "total_paginas": max(1, -(-total_q // limit)),  # ceil division
    }


# ── 2. GET /rrhh/legajo/{empleado_id} ────────────────────────────────────────

@router.get("/rrhh/legajo/{empleado_id}")
def detalle_empleado(
    empleado_id: str,
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    usr = db.query(Usuario).filter(Usuario.id == emp.usuario_id).first()
    if not usr:
        raise HTTPException(status_code=404, detail="Usuario del empleado no encontrado")

    docs = (
        db.query(DocumentoLaboral)
        .filter(
            DocumentoLaboral.empleado_id == empleado_id,
            DocumentoLaboral.empresa_id == empresa_id,
        )
        .order_by(DocumentoLaboral.created_at.desc())
        .all()
    )

    doc_ids = [d.id for d in docs]
    firmado_map: dict = {}
    if doc_ids:
        for did, dt in (
            db.query(DocumentoFirmado.documento_id, DocumentoFirmado.firmado_en)
            .filter(
                DocumentoFirmado.documento_id.in_(doc_ids),
                DocumentoFirmado.tabla_documento == "documento_laboral",
            )
            .all()
        ):
            firmado_map[did] = dt

    nombre = f"{usr.nombre} {usr.apellido}".strip()
    iniciales = (
        (usr.nombre[0] if usr.nombre else "") +
        (usr.apellido[0] if usr.apellido else "")
    ).upper() or "?"

    contratos_count = sum(1 for d in docs if d.tipo.strip().lower() == "contrato")
    firmados_count  = len(firmado_map)
    pendientes_count = sum(
        1 for d in docs
        if d.requiere_firma and d.id not in firmado_map
    )

    return {
        "empleado": {
            "id": emp.id,
            "usuarioId": emp.usuario_id,
            "nombreCompleto": nombre,
            "cargo": emp.cargo,
            "area": emp.area or "",
            "estado": "Activo" if emp.activo else "Inactivo",
            "fotoUrl": usr.foto_url or "",
            "iniciales": iniciales,
            "fechaIngreso": emp.fecha_ingreso.isoformat() if emp.fecha_ingreso else None,
        },
        "documentos": [
            _doc_dict(d, d.id in firmado_map, firmado_map.get(d.id))
            for d in docs
        ],
        "stats": {
            "total":    len(docs),
            "contratos": contratos_count,
            "firmados": firmados_count,
            "pendientes_firma": pendientes_count,
        },
    }


# ── 2b. GET /rrhh/legajo/{empleado_id}/documentos ───────────────────────────

_MESES_ES = [
    "", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
]

@router.get("/rrhh/legajo/{empleado_id}/documentos")
def listar_documentos_empleado(
    empleado_id: str,
    categoria: Optional[str] = Query(None, description="Filtrar por categoría: contratos|certificaciones|otros"),
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_no_tecnico(payload)
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    q = (
        db.query(DocumentoLaboral)
        .filter(
            DocumentoLaboral.empleado_id == empleado_id,
            DocumentoLaboral.empresa_id == empresa_id,
        )
        .order_by(DocumentoLaboral.fecha_emision.desc(), DocumentoLaboral.created_at.desc())
    )

    docs = q.all()

    # Filtrar por categoría en Python (tipos son texto libre)
    if categoria == "contratos":
        docs = [d for d in docs if d.tipo.strip().lower() == "contrato"]
    elif categoria == "certificaciones":
        docs = [d for d in docs if d.tipo.strip().lower() in ("certificado", "constancia")]
    elif categoria == "otros":
        docs = [d for d in docs if d.tipo.strip().lower() not in (
            "contrato", "certificado", "constancia")]

    doc_ids = [d.id for d in docs]
    firmado_map: dict = {}
    if doc_ids:
        for did, dt in (
            db.query(DocumentoFirmado.documento_id, DocumentoFirmado.firmado_en)
            .filter(
                DocumentoFirmado.documento_id.in_(doc_ids),
                DocumentoFirmado.tabla_documento == "documento_laboral",
            )
            .all()
        ):
            firmado_map[did] = dt

    return {
        "documentos": [_doc_dict(d, d.id in firmado_map, firmado_map.get(d.id)) for d in docs],
        "total": len(docs),
    }


# ── 3. POST /rrhh/legajo/{empleado_id}/documento ─────────────────────────────

@router.post("/rrhh/legajo/{empleado_id}/documento", status_code=201)
async def subir_documento(
    empleado_id: str,
    tipo: str = Form(...),
    nombre: str = Form(...),
    fecha_emision: str = Form(...),
    requiere_firma: bool = Form(False),
    mes: Optional[int] = Form(None, ge=1, le=12),
    anio: Optional[int] = Form(None, ge=2000, le=2100),
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_solo_admin(payload, "Solo administradores pueden subir documentos al legajo")
    empresa_id = payload["empresa_id"]

    emp = db.query(Empleado).filter(
        Empleado.id == empleado_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    content_type = (archivo.content_type or "").split(";")[0].strip().lower()
    if content_type != "application/pdf":
        raise HTTPException(status_code=422, detail="Solo se permiten archivos PDF")

    contenido = await archivo.read()
    if len(contenido) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="El archivo supera los 20 MB")

    try:
        result = _cu.upload(
            io.BytesIO(contenido),
            folder=f"e-zyro/{empresa_id}/legajos/{empleado_id}",
            resource_type="auto",   # PDFs se sirven inline en el navegador
        )
        url = result.get("secure_url", "")
        public_id = result.get("public_id", "")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Error al subir el archivo: {exc}")

    try:
        fecha_dt = datetime.strptime(fecha_emision, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=422, detail="Formato de fecha inválido. Use YYYY-MM-DD")

    nombre_final = nombre.strip() or nombre
    tipo_norm = tipo.strip().lower().replace(" ", "_")
    if tipo_norm == "boleta_mensual" and mes and anio:
        if not nombre.strip():
            nombre_final = f"Boleta de Pago - {_MESES_ES[mes]} {anio}"
        from datetime import date as _date
        fecha_dt = _date(anio, mes, 1)

    # Contratos siempre requieren firma, sin importar el valor enviado
    es_contrato = tipo.strip().lower() == "contrato"
    firma_requerida = es_contrato or requiere_firma

    doc = DocumentoLaboral(
        id=str(_uuid.uuid4()),
        empleado_id=empleado_id,
        empresa_id=empresa_id,
        tipo=tipo,
        nombre=nombre_final,
        url_archivo=url,
        public_id_cloudinary=public_id,
        fecha_emision=fecha_dt,
        requiere_firma=firma_requerida,
        created_at=datetime.utcnow(),
    )
    db.add(doc)
    db.flush()

    if firma_requerida:
        if es_contrato:
            msg = (
                f"Tienes un contrato pendiente de firma: «{nombre_final}». "
                "Por favor revisa tu expediente."
            )
        else:
            msg = f"El documento «{nombre_final}» está disponible para tu firma electrónica."

        notificar_usuario(
            db,
            empresa_id=empresa_id,
            usuario_id=emp.usuario_id,
            titulo="Contrato pendiente de firma" if es_contrato else "Documento pendiente de firma",
            mensaje=msg,
            tipo="firma_documento",
            categoria="firma_documento",
            referencia_id=None,
            referencia_tabla=doc.id,
        )

    db.commit()
    return {
        "id": doc.id,
        "url_archivo": url,
        "requiere_firma": firma_requerida,
        "mensaje": "Documento subido con éxito",
    }


# ── 4. DELETE /rrhh/documento/{doc_id} ───────────────────────────────────────

@router.delete("/rrhh/documento/{doc_id}")
def eliminar_documento(
    doc_id: str,
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    exigir_solo_admin(payload, "Solo administradores pueden eliminar documentos")
    empresa_id = payload["empresa_id"]

    doc = db.query(DocumentoLaboral).filter(
        DocumentoLaboral.id == doc_id, DocumentoLaboral.empresa_id == empresa_id
    ).first()
    if not doc:
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    if doc.public_id_cloudinary:
        try:
            rtype = "image" if "/image/upload/" in (doc.url_archivo or "") else "raw"
            _cu.destroy(doc.public_id_cloudinary, resource_type=rtype, invalidate=True)
        except Exception:
            pass

    db.query(DocumentoFirmado).filter(
        DocumentoFirmado.documento_id == doc_id,
        DocumentoFirmado.tabla_documento == "documento_laboral",
    ).delete()

    db.delete(doc)
    db.commit()
    return {"mensaje": "Documento eliminado"}


# ── 5. POST /rrhh/documento/{doc_id}/firmar ──────────────────────────────────

@router.post("/rrhh/documento/{doc_id}/firmar")
def firmar_documento(
    doc_id: str,
    request: Request,
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    doc = db.query(DocumentoLaboral).filter(
        DocumentoLaboral.id == doc_id, DocumentoLaboral.empresa_id == empresa_id
    ).first()
    if not doc:
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    if not doc.requiere_firma:
        raise HTTPException(status_code=422, detail="Este documento no requiere firma")

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        raise HTTPException(status_code=403, detail="No tienes un empleado asociado en esta empresa")

    if doc.empleado_id != emp.id:
        raise HTTPException(status_code=403, detail="No puedes firmar documentos de otro empleado")

    ya_firmado = db.query(DocumentoFirmado).filter(
        DocumentoFirmado.documento_id == doc_id,
        DocumentoFirmado.tabla_documento == "documento_laboral",
    ).first()
    if ya_firmado:
        raise HTTPException(status_code=409, detail="Este documento ya fue firmado")

    firma = db.query(FirmaDigital).filter(
        FirmaDigital.usuario_id == usuario_id, FirmaDigital.empresa_id == empresa_id
    ).first()
    if not firma:
        raise HTTPException(status_code=422, detail="No tienes una firma digital registrada")

    ip = request.client.host if request.client else None
    firmado = DocumentoFirmado(
        id=str(_uuid.uuid4()),
        firma_id=firma.id,
        empresa_id=empresa_id,
        documento_id=doc_id,
        tabla_documento="documento_laboral",
        firmado_en=datetime.utcnow(),
        ip_firma=ip,
    )
    db.add(firmado)

    db.query(Notificacion).filter(
        Notificacion.usuario_id == usuario_id,
        Notificacion.referencia_tabla == doc_id,
        Notificacion.leido == False,
    ).update({"leido": True})

    db.commit()
    return {
        "mensaje": "Documento firmado correctamente",
        "firmado_en": firmado.firmado_en.isoformat(),
    }


# ── 6. GET /rrhh/mis-documentos-pendientes ───────────────────────────────────

@router.get("/rrhh/mis-documentos-pendientes")
def mis_documentos_pendientes(
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    emp = db.query(Empleado).filter(
        Empleado.usuario_id == usuario_id, Empleado.empresa_id == empresa_id
    ).first()
    if not emp:
        return {"documentos": []}

    pendientes = (
        db.query(DocumentoLaboral)
        .filter(
            DocumentoLaboral.empleado_id == emp.id,
            DocumentoLaboral.empresa_id == empresa_id,
            DocumentoLaboral.requiere_firma == True,
            ~exists().where(
                and_(
                    DocumentoFirmado.documento_id == DocumentoLaboral.id,
                    DocumentoFirmado.tabla_documento == "documento_laboral",
                )
            ),
        )
        .order_by(DocumentoLaboral.created_at.desc())
        .all()
    )

    return {"documentos": [_doc_dict(d, False, None) for d in pendientes]}


# ── 7. GET /rrhh/mi-firma ────────────────────────────────────────────────────

@router.get("/rrhh/mi-firma")
def mi_firma(
    db: Session = Depends(get_db),
    payload: dict = Depends(verificar_token),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    firma = db.query(FirmaDigital).filter(
        FirmaDigital.usuario_id == usuario_id, FirmaDigital.empresa_id == empresa_id
    ).first()

    if not firma:
        return {"firma": None}

    return {
        "firma": {
            "id": firma.id,
            "url_cloudinary": firma.url_cloudinary,
            "primera_vez": firma.primera_vez,
        }
    }
