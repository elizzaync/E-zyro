from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.routers import auth, dashboard
from app.services.scheduler_service import iniciar_scheduler, detener_scheduler
@asynccontextmanager
async def lifespan(app: FastAPI):
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

# Incluir los routers
app.include_router(auth.router)
app.include_router(dashboard.router)


@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo"}