from pydantic import BaseModel

# Tu plantilla actual para el Login
class LoginData(BaseModel):
    username: str
    password: str
class PasswordResetRequest(BaseModel):
    email: str