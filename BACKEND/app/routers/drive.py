"""
Router: /drive — Drive de empresa (repositorio de archivos tipo Drive).

Carpetas recursivas (`drive_carpeta`) + archivos de cualquier tipo (`drive_archivo`)
en Cloudinary. Dos ámbitos: `compartido` (lo ve toda la empresa) y `personal`
(solo el propietario + admin). Objetivo: que la información de la empresa viva
dentro del sistema y no en cuentas externas personales.

- Leer y SUBIR: cualquier usuario de la empresa (incl. Técnico).
- Borrar/renombrar: el dueño de lo que subió, o un rol de gestión/admin.
"""
from __future__ import annotations

import uuid as _uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import es_admin
from ..db.database import get_db
from ..models.drive_carpeta import DriveCarpeta
from ..models.drive_archivo import DriveArchivo
from ..services.cloudinary_service import (
    subir_archivo_base64,
    eliminar_recurso_por_public_id,
)

router = APIRouter(prefix="/drive", tags=["drive"])

_MAX_BYTES = 30 * 1024 * 1024  # 30 MB por archivo
_IMG_EXT = {"jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff"}
_ROLES_GESTION = {
    "superadmin", "admin", "administrador",
    "jefe de operaciones", "jefe_operaciones",
    "supervisor de campo", "supervisor",
    "logística", "logistica", "logístico", "logistico",
}


# ── Schemas ───────────────────────────────────────────────────────────────
class CarpetaIn(BaseModel):
    nombre: str
    ambito: str = "compartido"        # compartido | personal
    padre_id: Optional[str] = None


class RenameIn(BaseModel):
    nombre: str


class CarpetaOut(BaseModel):
    id: str
    nombre: str
    ambito: str
    padre_id: Optional[str] = None
    sub_carpetas: int = 0
    archivos: int = 0
    created_at: Optional[str] = None


class ArchivoIn(BaseModel):
    nombre: str
    filename: str                      # nombre original con extensión
    archivo_base64: str
    descripcion: Optional[str] = None
    ambito: str = "compartido"
    carpeta_id: Optional[str] = None


class ArchivoEditIn(BaseModel):
    nombre: Optional[str] = None
    descripcion: Optional[str] = None


class ArchivoOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str] = None
    ambito: str
    carpeta_id: Optional[str] = None
    url: str
    recurso_tipo: str
    formato: Optional[str] = None
    bytes: Optional[int] = None
    subido_por_id: Optional[str] = None
    es_mio: bool = False
    created_at: Optional[str] = None


# ── Helpers ───────────────────────────────────────────────────────────────
def _es_gestion(payload: dict) -> bool:
    return es_admin(payload) or (payload.get("rol") or "").lower().strip() in _ROLES_GESTION


