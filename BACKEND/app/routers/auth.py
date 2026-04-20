# BACKEND/app/routers/auth.py
from fastapi import APIRouter, HTTPException, status
from app.schemas.auth import LoginData

# Creamos un router específico para todo lo relacionado con autenticación
router = APIRouter(
    prefix="/auth",
    tags=["Autenticación"]
)

@router.post("/login")
def login_usuario(credenciales: LoginData):
    # Lógica estática temporal
    if credenciales.username == "admin" and credenciales.password == "123456":
        return {
            "status": "success",
            "mensaje": "Autenticación exitosa",
            "data": {
                "username": credenciales.username,
                "rol": "administrador",
                "token": "fake-jwt-token-12345" # Listo para cuando metamos JWT real
            }
        }
    else:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )