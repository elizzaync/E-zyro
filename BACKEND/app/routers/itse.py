"""
Router: /itse — Inspección ITSE (Fase 5).
Inspección por tablero o zona, con tableros, ítems (hallazgos) y fotos (galería).
Reutiliza ubicacion/zona (Fase 0) y recurso_cloudinary (Fase 1).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..core.permisos import exigir_permiso
from ..db.database import get_db
from ..models.itse import InspeccionItse, InspeccionTablero, InspeccionItem
from ..models.ubicacion import Ubicacion
from ..models.zona import Zona
from ..services.cloudinary_service import subir_e_indexar
from ..services.cloudinary_paths import carpeta_itse
from ..schemas.itse import (
    InspeccionIn, InspeccionOut, TableroIn, TableroOut,
    ItemIn, ItemOut, FotoIn,
)

router = APIRouter(prefix="/itse", tags=["itse"])

_MODOS = {"tablero", "zona"}
_RESULTADOS = {"conforme", "observado", "no_conforme"}


def _insp_or_404(db: Session, empresa_id: str, iid: str) -> InspeccionItse:
    i = db.query(InspeccionItse).filter(InspeccionItse.id == iid, InspeccionItse.empresa_id == empresa_id).first()
    if not i:
        raise HTTPException(status_code=404, detail="Inspección no encontrada")
    return i


def _validar_catalogos(db: Session, empresa_id: str, ubicacion_id: Optional[str], zona_id: Optional[str]) -> None:
    if ubicacion_id and not db.query(Ubicacion.id).filter(Ubicacion.id == ubicacion_id, Ubicacion.empresa_id == empresa_id).first():
        raise HTTPException(status_code=400, detail="Ubicación inválida")
    if zona_id and not db.query(Zona.id).filter(Zona.id == zona_id, Zona.empresa_id == empresa_id).first():
        raise HTTPException(status_code=400, detail="Zona inválida")


def _out(i: InspeccionItse) -> InspeccionOut:
    return InspeccionOut(
        id=str(i.id), cliente_id=(str(i.cliente_id) if i.cliente_id else None),
        ubicacion_id=(str(i.ubicacion_id) if i.ubicacion_id else None),
        zona_id=(str(i.zona_id) if i.zona_id else None), modo=i.modo,
        fecha=(str(i.fecha) if i.fecha else None), estado=i.estado,
        pdf_url=i.pdf_url, observaciones=i.observaciones,
    )


# ── Inspecciones ─────────────────────────────────────────────────────────────
@router.get("", response_model=List[InspeccionOut])
def listar(
    cliente_id: Optional[str] = Query(None),
    ubicacion_id: Optional[str] = Query(None),
    modo: Optional[str] = Query(None),
    estado: Optional[str] = Query(None),
    payload: dict = Depends(verificar_token), db: Session = Depends(get_db),
):
    qry = db.query(InspeccionItse).filter(InspeccionItse.empresa_id == payload["empresa_id"])
    if cliente_id:
        qry = qry.filter(InspeccionItse.cliente_id == cliente_id)
    if ubicacion_id:
        qry = qry.filter(InspeccionItse.ubicacion_id == ubicacion_id)
    if modo:
        qry = qry.filter(InspeccionItse.modo == modo)
    if estado:
        qry = qry.filter(InspeccionItse.estado == estado)
    return [_out(i) for i in qry.order_by(InspeccionItse.created_at.desc()).limit(300).all()]


@router.post("", response_model=InspeccionOut, status_code=201)
def crear(body: InspeccionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "crear")
    empresa_id = payload["empresa_id"]
    if body.modo not in _MODOS:
        raise HTTPException(status_code=400, detail=f"modo inválido (use {sorted(_MODOS)})")
    _validar_catalogos(db, empresa_id, body.ubicacion_id, body.zona_id)
    i = InspeccionItse(
        id=str(_uuid.uuid4()), empresa_id=empresa_id, cliente_id=body.cliente_id,
        ubicacion_id=body.ubicacion_id, zona_id=body.zona_id, modo=body.modo,
        fecha=date.today(), estado="borrador", observaciones=body.observaciones,
        registrado_por_id=payload.get("id"),
    )
    db.add(i)
    db.commit()
    return _out(i)


@router.put("/{iid}", response_model=InspeccionOut)
def actualizar(iid: str, body: InspeccionIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "editar")
    empresa_id = payload["empresa_id"]
    i = _insp_or_404(db, empresa_id, iid)
    if i.estado == "finalizada":
        raise HTTPException(status_code=409, detail="No se edita una inspección finalizada")
    if body.modo not in _MODOS:
        raise HTTPException(status_code=400, detail=f"modo inválido (use {sorted(_MODOS)})")
    _validar_catalogos(db, empresa_id, body.ubicacion_id, body.zona_id)
    i.cliente_id = body.cliente_id
    i.ubicacion_id = body.ubicacion_id
    i.zona_id = body.zona_id
    i.modo = body.modo
    i.observaciones = body.observaciones
    db.commit()
    return _out(i)


@router.delete("/{iid}", status_code=204)
def eliminar(iid: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "eliminar")
    i = _insp_or_404(db, payload["empresa_id"], iid)
    db.query(InspeccionItem).filter(InspeccionItem.inspeccion_id == iid).delete(synchronize_session=False)
    db.query(InspeccionTablero).filter(InspeccionTablero.inspeccion_id == iid).delete(synchronize_session=False)
    db.delete(i)
    db.commit()


@router.post("/{iid}/finalizar", response_model=InspeccionOut)
def finalizar(iid: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "finalizar")
    i = _insp_or_404(db, payload["empresa_id"], iid)
    if i.estado == "finalizada":
        return _out(i)  # idempotente
    if i.modo == "tablero":
        tiene = db.query(InspeccionTablero.id).filter(InspeccionTablero.inspeccion_id == iid).first()
        if not tiene:
            raise HTTPException(status_code=409, detail="Una inspección por tablero requiere al menos un tablero")
    i.estado = "finalizada"
    db.commit()
    # NOTA: generación del PDF entregable (pdf_url) en iteración posterior (pdf_service).
    return _out(i)


# ── Tableros ─────────────────────────────────────────────────────────────────
@router.post("/{iid}/tableros", response_model=TableroOut, status_code=201)
def crear_tablero(iid: str, body: TableroIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "editar")
    _insp_or_404(db, payload["empresa_id"], iid)
    t = InspeccionTablero(id=str(_uuid.uuid4()), inspeccion_id=iid, nombre=body.nombre.strip(),
                          ambiente=body.ambiente, descripcion=body.descripcion)
    db.add(t)
    db.commit()
    return TableroOut(id=str(t.id), inspeccion_id=iid, nombre=t.nombre, ambiente=t.ambiente, descripcion=t.descripcion)


@router.get("/{iid}/tableros", response_model=List[TableroOut])
def listar_tableros(iid: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _insp_or_404(db, payload["empresa_id"], iid)
    rows = db.query(InspeccionTablero).filter(InspeccionTablero.inspeccion_id == iid).order_by(InspeccionTablero.created_at).all()
    return [TableroOut(id=str(t.id), inspeccion_id=iid, nombre=t.nombre, ambiente=t.ambiente, descripcion=t.descripcion) for t in rows]


@router.delete("/tableros/{tid}", status_code=204)
def eliminar_tablero(tid: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "editar")
    t = db.query(InspeccionTablero).filter(InspeccionTablero.id == tid).first()
    if not t:
        raise HTTPException(status_code=404, detail="Tablero no encontrado")
    _insp_or_404(db, payload["empresa_id"], str(t.inspeccion_id))  # valida empresa por la inspección padre
    db.query(InspeccionItem).filter(InspeccionItem.tablero_id == tid).update({"tablero_id": None}, synchronize_session=False)
    db.delete(t)
    db.commit()


# ── Ítems ────────────────────────────────────────────────────────────────────
@router.post("/{iid}/items", response_model=ItemOut, status_code=201)
def crear_item(iid: str, body: ItemIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "editar")
    _insp_or_404(db, payload["empresa_id"], iid)
    if body.resultado not in _RESULTADOS:
        raise HTTPException(status_code=400, detail=f"resultado inválido (use {sorted(_RESULTADOS)})")
    it = InspeccionItem(id=str(_uuid.uuid4()), inspeccion_id=iid, tablero_id=body.tablero_id,
                        descripcion=body.descripcion.strip(), resultado=body.resultado, observacion=body.observacion)
    db.add(it)
    db.commit()
    return ItemOut(id=str(it.id), tablero_id=(str(it.tablero_id) if it.tablero_id else None),
                   descripcion=it.descripcion, resultado=it.resultado, observacion=it.observacion)


@router.get("/{iid}/items", response_model=List[ItemOut])
def listar_items(iid: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    _insp_or_404(db, payload["empresa_id"], iid)
    rows = db.query(InspeccionItem).filter(InspeccionItem.inspeccion_id == iid).order_by(InspeccionItem.created_at).all()
    return [ItemOut(id=str(x.id), tablero_id=(str(x.tablero_id) if x.tablero_id else None),
                    descripcion=x.descripcion, resultado=x.resultado, observacion=x.observacion) for x in rows]


@router.delete("/items/{item_id}", status_code=204)
def eliminar_item(item_id: str, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "editar")
    x = db.query(InspeccionItem).filter(InspeccionItem.id == item_id).first()
    if not x:
        raise HTTPException(status_code=404, detail="Ítem no encontrado")
    _insp_or_404(db, payload["empresa_id"], str(x.inspeccion_id))
    db.delete(x)
    db.commit()


# ── Fotos (galería) ──────────────────────────────────────────────────────────
@router.post("/{iid}/fotos", status_code=201)
def subir_foto(iid: str, body: FotoIn, payload: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    exigir_permiso(db, payload, "itse", "editar")
    empresa_id = payload["empresa_id"]
    _insp_or_404(db, empresa_id, iid)
    ent_id = body.tablero_id or iid
    rec = subir_e_indexar(
        db, empresa_id=empresa_id, base64_data=body.imagen_base64,
        folder=carpeta_itse(empresa_id, iid), public_id=str(_uuid.uuid4()),
        entidad_tipo="itse", entidad_id=ent_id, descripcion=body.descripcion,
        creado_por_id=payload.get("id"),
    )
    return {"id": rec.id, "secure_url": rec.secure_url, "entidad_id": ent_id}
