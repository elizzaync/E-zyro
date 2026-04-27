import sys
import os
# 🌟 EL TRUCO MÁGICO: Obligamos a Python a leer esta carpeta como la principal
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Ahora las importaciones funcionarán SIEMPRE, sin el "app."
from database import engine, Base
from models.empresa import Empresa
from models.usuario import Usuario
from models.empleado import Empleado
from models.orden_mantenimiento import OrdenMantenimiento
from models.notificacion import Notificacion

from routers import auth, dashboard

# Crea las tablas en la BD si no existen
Base.metadata.create_all(bind=engine)

app = FastAPI(title="API E-zyro")

# 1. Configurar los dominios permitidos (CORS)
origenes_permitidos = [
    "http://localhost:4200",
    "*"  # Permite conexiones desde cualquier lugar en producción
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
app.include_router(dashboard.router)

@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo y a prueba de errores"}