def _ext(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


def _recurso_tipo(ext: str) -> str:
    if ext in _IMG_EXT:
        return "imagen"
    if ext == "pdf":
        return "pdf"
    return "raw"


def _check_size(b64: str) -> None:
    payload = b64.split(",", 1)[1] if b64.startswith("data:") and "," in b64 else b64
    if (len(payload) * 3) // 4 > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="El archivo supera el límite de 30 MB")


def _scope_ambito(qry, model, ambito: str, payload: dict, propietario_id: Optional[str]):
    """Acota la consulta al ámbito: compartido (todos) o personal (dueño + admin)."""
    if ambito == "personal":
        owner = payload.get("id")
        if propietario_id and es_admin(payload):
            owner = propietario_id
        return qry.filter(model.ambito == "personal", model.propietario_id == owner)
    return qry.filter(model.ambito == "compartido")


def _resolver_destino(db: Session, empresa_id: str, carpeta_id: Optional[str],
                      ambito_body: str, payload: dict):
    """Si hay carpeta, hereda ámbito/propietario de ella; si es raíz, usa el body."""
    if carpeta_id:
        c = db.query(DriveCarpeta).filter(
            DriveCarpeta.id == carpeta_id, DriveCarpeta.empresa_id == empresa_id).first()
        if not c:
            raise HTTPException(status_code=404, detail="Carpeta no encontrada")
        return c.ambito, c.propietario_id, c.id
    ambito = ambito_body if ambito_body in ("compartido", "personal") else "compartido"
    propietario = payload.get("id") if ambito == "personal" else None
    return ambito, propietario, None


# ════════════════════════════════════════════════════════════════════════════
# CARPETAS
# ════════════════════════════════════════════════════════════════════════════
def _carpeta_out(db: Session, c: DriveCarpeta) -> CarpetaOut:
    subc = db.query(func.count(DriveCarpeta.id)).filter(DriveCarpeta.padre_id == c.id).scalar() or 0
    narch = db.query(func.count(DriveArchivo.id)).filter(DriveArchivo.carpeta_id == c.id).scalar() or 0
    return CarpetaOut(
        id=str(c.id), nombre=c.nombre, ambito=c.ambito,
        padre_id=str(c.padre_id) if c.padre_id else None,
        sub_carpetas=int(subc), archivos=int(narch),
        created_at=c.created_at.isoformat() if c.created_at else None,
    )


@router.get("/carpetas", response_model=List[CarpetaOut])
def listar_carpetas(
    ambito: str = Query("compartido"),
    padre_id: str = Query("", description="vacío = raíz del ámbito"),
    propietario_id: str = Query("", description="solo admin: ver el personal de otro"),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(DriveCarpeta).filter(DriveCarpeta.empresa_id == payload["empresa_id"])
    qry = _scope_ambito(qry, DriveCarpeta, ambito, payload, propietario_id or None)
    if padre_id:
        qry = qry.filter(DriveCarpeta.padre_id == padre_id)
    else:
        qry = qry.filter(DriveCarpeta.padre_id.is_(None))
    return [_carpeta_out(db, c) for c in qry.order_by(DriveCarpeta.nombre.asc()).all()]


@router.post("/carpetas", response_model=CarpetaOut, status_code=201)
def crear_carpeta(body: CarpetaIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")
    e = payload["empresa_id"]
    ambito, propietario, padre = _resolver_destino(db, e, body.padre_id, body.ambito, payload)
    c = DriveCarpeta(
        id=str(_uuid.uuid4()), empresa_id=e, nombre=nombre, ambito=ambito,
        propietario_id=propietario, padre_id=padre,
        creado_por_id=payload.get("id"), created_at=datetime.utcnow(),
    )
    db.add(c)
    db.commit()
    return _carpeta_out(db, c)


@router.put("/carpetas/{carpeta_id}", response_model=CarpetaOut)
def renombrar_carpeta(carpeta_id: str, body: RenameIn,
                      payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    c = db.query(DriveCarpeta).filter(
        DriveCarpeta.id == carpeta_id, DriveCarpeta.empresa_id == payload["empresa_id"]).first()
    if not c:
        raise HTTPException(status_code=404, detail="Carpeta no encontrada")
    if str(c.creado_por_id) != str(payload.get("id")) and not _es_gestion(payload):
        raise HTTPException(status_code=403, detail="Solo el dueño o un administrador puede renombrar")
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")
    c.nombre = nombre
    db.commit()
    return _carpeta_out(db, c)


@router.delete("/carpetas/{carpeta_id}", status_code=204)
def eliminar_carpeta(carpeta_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    e = payload["empresa_id"]
    c = db.query(DriveCarpeta).filter(
        DriveCarpeta.id == carpeta_id, DriveCarpeta.empresa_id == e).first()
    if not c:
        raise HTTPException(status_code=404, detail="Carpeta no encontrada")
    if str(c.creado_por_id) != str(payload.get("id")) and not _es_gestion(payload):
        raise HTTPException(status_code=403, detail="Solo el dueño o un administrador puede eliminar")
    subc = db.query(func.count(DriveCarpeta.id)).filter(DriveCarpeta.padre_id == carpeta_id).scalar() or 0
    narch = db.query(func.count(DriveArchivo.id)).filter(DriveArchivo.carpeta_id == carpeta_id).scalar() or 0
    if subc or narch:
        raise HTTPException(status_code=409, detail="La carpeta no está vacía. Elimina su contenido primero.")
    db.delete(c)
    db.commit()


# ════════════════════════════════════════════════════════════════════════════
# ARCHIVOS
# ════════════════════════════════════════════════════════════════════════════
def _archivo_out(a: DriveArchivo, payload: dict) -> ArchivoOut:
    return ArchivoOut(
        id=str(a.id), nombre=a.nombre, descripcion=a.descripcion, ambito=a.ambito,
        carpeta_id=str(a.carpeta_id) if a.carpeta_id else None,
        url=a.url_cloudinary, recurso_tipo=a.recurso_tipo, formato=a.formato,
        bytes=int(a.bytes) if a.bytes is not None else None,
        subido_por_id=str(a.subido_por_id) if a.subido_por_id else None,
        es_mio=str(a.subido_por_id) == str(payload.get("id")),
        created_at=a.created_at.isoformat() if a.created_at else None,
    )


@router.get("/archivos", response_model=List[ArchivoOut])
def listar_archivos(
    ambito: str = Query("compartido"),
    carpeta_id: str = Query("", description="vacío = raíz del ámbito"),
    propietario_id: str = Query(""),
    q: str = Query(""),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(DriveArchivo).filter(DriveArchivo.empresa_id == payload["empresa_id"])
    qry = _scope_ambito(qry, DriveArchivo, ambito, payload, propietario_id or None)
    if carpeta_id:
        qry = qry.filter(DriveArchivo.carpeta_id == carpeta_id)
    else:
        qry = qry.filter(DriveArchivo.carpeta_id.is_(None))
    if q:
        like = f"%{q.strip()}%"
        qry = qry.filter((DriveArchivo.nombre.ilike(like)) | (DriveArchivo.descripcion.ilike(like)))
    rows = qry.order_by(DriveArchivo.created_at.desc()).all()
    return [_archivo_out(a, payload) for a in rows]


@router.post("/archivos", response_model=ArchivoOut, status_code=201)
def subir_archivo(body: ArchivoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    nombre = body.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="El nombre es obligatorio")
    if not body.archivo_base64:
        raise HTTPException(status_code=422, detail="Archivo requerido")
    _check_size(body.archivo_base64)

    e = payload["empresa_id"]
    ambito, propietario, carpeta = _resolver_destino(db, e, body.carpeta_id, body.ambito, payload)
    ext = _ext(body.filename)
    aid = str(_uuid.uuid4())
    res = subir_archivo_base64(
        body.archivo_base64, folder=f"e-zyro/drive/{e}",
        public_id=aid, extension=ext)
    a = DriveArchivo(
        id=aid, empresa_id=e, carpeta_id=carpeta, ambito=ambito, propietario_id=propietario,
        nombre=nombre, descripcion=(body.descripcion or None),
        url_cloudinary=res["secure_url"], public_id_cloudinary=res["public_id"],
        recurso_tipo=_recurso_tipo(ext), formato=res.get("format") or ext,
        bytes=res.get("bytes"), subido_por_id=payload.get("id"), created_at=datetime.utcnow(),
    )
    db.add(a)
    db.commit()
    return _archivo_out(a, payload)


@router.put("/archivos/{archivo_id}", response_model=ArchivoOut)
def editar_archivo(archivo_id: str, body: ArchivoEditIn,
                   payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    a = db.query(DriveArchivo).filter(
        DriveArchivo.id == archivo_id, DriveArchivo.empresa_id == payload["empresa_id"]).first()
    if not a:
        raise HTTPException(status_code=404, detail="Archivo no encontrado")
    if str(a.subido_por_id) != str(payload.get("id")) and not _es_gestion(payload):
        raise HTTPException(status_code=403, detail="Solo el dueño o un administrador puede editar")
    if body.nombre is not None and body.nombre.strip():
        a.nombre = body.nombre.strip()
    if body.descripcion is not None:
        a.descripcion = body.descripcion.strip() or None
    db.commit()
    return _archivo_out(a, payload)


@router.delete("/archivos/{archivo_id}", status_code=204)
def eliminar_archivo(archivo_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    a = db.query(DriveArchivo).filter(
        DriveArchivo.id == archivo_id, DriveArchivo.empresa_id == payload["empresa_id"]).first()
    if not a:
        raise HTTPException(status_code=404, detail="Archivo no encontrado")
    if str(a.subido_por_id) != str(payload.get("id")) and not _es_gestion(payload):
        raise HTTPException(status_code=403, detail="Solo el dueño o un administrador puede eliminar")
    rtype = "image" if (a.formato or "").lower() in _IMG_EXT else "raw"
    eliminar_recurso_por_public_id(a.public_id_cloudinary, resource_type=rtype)
    db.delete(a)
    db.commit()
