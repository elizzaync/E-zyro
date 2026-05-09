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
from app.models.historial_firma import HistorialFirma
from app.models.documento_firmado import DocumentoFirmado
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.auditoria import Auditoria
from app.core.security import verificar_token
from app.services.cloudinary_service import (
    subir_imagen_cloudinary,
    subir_pdf_bytes_cloudinary,
)
from app.services.pdf_service import generar_pdf_solicitud

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

# Mapeo hacia los valores permitidos por chk_solicitud_tipo en BD:
#   'justificacion_falta' | 'permiso' | 'vacaciones' | 'adelanto' | 'otro'
TIPO_MAP_BD = {
    'vacaciones':          'vacaciones',
    'adelanto':            'adelanto',
    'justificacion_falta': 'justificacion_falta',
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
    adjunto_nombre:   Optional[str] = None


@router.get("/mi-firma")
def obtener_mi_firma(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
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
        firma_url       = datos.firma_base64
        firma_existente = db.query(FirmaDigital).filter(
            FirmaDigital.usuario_id == usuario_id
        ).first()

        if datos.firma_base64.startswith("data:"):
            firma_public_id = f"e-zyro/firmas/firma_{usuario_id}"
            firma_url = subir_imagen_cloudinary(
                base64_data=datos.firma_base64,
                folder="e-zyro/firmas",
                public_id=f"firma_{usuario_id}"
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
        # Si firma_base64 comienza con "http" es la URL guardada; no se re-sube.

        # ── 2. Parsear fechas ─────────────────────────────────────────────
        def parse_date(s: Optional[str]) -> Optional[date]:
            if not s:
                return None
            try:
                return date.fromisoformat(s)
            except ValueError:
                return None

        fecha_inicio = parse_date(datos.fecha_inicio)
        fecha_fin    = parse_date(datos.fecha_fin)

        # ── 3. Mapear tipo al valor permitido por el constraint BD ────────
        # chk_solicitud_tipo: 'justificacion_falta'|'permiso'|'vacaciones'|'adelanto'|'otro'
        tipo_bd     = TIPO_MAP_BD.get(datos.tipo, 'permiso')
        tipo_label  = TIPOS_LABEL.get(datos.tipo, datos.tipo_label)

        # ── 4. Construir descripción (tipo original al inicio para no perder detalle)
        partes = [datos.tipo]
        partes.append(tipo_label)
        if datos.motivo:
            partes.append(datos.motivo[:200])
        if datos.lugar_destino:
            partes.append(f"Lugar: {datos.lugar_destino}")
        descripcion = " | ".join(partes)[:500]

        # ── 5. Crear SolicitudLaboral (sin url_pdf aún) ───────────────────
        solicitud = SolicitudLaboral(
            empleado_id  = empleado.id,
            empresa_id   = empresa_id,
            tipo         = tipo_bd,
            estado       = 'pendiente',
            descripcion  = descripcion,
            fecha_inicio = fecha_inicio,
            fecha_fin    = fecha_fin,
            url_pdf      = None,
            public_id_pdf= None,
        )
        db.add(solicitud)
        db.flush()  # Obtiene el ID antes del commit

        # ── 6. Generar PDF con overlay (reportlab + pypdf) ────────────────
        perfil = getattr(empleado, '__dict__', {})
        pdf_datos = {
            "tipo_original":  datos.tipo,
            "tipo":           tipo_bd,
            "nombre":         perfil.get("nombre", ""),
            "cargo":          perfil.get("cargo", perfil.get("puesto", "")),
            "area":           perfil.get("area", ""),
            "fecha_inicio":   datos.fecha_inicio or "",
            "fecha_fin":      datos.fecha_fin    or "",
            "hora_inicio":    datos.hora_inicio  or "",
            "hora_fin":       datos.hora_fin     or "",
            "motivo":         datos.motivo       or "",
            "total_dias":     datos.total_dias,
            "periodo":        f"{datos.fecha_inicio} - {datos.fecha_fin}" if datos.fecha_inicio and datos.fecha_fin else "",
            "firma_base64":   datos.firma_base64 if datos.firma_base64.startswith("data:") else firma_url,
        }
        pdf_bytes = generar_pdf_solicitud(pdf_datos)

        # ── 7. Subir PDF generado a Cloudinary ────────────────────────────
        pdf_uid       = uuid.uuid4().hex[:12]
        pdf_public_id = f"e-zyro/permisos/permiso_{empleado.id}_{pdf_uid}"
        pdf_url       = subir_pdf_bytes_cloudinary(pdf_bytes, pdf_public_id)

        # ── 8. Actualizar la solicitud con la URL del PDF ─────────────────
        solicitud.url_pdf       = pdf_url
        solicitud.public_id_pdf = pdf_public_id

        # ── 9. Registrar DocumentoFirmado ─────────────────────────────────
        if firma_existente and firma_existente.id:
            db.add(DocumentoFirmado(
                firma_id        = firma_existente.id,
                empresa_id      = empresa_id,
                documento_id    = solicitud.id,
                tabla_documento = "solicitud_laboral",
            ))

        # ── 10. Registrar en Auditoría ────────────────────────────────────
        datos_nuevos = json.dumps({
            "tipo":         datos.tipo,
            "tipo_bd":      tipo_bd,
            "tipo_label":   tipo_label,
            "estado":       "pendiente",
            "fecha_inicio": str(fecha_inicio),
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
            descripcion    = f"Solicitud de {tipo_label} enviada",
            datos_nuevos   = datos_nuevos,
        ))

        db.commit()

        # ── 11. Respuesta ─────────────────────────────────────────────────
        hoy        = date.today()
        fecha_fmt  = f"{hoy.day} {MESES[hoy.month]}, {hoy.year}"
        id_display = f"PRM-{solicitud.id[:6].upper()}"

        return {
            "status": "success",
            "data": {
                "id":           id_display,
                "tipo":         tipo_label,
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
