"""
Router: /operaciones
Gestión completa del módulo de Operaciones / Detalle de Servicio.

Tablas involucradas (bd.txt):
  proyecto_servicio, proyecto, cliente, catalogo_servicio, proyecto_detalle,
  proyecto_miembro, empleado, usuario,
  procedimiento, evidencia_procedimiento,
  requerimiento, requerimiento_detalle, material,
  seguimiento_proyecto
"""
from __future__ import annotations

from datetime import datetime, date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..core.security import verificar_token
from ..db.database import get_db
from ..services.cloudinary_service import subir_archivo_cloudinary

router = APIRouter(prefix="/operaciones", tags=["operaciones"])


# ══════════════════════════════════════════════════════════════
# SCHEMAS DE RESPUESTA
# ══════════════════════════════════════════════════════════════

class EvidenciaOut(BaseModel):
    id: str
    url_cloudinary: str
    descripcion: Optional[str]
    fecha_captura: str

class ProcedimientoOut(BaseModel):
    id: str
    nombre: str
    descripcion: Optional[str]
    orden: int
    estado: str
    evidencias: List[EvidenciaOut] = []

class MiembroEquipoOut(BaseModel):
    id: str
    nombre: str
    apellido: str
    foto_url: Optional[str]
    cargo: str
    rol_proyecto: str

class ItemMaterialOut(BaseModel):
    id: str                  # requerimiento_detalle.id
    requerimiento_id: str
    nombre: str
    unidad: str
    cantidad: int
    estado_req: str

class NotaOut(BaseModel):
    id: str
    fecha: str
    texto: str
    autor: str

class ServicioDetalleOut(BaseModel):
    id: str
    proyecto_id: str
    cliente: str
    tipo_servicio: str
    ubicacion: str
    fecha_str: str
    hora_str: str
    descripcion: str
    estado: str
    progreso: float
    equipo: List[MiembroEquipoOut]
    procedimientos: List[ProcedimientoOut]
    materiales_asignados: List[ItemMaterialOut]
    materiales_solicitados: List[ItemMaterialOut]
    notas: List[NotaOut]

class DashboardMetricaOut(BaseModel):
    id: str
    titulo: str
    valor: int
    colorIcono: str
    resaltado: bool = False

class DashboardServicioOut(BaseModel):
    id: str
    cliente: str
    tipoServicio: str
    ubicacion: str
    fechaStr: str
    horaStr: str
    estado: str
    alerta: bool = False


# ══════════════════════════════════════════════════════════════
# SCHEMAS DE ENTRADA
# ══════════════════════════════════════════════════════════════

class ActualizarEstadoBody(BaseModel):
    estado: str

class ActualizarProcedimientoBody(BaseModel):
    estado: str

class SolicitarMaterialBody(BaseModel):
    material_id: str
    cantidad: int

class ActualizarReqDetalleBody(BaseModel):
    cantidad: Optional[int] = None

class AgregarNotaBody(BaseModel):
    descripcion: str


# ══════════════════════════════════════════════════════════════
# GET /operaciones/dashboard?fecha=YYYY-MM-DD
# Métricas del día + lista de servicios para la fecha dada
# ══════════════════════════════════════════════════════════════

@router.get("/dashboard")
def get_dashboard(
    fecha: Optional[str] = None,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    try:
        fecha_dt = date.fromisoformat(fecha) if fecha else date.today()
    except ValueError:
        raise HTTPException(status_code=400, detail="Formato de fecha inválido. Use YYYY-MM-DD")

    hoy = date.today()

    # ── Servicios para la fecha dada, filtrados por membresía del usuario ──
    servicios_rows = db.execute(text("""
        SELECT
            ps.id,
            ps.nombre                                           AS tipo_servicio,
            ps.estado,
            ps.fecha_programada,
            c.razon_social                                      AS cliente,
            COALESCE(pd.zona_ejecucion, p.nombre_proyecto)     AS ubicacion
        FROM proyecto_servicio ps
        JOIN proyecto          p   ON p.id  = ps.proyecto_id
        JOIN cliente           c   ON c.id  = p.cliente_id
        LEFT JOIN proyecto_detalle pd ON pd.proyecto_id = p.id
        WHERE ps.empresa_id              = :eid
          AND ps.fecha_programada::date  = :fecha
          AND EXISTS (
              SELECT 1 FROM proyecto_miembro pm
              JOIN empleado e ON e.id = pm.empleado_id
              WHERE pm.proyecto_id = p.id
                AND e.usuario_id   = :uid
                AND pm.activo      = TRUE
          )
        ORDER BY ps.fecha_programada ASC
    """), {"eid": empresa_id, "uid": usuario_id, "fecha": str(fecha_dt)}).fetchall()

    _estado_map = {"Pendiente": "Pendiente", "En_Proceso": "Activo", "Completado": "Completado"}
    pendientes = activos = hechos = 0
    servicios: list[dict] = []

    for row in servicios_rows:
        est_raw = row.estado or "Pendiente"
        est_fe  = _estado_map.get(est_raw, est_raw)
        fp      = row.fecha_programada

        if est_raw == "Pendiente":    pendientes += 1
        elif est_raw == "En_Proceso": activos    += 1
        elif est_raw == "Completado": hechos     += 1

        alerta = est_raw == "Pendiente" and fp is not None and fp.date() < hoy

        servicios.append({
            "id":          row.id,
            "cliente":     row.cliente,
            "tipoServicio": row.tipo_servicio,
            "ubicacion":   row.ubicacion or "",
            "fechaStr":    fp.strftime("%d %b %Y") if fp else "Sin fecha",
            "horaStr":     fp.strftime("%I:%M %p")  if fp else "--:--",
            "estado":      est_fe,
            "alerta":      alerta,
        })

    # ── Conteo de hoy (siempre TODAY, sin importar la fecha seleccionada) ──
    if fecha_dt != hoy:
        hoy_row = db.execute(text("""
            SELECT COUNT(DISTINCT ps.id) AS total
            FROM proyecto_servicio ps
            JOIN proyecto p ON p.id = ps.proyecto_id
            WHERE ps.empresa_id             = :eid
              AND ps.fecha_programada::date = :hoy
              AND EXISTS (
                  SELECT 1 FROM proyecto_miembro pm
                  JOIN empleado e ON e.id = pm.empleado_id
                  WHERE pm.proyecto_id = p.id
                    AND e.usuario_id   = :uid
                    AND pm.activo      = TRUE
              )
        """), {"eid": empresa_id, "uid": usuario_id, "hoy": str(hoy)}).fetchone()
        hoy_count = int(hoy_row.total) if hoy_row else 0
    else:
        hoy_count = len(servicios_rows)

    metricas = [
        {"id": "pendientes", "titulo": "Pendientes", "valor": pendientes, "colorIcono": "#f59e0b", "resaltado": False},
        {"id": "activos",    "titulo": "En Proceso",  "valor": activos,    "colorIcono": "#3b82f6", "resaltado": activos > 0},
        {"id": "hechos",     "titulo": "Completados", "valor": hechos,     "colorIcono": "#91d337", "resaltado": False},
        {"id": "hoy",        "titulo": "Para Hoy",    "valor": hoy_count,  "colorIcono": "#8b5cf6", "resaltado": False},
    ]

    return {"status": "success", "data": {"metricas": metricas, "servicios": servicios}}


# ══════════════════════════════════════════════════════════════
# GET /operaciones/servicio/{servicio_id}
# Endpoint principal: devuelve JSON anidado completo
# ══════════════════════════════════════════════════════════════

@router.get("/servicio/{servicio_id}", response_model=ServicioDetalleOut)
def get_detalle_servicio(
    servicio_id: str,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    # ── 1. Datos base del servicio ────────────────────────────
    row = db.execute(text("""
        SELECT
            ps.id,
            ps.proyecto_id,
            ps.nombre                                           AS tipo_servicio,
            ps.descripcion,
            ps.estado,
            ps.fecha_programada,
            c.razon_social                                      AS cliente,
            COALESCE(pd.zona_ejecucion, p.nombre_proyecto)     AS ubicacion
        FROM proyecto_servicio ps
        JOIN proyecto          p  ON p.id  = ps.proyecto_id
        JOIN cliente           c  ON c.id  = p.cliente_id
        LEFT JOIN proyecto_detalle pd ON pd.proyecto_id = p.id
        WHERE ps.id        = :sid
          AND ps.empresa_id = :eid
        LIMIT 1
    """), {"sid": servicio_id, "eid": empresa_id}).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    # Verificar que el usuario autenticado pertenece al proyecto
    miembro = db.execute(text("""
        SELECT 1 FROM proyecto_miembro pm
        JOIN empleado e ON e.id = pm.empleado_id
        WHERE pm.proyecto_id = :pid AND e.usuario_id = :uid
        LIMIT 1
    """), {"pid": row.proyecto_id, "uid": usuario_id}).fetchone()

    if not miembro:
        raise HTTPException(status_code=403, detail="No tienes acceso a este servicio")

    fecha_str = row.fecha_programada.strftime("%d %b %Y") if row.fecha_programada else "Sin fecha"
    hora_str  = row.fecha_programada.strftime("%I:%M %p") if row.fecha_programada else "--:--"

    # ── 2. Equipo de trabajo (proyecto_miembro → empleado → usuario) ──
    equipo_rows = db.execute(text("""
        SELECT
            u.id,
            u.nombre,
            u.apellido,
            u.foto_url,
            e.cargo,
            pm.rol_proyecto
        FROM proyecto_miembro pm
        JOIN empleado e ON e.id  = pm.empleado_id
        JOIN usuario  u ON u.id  = e.usuario_id
        WHERE pm.proyecto_id = :pid
          AND pm.activo      = TRUE
    """), {"pid": row.proyecto_id}).fetchall()

    equipo = [
        MiembroEquipoOut(
            id=r.id, nombre=r.nombre, apellido=r.apellido,
            foto_url=r.foto_url, cargo=r.cargo,
            rol_proyecto=r.rol_proyecto or "Técnico"
        )
        for r in equipo_rows
    ]

    # ── 3. Procedimientos + Evidencias ────────────────────────
    proc_rows = db.execute(text("""
        SELECT id, nombre, descripcion, orden, estado
        FROM procedimiento
        WHERE proyecto_servicio_id = :sid
        ORDER BY orden ASC
    """), {"sid": servicio_id}).fetchall()

    ev_rows = db.execute(text("""
        SELECT id, procedimiento_id, url_cloudinary, descripcion, fecha_captura
        FROM evidencia_procedimiento
        WHERE proyecto_servicio_id = :sid
        ORDER BY fecha_captura ASC
    """), {"sid": servicio_id}).fetchall()

    ev_by_proc: dict[str, list] = {}
    for ev in ev_rows:
        ev_by_proc.setdefault(ev.procedimiento_id, []).append(
            EvidenciaOut(
                id=ev.id,
                url_cloudinary=ev.url_cloudinary,
                descripcion=ev.descripcion,
                fecha_captura=ev.fecha_captura.strftime("%I:%M %p") if ev.fecha_captura else ""
            )
        )

    procedimientos = [
        ProcedimientoOut(
            id=p.id, nombre=p.nombre, descripcion=p.descripcion,
            orden=p.orden, estado=p.estado,
            evidencias=ev_by_proc.get(p.id, [])
        )
        for p in proc_rows
    ]

    total     = len(procedimientos)
    completos = sum(1 for p in procedimientos if p.estado == "completado")
    progreso  = round((completos / total * 100), 1) if total else 0

    # ── 4. Materiales (requerimiento → requerimiento_detalle → material) ─
    mat_rows = db.execute(text("""
        SELECT
            rd.id,
            r.id  AS requerimiento_id,
            r.estado,
            m.nombre,
            m.unidad,
            rd.cantidad
        FROM requerimiento r
        JOIN requerimiento_detalle rd ON rd.requerimiento_id = r.id
        JOIN material              m  ON m.id = rd.material_id
        WHERE r.proyecto_servicio_id = :sid
          AND r.empresa_id           = :eid
          AND r.tipo                 = 'material'
        ORDER BY r.created_at ASC
    """), {"sid": servicio_id, "eid": empresa_id}).fetchall()

    mat_asignados  = []
    mat_solicitados = []

    for m in mat_rows:
        item = ItemMaterialOut(
            id=m.id, requerimiento_id=m.requerimiento_id,
            nombre=m.nombre, unidad=m.unidad,
            cantidad=m.cantidad, estado_req=m.estado
        )
        if m.estado in ("entregado", "aprobado"):
            mat_asignados.append(item)
        else:
            mat_solicitados.append(item)

    # ── 5. Notas (seguimiento_proyecto.descripcion como timeline) ──
    nota_rows = db.execute(text("""
        SELECT
            sp.id,
            sp.descripcion,
            sp.fecha,
            CONCAT(u.nombre, ' ', u.apellido) AS autor
        FROM seguimiento_proyecto sp
        JOIN empleado e ON e.id  = sp.registrado_por
        JOIN usuario  u ON u.id  = e.usuario_id
        WHERE sp.proyecto_id = :pid
          AND sp.empresa_id  = :eid
        ORDER BY sp.fecha ASC, sp.created_at ASC
    """), {"pid": row.proyecto_id, "eid": empresa_id}).fetchall()

    notas = [
        NotaOut(
            id=n.id,
            fecha=n.fecha.strftime("%I:%M %p") if isinstance(n.fecha, datetime) else str(n.fecha),
            texto=n.descripcion or "",
            autor=n.autor
        )
        for n in nota_rows
    ]

    return ServicioDetalleOut(
        id=row.id,
        proyecto_id=row.proyecto_id,
        cliente=row.cliente,
        tipo_servicio=row.tipo_servicio,
        ubicacion=row.ubicacion or "",
        fecha_str=fecha_str,
        hora_str=hora_str,
        descripcion=row.descripcion or "",
        estado=row.estado,
        progreso=progreso,
        equipo=equipo,
        procedimientos=procedimientos,
        materiales_asignados=mat_asignados,
        materiales_solicitados=mat_solicitados,
        notas=notas,
    )


# ══════════════════════════════════════════════════════════════
# PATCH /operaciones/servicio/{id}/estado
# ══════════════════════════════════════════════════════════════

@router.patch("/servicio/{servicio_id}/estado")
def actualizar_estado_servicio(
    servicio_id: str,
    body: ActualizarEstadoBody,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    estados_validos = {"Pendiente", "En_Proceso", "Completado", "Cancelado"}
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail="Estado inválido")

    db.execute(text("""
        UPDATE proyecto_servicio
        SET estado = :estado, updated_at = NOW()
        WHERE id = :sid AND empresa_id = :eid
    """), {"estado": body.estado, "sid": servicio_id, "eid": payload["empresa_id"]})
    db.commit()
    return {"ok": True, "estado": body.estado}


# ══════════════════════════════════════════════════════════════
# PATCH /operaciones/procedimiento/{id}/estado
# ══════════════════════════════════════════════════════════════

@router.patch("/procedimiento/{proc_id}/estado")
def actualizar_estado_procedimiento(
    proc_id: str,
    body: ActualizarProcedimientoBody,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    estados_validos = {"pendiente", "en_proceso", "completado", "bloqueado"}
    if body.estado not in estados_validos:
        raise HTTPException(status_code=422, detail="Estado inválido")

    db.execute(text("""
        UPDATE procedimiento
        SET estado = :estado, updated_at = NOW()
        WHERE id = :pid AND empresa_id = :eid
    """), {"estado": body.estado, "pid": proc_id, "eid": payload["empresa_id"]})
    db.commit()
    return {"ok": True, "estado": body.estado}


# ══════════════════════════════════════════════════════════════
# POST /operaciones/procedimiento/{id}/evidencia
# Sube foto/archivo a Cloudinary y registra en evidencia_procedimiento
# ══════════════════════════════════════════════════════════════

@router.post("/procedimiento/{proc_id}/evidencia", status_code=status.HTTP_201_CREATED)
async def subir_evidencia(
    proc_id:     str,
    archivo:     UploadFile = File(...),
    descripcion: str        = Form(default=""),
    payload:     dict       = Depends(verificar_token),
    db:          Session    = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    # Obtener datos del procedimiento
    proc = db.execute(text("""
        SELECT p.id, p.proyecto_servicio_id, ps.proyecto_id
        FROM procedimiento p
        JOIN proyecto_servicio ps ON ps.id = p.proyecto_servicio_id
        WHERE p.id = :pid AND p.empresa_id = :eid
        LIMIT 1
    """), {"pid": proc_id, "eid": empresa_id}).fetchone()

    if not proc:
        raise HTTPException(status_code=404, detail="Procedimiento no encontrado")

    # Obtener empleado_id desde usuario
    empleado = db.execute(text("""
        SELECT id FROM empleado WHERE usuario_id = :uid AND empresa_id = :eid LIMIT 1
    """), {"uid": usuario_id, "eid": empresa_id}).fetchone()

    if not empleado:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")

    # Subir a Cloudinary
    contenido = await archivo.read()
    folder    = f"evidencias/{empresa_id}/{proc.proyecto_id}"
    resultado = subir_archivo_cloudinary(contenido, folder=folder, public_id=None)

    ev_id = str(__import__("uuid").uuid4())
    db.execute(text("""
        INSERT INTO evidencia_procedimiento
            (id, procedimiento_id, proyecto_servicio_id, proyecto_id,
             empresa_id, subido_por, url_cloudinary, public_id_cloudinary,
             etapa, descripcion, fecha_captura, created_at)
        VALUES
            (:id, :proc_id, :ps_id, :proj_id,
             :eid, :emp_id, :url, :pub_id,
             'durante', :desc, NOW(), NOW())
    """), {
        "id":      ev_id,
        "proc_id": proc_id,
        "ps_id":   proc.proyecto_servicio_id,
        "proj_id": proc.proyecto_id,
        "eid":     empresa_id,
        "emp_id":  empleado.id,
        "url":     resultado["secure_url"],
        "pub_id":  resultado["public_id"],
        "desc":    descripcion,
    })

    # Marcar procedimiento como completado
    db.execute(text("""
        UPDATE procedimiento SET estado = 'completado', updated_at = NOW()
        WHERE id = :pid
    """), {"pid": proc_id})

    db.commit()
    return {"ok": True, "evidencia_id": ev_id, "url": resultado["secure_url"]}


# ══════════════════════════════════════════════════════════════
# POST /operaciones/servicio/{id}/requerimiento
# Solicitar material extra
# ══════════════════════════════════════════════════════════════

@router.post("/servicio/{servicio_id}/requerimiento", status_code=status.HTTP_201_CREATED)
def solicitar_material(
    servicio_id: str,
    body: SolicitarMaterialBody,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    ps = db.execute(text("""
        SELECT id, proyecto_id FROM proyecto_servicio
        WHERE id = :sid AND empresa_id = :eid LIMIT 1
    """), {"sid": servicio_id, "eid": empresa_id}).fetchone()

    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    empleado = db.execute(text("""
        SELECT id FROM empleado WHERE usuario_id = :uid AND empresa_id = :eid LIMIT 1
    """), {"uid": usuario_id, "eid": empresa_id}).fetchone()

    if not empleado:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")

    import uuid as _uuid
    req_id = str(_uuid.uuid4())
    rd_id  = str(_uuid.uuid4())

    db.execute(text("""
        INSERT INTO requerimiento
            (id, proyecto_id, proyecto_servicio_id, empresa_id, solicitante_id,
             tipo, estado, fecha, created_at)
        VALUES
            (:id, :proy, :ps, :eid, :sol, 'material', 'pendiente', NOW()::date, NOW())
    """), {"id": req_id, "proy": ps.proyecto_id, "ps": servicio_id,
           "eid": empresa_id, "sol": empleado.id})

    db.execute(text("""
        INSERT INTO requerimiento_detalle (id, requerimiento_id, material_id, cantidad)
        VALUES (:id, :rid, :mid, :cant)
    """), {"id": rd_id, "rid": req_id, "mid": body.material_id, "cant": body.cantidad})

    db.commit()
    return {"ok": True, "requerimiento_id": req_id, "detalle_id": rd_id}


# ══════════════════════════════════════════════════════════════
# PATCH /operaciones/requerimiento-detalle/{id}
# Editar cantidad de material solicitado
# ══════════════════════════════════════════════════════════════

@router.patch("/requerimiento-detalle/{rd_id}")
def actualizar_requerimiento_detalle(
    rd_id:   str,
    body:    ActualizarReqDetalleBody,
    payload: dict    = Depends(verificar_token),
    db:      Session = Depends(get_db),
):
    if body.cantidad is not None and body.cantidad < 1:
        raise HTTPException(status_code=422, detail="Cantidad inválida")

    if body.cantidad is not None:
        db.execute(text("""
            UPDATE requerimiento_detalle SET cantidad = :cant WHERE id = :id
        """), {"cant": body.cantidad, "id": rd_id})
        db.commit()

    return {"ok": True}


# ══════════════════════════════════════════════════════════════
# POST /operaciones/servicio/{id}/nota
# Agregar nota al timeline (seguimiento_proyecto)
# ══════════════════════════════════════════════════════════════

@router.post("/servicio/{servicio_id}/nota", status_code=status.HTTP_201_CREATED)
def agregar_nota(
    servicio_id: str,
    body: AgregarNotaBody,
    payload: dict = Depends(verificar_token),
    db: Session = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    usuario_id = payload["id"]

    ps = db.execute(text("""
        SELECT proyecto_id FROM proyecto_servicio
        WHERE id = :sid AND empresa_id = :eid LIMIT 1
    """), {"sid": servicio_id, "eid": empresa_id}).fetchone()

    if not ps:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    empleado = db.execute(text("""
        SELECT id FROM empleado WHERE usuario_id = :uid AND empresa_id = :eid LIMIT 1
    """), {"uid": usuario_id, "eid": empresa_id}).fetchone()

    if not empleado:
        raise HTTPException(status_code=403, detail="No eres empleado registrado")

    import uuid as _uuid
    nota_id = str(_uuid.uuid4())

    # Calcular progreso actual del servicio para seguimiento_proyecto
    stats = db.execute(text("""
        SELECT
            COUNT(*)                                                     AS total,
            SUM(CASE WHEN estado = 'completado' THEN 1 ELSE 0 END)     AS completos
        FROM procedimiento WHERE proyecto_servicio_id = :sid
    """), {"sid": servicio_id}).fetchone()

    progreso = round((stats.completos or 0) / (stats.total or 1) * 100, 2)

    db.execute(text("""
        INSERT INTO seguimiento_proyecto
            (id, proyecto_id, empresa_id, porcentaje_avance, descripcion,
             fecha, registrado_por, created_at)
        VALUES
            (:id, :proy, :eid, :prog, :desc, NOW()::date, :emp, NOW())
    """), {
        "id":   nota_id,
        "proy": ps.proyecto_id,
        "eid":  empresa_id,
        "prog": progreso,
        "desc": body.descripcion,
        "emp":  empleado.id if empleado else None,
    })
    db.commit()
    return {"ok": True, "nota_id": nota_id}


# ══════════════════════════════════════════════════════════════
# GET /operaciones/materiales/buscar?q=...
# Búsqueda de inventario para el modal de solicitud
# ══════════════════════════════════════════════════════════════

@router.get("/materiales/buscar")
def buscar_materiales(
    q: str,
    payload: dict = Depends(verificar_token),
    db: Session   = Depends(get_db),
):
    empresa_id = payload["empresa_id"]
    rows = db.execute(text("""
        SELECT
            m.id,
            m.nombre,
            m.unidad,
            COALESCE(SUM(s.cantidad), 0) AS stock
        FROM material m
        LEFT JOIN stock s ON s.material_id = m.id AND s.empresa_id = m.empresa_id
        WHERE m.empresa_id = :eid
          AND m.activo     = TRUE
          AND m.nombre     ILIKE :q
        GROUP BY m.id, m.nombre, m.unidad
        ORDER BY m.nombre ASC
        LIMIT 20
    """), {"eid": empresa_id, "q": f"%{q}%"}).fetchall()

    return [{"id": r.id, "nombre": r.nombre, "unidad": r.unidad, "stock": int(r.stock)} for r in rows]
