from typing import Optional
from pydantic import BaseModel, EmailStr, Field
# --- LOGIN ---
class LoginData(BaseModel):
    username:  str
    password:  str
    device_id: Optional[str] = None   # UUID persistente generado en el cliente
    plataforma: Optional[str] = None  # 'movil' (app → token largo) | None/web (token corto)
# --- RECUPERACIÓN DE CONTRASEÑA ---
# 1. Para la solicitud inicial
class PasswordResetRequest(BaseModel):
    email: EmailStr
# 2. PARA LA VERIFICACIÓN (Esta es la que te falta en el error)
class PasswordVerifyCode(BaseModel):
    email: EmailStr
    code: str = Field(..., min_length=6, max_length=6)
# 3. Para el cambio final de clave
class PasswordResetConfirm(BaseModel):
    email: EmailStr
    code: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=6)