from fastapi import APIRouter, HTTPException, status
from app.schemas.auth import LoginData
# Creamos un router especifico para todo lo relacionado con autenticacion
router = APIRouter(
    prefix="/auth",
    tags=["Autenticacion"]
)
@router.post("/login")
def login_usuario(credenciales: LoginData):
    # Logica estatica temporal
    if credenciales.username == "admin" and credenciales.password == "123456":
        return {
            "status": "success",
            "mensaje": "Autenticacion exitosa",
            "data": {
                "username": credenciales.username,
                "rol": "administrador",
                "token": "fake-jwt-token-12345"
            }
        }
    else:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contrasena incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )