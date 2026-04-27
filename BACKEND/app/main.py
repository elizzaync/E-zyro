from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, dashboard
app = FastAPI(title="API E-zyro")
# 1. Configurar los dominios permitidos (CORS)
origenes_permitidos = [
    "http://localhost:4200",
      "*"  # Tu Angular en local
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origenes_permitidos,
    allow_credentials=True,
    allow_methods=["*"], # Permite POST, GET, PUT, DELETE
    allow_headers=["*"], # Permite enviar tokens y headers
)
# 2. Incluir los routers
app.include_router(auth.router)
app.include_router(dashboard.router)
@app.get("/")
def read_root():
    return {"mensaje": "Backend de E-zyro activo"}