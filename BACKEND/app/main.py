from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class Usuario(BaseModel):
    nombre: str
    edad: int

@app.get("/")
def read_root():
    return {"mensaje": "API funcionando 🚀"}

@app.post("/usuarios")
def crear_usuario(usuario: Usuario):
    return {
        "mensaje": "Usuario creado",
        "data": usuario
    }