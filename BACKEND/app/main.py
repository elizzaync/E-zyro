from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from sqlalchemy import text

from app.db.database import engine, Base
from app.routers import auth, dashboard
from app.routers import permisos as permisos_router
from app.services.scheduler_service import iniciar_scheduler, detener_scheduler

# Importar todos los modelos para que Base los registre antes de create_all
from app.models import (  # noqa: F401
    auditoria, catalogo_servicio, categoria_habilidad, cliente,
    dispositivo_push, empleado, empleado_habilidad, empresa, habilidad,
    notificacion, orden_mantenimiento, permiso, proyecto, proyecto_detalle,
    proyecto_miembro, proyecto_servicio, recuperacion_password,
    registro_asistencia, rol, rol_permiso, sesion_usuario,
    solicitud_laboral, usuario, usuario_permiso, usuario_rol,
    contrato, documento_laboral, firma_digital,
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
        conn.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Crear tablas nuevas (firma_digital) sin tocar las existentes
    Base.metadata.create_all(bind=engine)
    # Agregar columnas nuevas a tablas existentes
    _run_migrations()
    iniciar_scheduler()
    yield
    detener_scheduler()


app = FastAPI(title="API E-zyro", lifespan=lifespan)

origenes_permitidos = [
    "http://localhost:4200",
    "*"
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origenes_permitidos,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(permisos_router.router)


@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo"}
