from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from sqlalchemy import text
import time

from app.db.database import engine, Base
from app.routers import auth, dashboard
from app.routers import permisos        as permisos_router
from app.routers import asistencia      as asistencia_router
from app.routers import proyectos       as proyectos_router
from app.routers import comunicados     as comunicados_router
from app.routers import operaciones     as operaciones_router
from app.routers import chat_ws         as chat_ws_router
from app.routers import notificaciones  as notificaciones_router
from app.routers import requerimientos  as requerimientos_router
from app.routers import auditoria       as auditoria_router
from app.services.scheduler_service import iniciar_scheduler, detener_scheduler
from app.core.audit_context import AuditContextMiddleware
import app.core.audit_listener  # noqa: F401 — registra el listener al importar

# Importar todos los modelos para que Base los registre antes de create_all
from app.models import (  # noqa: F401
    # Core
    #corex
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
    # Comunicados
    comunicado,
    # Equipos y mantenimiento
    tipo_equipo, equipo, plan_mantenimiento,
    orden_mantenimiento, evidencia_mantenimiento, informe_tecnico,
    paso_mantenimiento,
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
        conn.execute(text(
            "ALTER TABLE auditoria "
            "ADD COLUMN IF NOT EXISTS empresa_id VARCHAR(36)"
        ))
        # ── HU-MANT: tabla paso_mantenimiento (checklist técnico por equipo) ──
        # NOTA: los IDs en este esquema son `uuid` (vienen del backup original).
        # Las FKs DEBEN ser uuid para no romper. SQLAlchemy mapea el campo Python
        # `String(36)` <-> postgres `uuid` de forma transparente.
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS paso_mantenimiento (
                id          uuid PRIMARY KEY,
                equipo_id   uuid NOT NULL REFERENCES equipo(id),
                empresa_id  uuid NOT NULL REFERENCES empresa(id),
                nombre      VARCHAR(200) NOT NULL,
                descripcion TEXT,
                orden       INTEGER NOT NULL DEFAULT 1,
                estado      VARCHAR(20) NOT NULL DEFAULT 'pendiente',
                created_at  TIMESTAMP NOT NULL DEFAULT now(),
                updated_at  TIMESTAMP
            )
        """))
        conn.execute(text(
            "ALTER TABLE evidencia_mantenimiento "
            "ADD COLUMN IF NOT EXISTS paso_id uuid "
            "REFERENCES paso_mantenimiento(id)"
        ))
        conn.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='auditoria'
                      AND column_name='datos_anteriores'
                      AND data_type='text'
                ) THEN
                    ALTER TABLE auditoria
                        ALTER COLUMN datos_anteriores
                        TYPE JSONB USING NULLIF(datos_anteriores,'')::jsonb;
                    ALTER TABLE auditoria
                        ALTER COLUMN datos_nuevos
                        TYPE JSONB USING NULLIF(datos_nuevos,'')::jsonb;
                END IF;
            END $$;
        """))
        conn.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    for intento in range(10):
        try:
            Base.metadata.create_all(bind=engine)
            _run_migrations()
            break
        except Exception as e:
            if intento == 9:
                raise
            print(f"DB no disponible (intento {intento + 1}/10), reintentando en 3s... {e}")
            time.sleep(3)
    iniciar_scheduler()
    yield
    detener_scheduler()


app = FastAPI(title="API E-zyro", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(AuditContextMiddleware)

app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(permisos_router.router)
app.include_router(asistencia_router.router)
app.include_router(proyectos_router.router)
app.include_router(comunicados_router.router)
app.include_router(operaciones_router.router)
app.include_router(chat_ws_router.router)
app.include_router(notificaciones_router.router)
app.include_router(requerimientos_router.router)
app.include_router(auditoria_router.router)


@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo"}
