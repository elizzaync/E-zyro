# app/routers/permisos.py
import uuid
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Form, File, UploadFile
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.models.empleado import Empleado
from app.models.firma_digital import FirmaDigital
from app.models.historial_firma import HistorialFirma
from app.models.documento_firmado import DocumentoFirmado
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.auditoria import Auditoria
from app.core.security import verificar_token
from app.services.cloudinary_service import (
    subir_imagen_cloudinary,
    subir_pdf_bytes_cloudinary,
)
from app.services.cloudinary_paths import carpeta_firma

router = APIRouter(prefix="/permisos", tags=["Permisos"])

TIPOS_LABEL = {
    'permiso_personal':         'Permiso Personal',
    'comision_trabajo':         'Comisión de Trabajo',
    'cita_essalud':             'Cita Essalud / Clínica',
    'permanencia_capacitacion': 'Permanencia Capacitación',
    'permanencia_extra':        'Permanencia Extra (H)',
    'recuperacion':             'Recuperación (H)',
    'vacaciones':               'Vacaciones',
    'dias_libres':              'Día(s) Libre(s)',
    'transferencia':            'Transferencia',
    'otros':                    'Otros',
}

# Mapeo de IDs numéricos de Flutter hacia la Base de Datos
TIPO_DB_MAP = {
    '1': 'permiso_personal',
    '2': 'comision_trabajo',
    '3': 'cita_essalud',
    '4': 'permanencia_capacitacion',
    '5': 'permanencia_extra',
    '6': 'recuperacion',
    '7': 'vacaciones',
    '8': 'dias_libres',
    '9': 'transferencia',
    '10': 'otros',
}

MESES = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun",
         "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]


