from fastapi import APIRouter, Depends
from app.core.security import verificar_token # Importamos al guardia

router = APIRouter(prefix="/tareas", tags=["Tareas"])

# Al poner "Depends(verificar_token)", FastAPI exige una pulsera válida antes de ejecutar el código
@router.get("/mis-tareas")
def obtener_tareas(usuario_actual: dict = Depends(verificar_token)):

    # Gracias al JWT, ¡ya sabes quién es sin buscar en la BD!
    id_tecnico = usuario_actual.get("id")
    id_empresa = usuario_actual.get("empresa_id")

    # Aquí buscarías las tareas de E-System Tic asignadas a ese técnico...

    return {"mensaje": f"Devolviendo tareas para la empresa {id_empresa}"}