"""
Middleware de captura CENTRALIZADA de eventos HTTP para audit_log (Fase 1).

Observa cada respuesta y registra:
  - 403 → PERMISSION_DENIED (resultado=denegado), con las claims del token
    decodificadas en silencio (mismo criterio que audit_context.py).
    Se excluye el candado de rol ClienteExterno (ver _PREFIJOS_PORTAL en
    app/core/security.py): devuelve 403 por diseño ante CUALQUIER ruta fuera
    de /portal-cliente y /auth, y generaría ruido masivo sin valor de
    seguridad (incluso falsas alertas de "accesos denegados").
  - descargas/exportaciones con status 200 → DOWNLOAD (o EXPORT si es
    exportación tabular), detectadas por sufijo de ruta o por el header
    Content-Disposition: attachment.

NUNCA lee el body del request. Best-effort total: un fallo aquí jamás
rompe ni retrasa la respuesta al cliente.
"""
from __future__ import annotations

import os

from jose import jwt, JWTError
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.security import _PREFIJOS_PORTAL

_SECRET: str = os.getenv("SECRET_KEY", "")
_ALGO: str = "HS256"

# Rutas que YA registran su propio evento (router o archivar()): el middleware
# las salta para no duplicar filas en audit_log.
_EXCLUIR_DESCARGA = (
    "/backups",                    # instrumentado en app/routers/backups.py
    "/audit-log",                  # el export se audita a sí mismo
    "/seguridad-tic",
    "/rrhh/asistencia/reportes",   # pasan por document_archive_service.archivar
    "/vacaciones/reporte",
)

_SUFIJOS_DESCARGA = ("/descargar", "/exportar", "/export", "/excel", "/csv", "/pdf")
_EXT_DESCARGA = (".pdf", ".xlsx", ".xls", ".csv", ".zip")
_MARCAS_EXPORT = ("/exportar", "/export", "/excel", "/csv", ".xlsx", ".xls", ".csv")


def _claims_silenciosas(request: Request) -> dict:
    try:
        auth = request.headers.get("Authorization", "")
        token = (auth.removeprefix("Bearer ").strip()
                 if auth.startswith("Bearer ")
                 else request.query_params.get("token", ""))
        if not token:
            return {}
        return jwt.decode(token, _SECRET, algorithms=[_ALGO])
    except (JWTError, Exception):  # noqa: BLE001
        return {}


def _es_descarga(path: str, response: Response) -> bool:
    p = path.lower()
    if any(p.endswith(s) for s in _SUFIJOS_DESCARGA):
        return True
    if any(p.endswith(e) for e in _EXT_DESCARGA):
        return True
    cd = (response.headers.get("content-disposition") or "").lower()
    return "attachment" in cd


def _es_export(path: str, response: Response) -> bool:
    p = path.lower()
    if any(m in p for m in _MARCAS_EXPORT):
        return True
    ct = (response.headers.get("content-type") or "").lower()
    return ("csv" in ct) or ("spreadsheet" in ct) or ("ms-excel" in ct)


def _nombre_adjunto(response: Response) -> str | None:
    cd = response.headers.get("content-disposition") or ""
    if "filename=" in cd:
        return cd.split("filename=", 1)[1].strip().strip('"')[:150]
    return None


class AuditEventsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        try:
            self._registrar(request, response)
        except Exception:  # noqa: BLE001 — jamás romper la respuesta
            pass
        return response

    def _registrar(self, request: Request, response: Response) -> None:
        path = request.url.path
        if request.method == "OPTIONS":
            return

        # Import perezoso: evita ciclos y no encarece el arranque
        from app.services.audit_service import contexto_desde_payload, registrar_evento

        # ── 403 → PERMISSION_DENIED ──────────────────────────────────────────
        if response.status_code == 403:
            claims = _claims_silenciosas(request)
            rol = (claims.get("rol") or "").lower().strip().replace(" ", "")
            if rol == "clienteexterno" and not path.startswith(_PREFIJOS_PORTAL):
                return  # candado de rol (security.py): 403 por diseño, sin valor de seguridad
            ctx = contexto_desde_payload(claims, request)
            registrar_evento(accion="PERMISSION_DENIED", resultado="denegado",
                             detalle={"status": 403}, **ctx)
            return

        # ── Descargas / exportaciones exitosas ──────────────────────────────
        if response.status_code == 200 and _es_descarga(path, response):
            if path.startswith(_EXCLUIR_DESCARGA):
                return
            claims = _claims_silenciosas(request)
            ctx = contexto_desde_payload(claims, request)
            adjunto = _nombre_adjunto(response)
            registrar_evento(
                accion="EXPORT" if _es_export(path, response) else "DOWNLOAD",
                detalle={"archivo": adjunto} if adjunto else None, **ctx)