@router.get("/mis-solicitudes")
def mis_solicitudes(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    try:
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": []}

        solicitudes = (
            db.query(SolicitudLaboral)
            .filter(SolicitudLaboral.empleado_id == empleado.id)
            .order_by(SolicitudLaboral.created_at.desc())
            .all()
        )

        data = []
        for s in solicitudes:
            dt = s.created_at
            fecha_fmt = f"{dt.day} {MESES[dt.month]}, {dt.year}" if dt else ""
            data.append({
                "id":           f"PRM-{str(s.id)[:6].upper()}",
                "tipo":         s.tipo,
                "tipo_label":   TIPOS_LABEL.get(s.tipo, s.tipo),
                "estado":       s.estado,
                "fecha_inicio": str(s.fecha_inicio) if s.fecha_inicio else None,
                "fecha_fin":    str(s.fecha_fin)    if s.fecha_fin    else None,
                "fecha_emision": fecha_fmt,
                "descripcion":  s.descripcion,
                "url_pdf":      s.url_pdf,
                "observacion":  s.observacion,
            })

        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.post("/guardar-firma")
async def guardar_firma(
    firma_base64: str = Form(...),
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    try:
        usuario_id = current_user.get("id")
        empresa_id = current_user.get("empresa_id")

        _firma_folder = carpeta_firma(empresa_id, "permisos")
        firma_public_id = f"{_firma_folder}/firma_{usuario_id}"
        firma_url = subir_imagen_cloudinary(
            base64_data=firma_base64,
            folder=_firma_folder,
            public_id=f"firma_{usuario_id}",
        )

        firma_existente = db.query(FirmaDigital).filter(
            FirmaDigital.usuario_id == usuario_id
        ).first()

        if firma_existente:
            db.add(HistorialFirma(
                usuario_id           = usuario_id,
                empresa_id           = empresa_id,
                url_cloudinary       = firma_existente.url_cloudinary,
                public_id_cloudinary = firma_existente.public_id_cloudinary,
            ))
            firma_existente.url_cloudinary       = firma_url
            firma_existente.public_id_cloudinary = firma_public_id
            firma_existente.primera_vez          = False
            firma_existente.updated_at           = datetime.utcnow()
        else:
            db.add(FirmaDigital(
                usuario_id           = usuario_id,
                empresa_id           = empresa_id,
                url_cloudinary       = firma_url,
                public_id_cloudinary = firma_public_id,
                primera_vez          = True,
            ))

        db.commit()
        return {"status": "success", "data": {"url_firma": firma_url}}

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/mi-firma")
def obtener_mi_firma(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    try:
        usuario_id = current_user.get("id")
        firma = db.query(FirmaDigital).filter(
            FirmaDigital.usuario_id == usuario_id
        ).first()
        if not firma:
            return {"status": "success", "data": None}
        return {"status": "success", "data": {"url_firma": firma.url_cloudinary}}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/historial-firmas")
def obtener_historial_firmas(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    try:
        usuario_id = current_user.get("id")
        historial = db.query(HistorialFirma).filter(
            HistorialFirma.usuario_id == usuario_id
        ).all()
        return {
            "status": "success", 
            "data": [{"url_firma": h.url_cloudinary} for h in historial]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.post("/enviar-solicitud")
async def enviar_solicitud(
    # ── Archivo PDF generado en el cliente ────────────────────────
    pdf_file: UploadFile = File(...),

    # ── Campos del formulario ─────────────────────────────────────
    tipo:        str           = Form(...),
    tipo_label:  str           = Form(...),
    fecha_inicio: Optional[str] = Form(None),
    fecha_fin:   Optional[str] = Form(None),
    hora_inicio: Optional[str] = Form(None),
    hora_fin:    Optional[str] = Form(None),
    motivo:      Optional[str] = Form(None),
    lugar_destino: Optional[str] = Form(None),
    total_dias:  Optional[str] = Form(None),

    current_user: dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    try:
        usuario_id = current_user.get("id")
        empresa_id = current_user.get("empresa_id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            raise HTTPException(status_code=404, detail="Empleado no encontrado")

        # ── 1. Obtener firma existente (guardada previamente via /guardar-firma)
        firma_existente = db.query(FirmaDigital).filter(
            FirmaDigital.usuario_id == usuario_id
        ).first()

        # ── 2. Parsear fechas y números ───────────────────────────────────
        def parse_date(s: Optional[str]) -> Optional[date]:
            if not s:
                return None
            try:
                return date.fromisoformat(s)
            except ValueError:
                return None

        fecha_inicio_dt = parse_date(fecha_inicio)
        fecha_fin_dt    = parse_date(fecha_fin)

        # ── 3. Subir PDF a Cloudinary (resource_type raw)
        content_type = (pdf_file.content_type or "").split(";")[0].strip().lower()
        if content_type not in {"application/pdf", "application/octet-stream"}:
            raise HTTPException(status_code=422, detail="Solo se aceptan archivos PDF")
        pdf_bytes = await pdf_file.read()
        if len(pdf_bytes) > 10 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="El PDF supera el límite de 10 MB")
        pdf_uid       = uuid.uuid4().hex[:12]
        pdf_public_id = f"e-zyro/permisos/permiso_{str(empleado.id)}_{pdf_uid}"
        pdf_url       = subir_pdf_bytes_cloudinary(pdf_bytes, pdf_public_id)

        # ── 4. Construir descripción ──────────────────────────────────────
        label_display = tipo_label if tipo_label else TIPOS_LABEL.get(tipo, "Trámite Laboral")
        partes = [label_display]
        if motivo:
            partes.append(f"Motivo: {motivo[:200]}")
        if hora_inicio and hora_fin:
            partes.append(f"Horario: {hora_inicio} - {hora_fin}")
        if total_dias:
            partes.append(f"Días: {total_dias}")
        if lugar_destino:
            partes.append(f"Lugar: {lugar_destino}")
        descripcion = " | ".join(partes)[:500]

        # ── 5. Crear SolicitudLaboral ─────────────────────────────────────
        # NOTA: el campo tipo se guarda tal cual llega del frontend.
        # Asegúrate de que el constraint chk_solicitud_tipo en PostgreSQL
        # esté actualizado para aceptar los valores exactos del frontend.
        tipo_db = TIPO_DB_MAP.get(tipo, tipo) # Mapea "1" a "permiso_personal", si no existe guarda el original
        solicitud = SolicitudLaboral(
            empleado_id  = empleado.id,
            empresa_id   = empresa_id,
            tipo         = tipo_db,
            estado       = 'pendiente',
            descripcion  = descripcion,
            fecha_inicio = fecha_inicio_dt,
            fecha_fin    = fecha_fin_dt,
            url_pdf      = pdf_url,
            public_id_pdf= pdf_public_id,
        )
        db.add(solicitud)
        db.flush()

        # ── 6. Registrar DocumentoFirmado ─────────────────────────────────
        if firma_existente and firma_existente.id:
            db.add(DocumentoFirmado(
                firma_id        = firma_existente.id,
                empresa_id      = empresa_id,
                documento_id    = str(solicitud.id),
                tabla_documento = "solicitud_laboral",
            ))

        # ── 7. Registrar en Auditoría ─────────────────────────────────────
        datos_nuevos = {
            "tipo":         tipo_db,
            "tipo_label":   label_display,
            "estado":       "pendiente",
            "fecha_inicio": str(fecha_inicio_dt) if fecha_inicio_dt else None,
            "url_pdf":      pdf_url,
        }

        db.add(Auditoria(
            id             = str(uuid.uuid4()),
            empresa_id     = empresa_id,
            usuario_id     = usuario_id,
            tabla_afectada = "solicitud_laboral",
            registro_id    = str(solicitud.id),
            accion         = "INSERT",
            modulo         = "Permisos",
            descripcion    = f"Solicitud de {label_display} enviada",
            datos_nuevos   = datos_nuevos,
        ))

        db.commit()

        # ── 8. Respuesta ──────────────────────────────────────────────────
        hoy        = date.today()
        fecha_fmt  = f"{hoy.day} {MESES[hoy.month]}, {hoy.year}"
        id_display = f"PRM-{str(solicitud.id)[:6].upper()}"

        return {
            "status": "success",
            "data": {
                "id":           id_display,
                "tipo":         label_display,
                "fechaEmision": fecha_fmt,
                "estadoActual": "enviado",
                "url_pdf":      pdf_url,
            },
        }

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error interno del servidor")
