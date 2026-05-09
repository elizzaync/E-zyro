# app/routers/permisos.py
import uuid
import json
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

MESES = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun",
         "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]


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
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/enviar-solicitud")
def enviar_solicitud(
    # ── Archivo PDF generado en el cliente (pdf-lib) ──────────────
    pdf_file: UploadFile = File(...),

    # ── Campos del formulario ─────────────────────────────────────
    tipo:             str           = Form(...),
    tipo_label:       str           = Form(...),
    firma_base64:     str           = Form(...),
    fecha_inicio:     Optional[str] = Form(None),
    fecha_fin:        Optional[str] = Form(None),
    hora_inicio:      Optional[str] = Form(None),
    hora_fin:         Optional[str] = Form(None),
    motivo:           Optional[str] = Form(None),
    lugar_destino:    Optional[str] = Form(None),
    adjunto_nombre:   Optional[str] = Form(None),
    horas_calculadas: Optional[str] = Form(None),  # llega como string desde FormData
    total_dias:       Optional[str] = Form(None),  # llega como string desde FormData

    current_user: dict    = Depends(verificar_token),
    db:           Session = Depends(get_db),
):
    try:
        usuario_id = current_user.get("id")
        empresa_id = current_user.get("empresa_id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            raise HTTPException(status_code=404, detail="Empleado no encontrado")

        # ── 1. Gestión de la firma digital ───────────────────────────────
        firma_url       = firma_base64
        firma_existente = db.query(FirmaDigital).filter(
            FirmaDigital.usuario_id == usuario_id
        ).first()

        if firma_base64.startswith("data:"):
            firma_public_id = f"e-zyro/firmas/firma_{usuario_id}"
            firma_url = subir_imagen_cloudinary(
                base64_data=firma_base64,
                folder="e-zyro/firmas",
                public_id=f"firma_{usuario_id}",
            )
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
                nueva_firma = FirmaDigital(
                    usuario_id           = usuario_id,
                    empresa_id           = empresa_id,
                    url_cloudinary       = firma_url,
                    public_id_cloudinary = firma_public_id,
                    primera_vez          = True,
                )
                db.add(nueva_firma)
                db.flush()
                firma_existente = nueva_firma
        # Si firma_base64 comienza con "http", es la URL ya guardada; no se re-sube.

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

        # ── 3. Subir PDF recibido a Cloudinary (resource_type raw, extensión .pdf)
        pdf_bytes     = pdf_file.file.read()
        pdf_uid       = uuid.uuid4().hex[:12]
        pdf_public_id = f"e-zyro/permisos/permiso_{empleado.id}_{pdf_uid}.pdf"
        pdf_url       = subir_pdf_bytes_cloudinary(pdf_bytes, pdf_public_id)

        # ── 4. Construir descripción ──────────────────────────────────────
        label_display = TIPOS_LABEL.get(tipo, tipo_label)
        partes = [tipo, label_display]
        if motivo:
            partes.append(motivo[:200])
        if lugar_destino:
            partes.append(f"Lugar: {lugar_destino}")
        descripcion = " | ".join(partes)[:500]

        # ── 5. Crear SolicitudLaboral ─────────────────────────────────────
        # NOTA: el campo tipo se guarda tal cual llega del frontend.
        # Asegúrate de que el constraint chk_solicitud_tipo en PostgreSQL
        # esté actualizado para aceptar los valores exactos del frontend.
        solicitud = SolicitudLaboral(
            empleado_id  = empleado.id,
            empresa_id   = empresa_id,
            tipo         = tipo,
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
                documento_id    = solicitud.id,
                tabla_documento = "solicitud_laboral",
            ))

        # ── 7. Registrar en Auditoría ─────────────────────────────────────
        datos_nuevos = json.dumps({
            "tipo":         tipo,
            "tipo_label":   label_display,
            "estado":       "pendiente",
            "fecha_inicio": str(fecha_inicio_dt),
            "url_pdf":      pdf_url,
        }, ensure_ascii=False)

        db.add(Auditoria(
            id             = str(uuid.uuid4()),
            empresa_id     = empresa_id,
            usuario_id     = usuario_id,
            tabla_afectada = "solicitud_laboral",
            registro_id    = solicitud.id,
            accion         = "INSERT",
            modulo         = "Permisos",
            descripcion    = f"Solicitud de {label_display} enviada",
            datos_nuevos   = datos_nuevos,
        ))

        db.commit()

        # ── 8. Respuesta ──────────────────────────────────────────────────
        hoy        = date.today()
        fecha_fmt  = f"{hoy.day} {MESES[hoy.month]}, {hoy.year}"
        id_display = f"PRM-{solicitud.id[:6].upper()}"

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
        raise HTTPException(status_code=500, detail=str(e))
