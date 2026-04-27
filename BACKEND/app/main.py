from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# IMPORTACIONES LOCALES (Sin el "app.")
from database import engine, Base
from models.empresa import Empresa
from models.usuario import Usuario
from models.empleado import Empleado
from models.orden_mantenimiento import OrdenMantenimiento
from models.notificacion import Notificacion

from routers import auth, dashboard

# Crea las tablas
Base.metadata.create_all(bind=engine)

app = FastAPI(title="API E-zyro")

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

@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo y modularizado"}