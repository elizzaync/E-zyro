"""
Router: /audit-log (módulo Seguridad · Gestión de TIC)

Vista COMPLETA del audit log de eventos HTTP/seguridad (mismos filtros y DTO
que /seguridad-tic/eventos) + export CSV. El export SE AUDITA a sí mismo
(accion=EXPORT). Gate Soporte idéntico al de backups.py.
"""
from __future__ import annotations

import csv
import io
import json
import unicodedata
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.core.security import verificar_token
from app.db.database import get_db
from app.services.audit_service import (
    consultar_eventos,
    contexto_desde_payload,
    evento_a_dto,
    registrar_evento,
)

router = APIRouter(prefix="/audit-log", tags=["audit-log"])


# ── Autorización: solo Soporte / TI / admin total (clon de backups.py) ────────

def _autorizar_soporte(payload: dict) -> None:
    if payload.get("admin_total"):
        return
    rol = (payload.get("rol") or "").strip().lower()
    rol = unicodedata.normalize("NFC", rol).replace("\xa0", " ")
    if rol in ("soporte", "ti", "admin", "superadmin"):
        return
    raise HTTPException(status_code=403, detail="Solo Soporte puede ver el audit log")


@router.get("")
def listar_eventos(
    accion:        str = Query("todas"),
    usuarioNombre: str = Query(""),
    ip:            str = Query(""),
    desde:         str = Query(""),   # YYYY-MM-DD
    hasta:         str = Query(""),   # YYYY-MM-DD
    resultado:     str = Query(""),
    page:          int = Query(1, ge=1),
    page_size:     int = Query(25, ge=1, le=200),
    payload:       dict = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    _autorizar_soporte(payload)
    filas, total = consultar_eventos(
        db, accion=accion or None, usuario_nombre=usuarioNombre or None,
        ip=ip or None, desde=desde or None, hasta=hasta or None,
        resultado=resultado or None, page=page, page_size=page_size,
    )
    return {"items": [evento_a_dto(e) for e in filas], "total": total,
            "page": page, "pageSize": page_size}


@router.get("/export")
def exportar_csv(
    request:       Request,
    accion:        str = Query("todas"),
    usuarioNombre: str = Query(""),
    ip:            str = Query(""),
    desde:         str = Query(""),
    hasta:         str = Query(""),
    resultado:     str = Query(""),
    payload:       dict = Depends(verificar_token),
    db:            Session = Depends(get_db),
):
    """Exporta el audit log filtrado a CSV (tope 50 000 filas)."""
    _autorizar_soporte(payload)
    filas, total = consultar_eventos(
        db, accion=accion or None, usuario_nombre=usuarioNombre or None,
        ip=ip or None, desde=desde or None, hasta=hasta or None,
        resultado=resultado or None, paginar=False,
    )

    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["fecha", "accion", "resultado", "usuario", "rol", "ip",
                "metodo", "ruta", "entidad", "entidad_id", "user_agent", "detalle"])
    for e in filas:
        w.writerow([
            e.fecha.isoformat() if e.fecha else "",
            e.accion or "", e.resultado or "", e.usuario_nombre or "",
            e.rol or "", e.ip or "", e.metodo_http or "", e.ruta or "",
            e.entidad or "", e.entidad_id or "", e.user_agent or "",
            json.dumps(e.detalle, ensure_ascii=False) if e.detalle else "",
        ])
    contenido = buf.getvalue().encode("utf-8-sig")  # BOM: Excel abre bien las tildes

    # El export se audita a sí mismo (el middleware excluye /audit-log)
    ctx = contexto_desde_payload(payload, request)
    registrar_evento(
        accion="EXPORT", entidad="audit_log",
        detalle={"filas": len(filas), "totalFiltrado": total,
                 "filtros": {"accion": accion, "usuarioNombre": usuarioNombre,
                             "ip": ip, "desde": desde, "hasta": hasta,
                             "resultado": resultado}},
        db=db, **ctx,
    )

    nombre = f"audit_log_{datetime.utcnow():%Y%m%d_%H%M%S}.csv"
    return StreamingResponse(
        io.BytesIO(contenido),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )
