from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from sqlalchemy import text

from app.db.database import engine, Base
from app.routers import auth, dashboard
from app.routers import permisos        as permisos_router
from app.routers import asistencia      as asistencia_router
from app.routers import proyectos       as proyectos_router
from app.routers import comunicados     as comunicados_router
from app.routers import operaciones     as operaciones_router
from app.routers import chat_ws         as chat_ws_router
from app.routers import notificaciones  as notificaciones_router
from app.services.scheduler_service import iniciar_scheduler, detener_scheduler

# Importar todos los modelos para que Base los registre antes de create_all
from app.models import (  # noqa: F401
    # Core
    empresa, plan_suscripcion, suscripcion,
    # Usuarios y roles
    usuario, rol, permiso, rol_permiso, usuario_rol, usuario_permiso,
    recuperacion_password, sesion_usuario, auditoria,
    # Clientes
    cliente, contrato_comercial, usuario_cliente,
    # Empleados
    empleado, contrato, documento_laboral, solicitud_laboral,
    turno, grupo_trabajo,
    categoria_habilidad, habilidad, empleado_habilidad,
    firma_digital, historial_firma, documento_firmado,
    foto_biometrica, dispositivo_push, notificacion,
    # Proyectos
    proyecto, proyecto_detalle, proyecto_miembro, proyecto_servicio,
    catalogo_servicio, fase, seguimiento_proyecto,
    proyecto_equipo, proyecto_grupo, mensaje_chat, programacion_campo,
    # Asistencia
    registro_asistencia, foto_asistencia, geolocalizacion_asistencia,
    # Operaciones / servicios
    procedimiento, evidencia_procedimiento,
    requerimiento, requerimiento_entrega,
    # Inventario: material.py contiene Stock; categoria_material.py y almacen.py son dependencias
    categoria_material, almacen, material, movimiento_inventario,
    # Compras
    proveedor, orden_compra, recepcion_compra,
    # Equipos y mantenimiento
    tipo_equipo, equipo, plan_mantenimiento,
    orden_mantenimiento, evidencia_mantenimiento, informe_tecnico,
    # Caja chica
    caja_chica,
    # Evaluación (contiene CriterioEvaluacion, Evaluacion, DetalleEvaluacion, CalificacionCliente)
    evaluacion,
    # Documentación
    carpeta_documental, plano, recordatorio,
)


def _run_migrations():
    """Aplica migraciones incrementales de forma segura (IF NOT EXISTS)."""
    with engine.connect() as conn:
        conn.execute(text(
            "ALTER TABLE solicitud_laboral "
            "ADD COLUMN IF NOT EXISTS url_pdf VARCHAR(500)"
        ))
        conn.execute(text(
            "ALTER TABLE solicitud_laboral "
            "ADD COLUMN IF NOT EXISTS public_id_pdf VARCHAR(255)"
        ))
        conn.execute(text(
            "ALTER TABLE mensaje_chat "
            "ADD COLUMN IF NOT EXISTS destinatario_id UUID "
            "REFERENCES usuario(id)"
        ))
        conn.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    _run_migrations()
    iniciar_scheduler()
    yield
    detener_scheduler()


app = FastAPI(title="API E-zyro", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(permisos_router.router)
app.include_router(asistencia_router.router)
app.include_router(proyectos_router.router)
app.include_router(comunicados_router.router)
app.include_router(operaciones_router.router)
app.include_router(chat_ws_router.router)
app.include_router(notificaciones_router.router)


@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo"}
