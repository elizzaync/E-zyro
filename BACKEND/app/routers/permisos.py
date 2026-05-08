# app/routers/permisos.py
import uuid
import json
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.models.empleado import Empleado
from app.models.firma_digital import FirmaDigital
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.auditoria import Auditoria
from app.core.security import verificar_token
from app.services.cloudinary_service import subir_imagen_cloudinary, subir_pdf_cloudinary

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


class SolicitudPermisoRequest(BaseModel):
    tipo:             str
    tipo_label:       str
    fecha_inicio:     Optional[str] = None
    fecha_fin:        Optional[str] = None
    hora_inicio:      Optional[str] = None
    hora_fin:         Optional[str] = None
    motivo:           Optional[str] = None
    lugar_destino:    Optional[str] = None
    horas_calculadas: Optional[float] = None
    total_dias:       Optional[int]   = None
    firma_base64:     str
    pdf_base64:       str
    adjunto_nombre:   Optional[str] = None


@router.get("/mi-firma")
def obtener_mi_firma(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
):
    try:
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": None}

        firma = db.query(FirmaDigital).filter(
            FirmaDigital.empleado_id == empleado.id
        ).first()

        if not firma:
            return {"status": "success", "data": None}

        return {"status": "success", "data": {"url_firma": firma.url_firma}}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/enviar-solicitud")
def enviar_solicitud(
    datos: SolicitudPermisoRequest,
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
):
    try:
        usuario_id = current_user.get("id")
        empresa_id = current_user.get("empresa_id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            raise HTTPException(status_code=404, detail="Empleado no encontrado")

        # ── 1. Gestión de la firma digital ───────────────────────────────
        firma_url = datos.firma_base64
        firma_existente = db.query(FirmaDigital).filter(
            FirmaDigital.empleado_id == empleado.id
        ).first()

        if datos.firma_base64.startswith("data:"):
            firma_public_id = f"e-zyro/firmas/firma_{empleado.id}"
            firma_url = subir_imagen_cloudinary(
                base64_data=datos.firma_base64,
                folder="e-zyro/firmas",
                public_id=f"firma_{empleado.id}"
            )
            if firma_existente:
                firma_existente.url_firma            = firma_url
                firma_existente.public_id_cloudinary = firma_public_id
                firma_existente.updated_at           = datetime.utcnow()
            else:
                db.add(FirmaDigital(
                    empleado_id          = empleado.id,
                    empresa_id           = empresa_id,
                    url_firma            = firma_url,
                    public_id_cloudinary = firma_public_id,
                ))
        # Si firma_base64 comienza con "http" es la URL guardada; no se re-sube.

        # ── 2. Subir PDF a Cloudinary ─────────────────────────────────────
        pdf_uid        = uuid.uuid4().hex[:12]
        pdf_public_id  = f"e-zyro/permisos/permiso_{empleado.id}_{pdf_uid}"
        pdf_url        = subir_pdf_cloudinary(datos.pdf_base64, pdf_public_id)

        # ── 3. Parsear fechas ─────────────────────────────────────────────
        def parse_date(s: Optional[str]) -> Optional[date]:
            if not s:
                return None
            try:
                return date.fromisoformat(s)
            except ValueError:
                return None

        fecha_inicio = parse_date(datos.fecha_inicio)
        fecha_fin    = parse_date(datos.fecha_fin)

        # ── 4. Construir descripción ──────────────────────────────────────
        partes = [TIPOS_LABEL.get(datos.tipo, datos.tipo_label)]
        if datos.motivo:
            partes.append(datos.motivo[:200])
        if datos.lugar_destino:
            partes.append(f"Lugar: {datos.lugar_destino}")
        descripcion = " | ".join(partes)[:500]

        # ── 5. Crear SolicitudLaboral ─────────────────────────────────────
        solicitud = SolicitudLaboral(
            empleado_id   = empleado.id,
            empresa_id    = empresa_id,
            tipo          = datos.tipo,
            estado        = 'pendiente',
            descripcion   = descripcion,
            fecha_inicio  = fecha_inicio,
            fecha_fin     = fecha_fin,
            url_pdf       = pdf_url,
            public_id_pdf = pdf_public_id,
        )
        db.add(solicitud)
        db.flush()

        # ── 6. Registrar en Auditoría ─────────────────────────────────────
        datos_nuevos = json.dumps({
            "tipo":         datos.tipo,
            "tipo_label":   TIPOS_LABEL.get(datos.tipo, datos.tipo_label),
            "estado":       "pendiente",
            "fecha_inicio": str(fecha_inicio),
            "url_pdf":      pdf_url,
        }, ensure_ascii=False)

        db.add(Auditoria(
            id              = str(uuid.uuid4()),
            empresa_id      = empresa_id,
            usuario_id      = usuario_id,
            tabla_afectada  = "solicitud_laboral",
            registro_id     = solicitud.id,
            accion          = "INSERT",
            modulo          = "Permisos",
            descripcion     = f"Solicitud de {TIPOS_LABEL.get(datos.tipo, datos.tipo_label)} enviada",
            datos_nuevos    = datos_nuevos,
        ))

        db.commit()

        # ── 7. Respuesta ──────────────────────────────────────────────────
        hoy        = date.today()
        fecha_fmt  = f"{hoy.day} {MESES[hoy.month]}, {hoy.year}"
        id_display = f"PRM-{solicitud.id[:6].upper()}"

        return {
            "status": "success",
            "data": {
                "id":           id_display,
                "tipo":         TIPOS_LABEL.get(datos.tipo, datos.tipo_label),
                "fechaEmision": fecha_fmt,
                "estadoActual": "enviado",
                "url_pdf":      pdf_url,
            }
        }

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
