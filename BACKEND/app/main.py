# BACKEND/app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth
app = FastAPI(title="API E-zyro Backend")
# Configuración de CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Cambiar en producción
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Conectamos el router de autenticación a la app principal
app.include_router(auth.router)
@app.get("/")
def read_root():
    return {"mensaje": "API de e-zyro funcionando en Railway 🚀"}