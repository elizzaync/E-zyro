from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base

# 👇 IMPORTANTE: Importamos cada tabla para que SQLAlchemy las registre
from app.models.empresa import Empresa
from app.models.usuario import Usuario
from app.models.empleado import Empleado
from app.models.orden_mantenimiento import OrdenMantenimiento
from app.models.notificacion import Notificacion

# Importamos los routers
from app.routers import auth, dashboard

# Crea las tablas en la BD si no existen
Base.metadata.create_all(bind=engine)

app = FastAPI(title="API E-zyro")

# 1. Configurar los dominios permitidos (CORS)
origenes_permitidos = [
    "http://localhost:4200",
    "*"  # Tu Angular en local y en prod
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origenes_permitidos,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. Incluir los routers
app.include_router(auth.router)
app.include_router(dashboard.router) # 👈 Añade el del dashboard

@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo y modularizado"}