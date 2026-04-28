from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc
from typing import Dict, Any
from datetime import date

from app.db.database import get_db

# 👇 NUEVO: Importamos Proyecto en lugar de OrdenMantenimiento
from app.models.proyecto import Proyecto
from app.models.notificacion import Notificacion
from app.models.empleado import Empleado

from app.core.security import verificar_token

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"]
)

@router.get("/resumen")
async def obtener_resumen_kpis(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
) -> Dict[str, Any]:
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        if not empleado:
            return {"status": "success", "data": {"activos": 0, "pendientes": 0, "completados": 0}}

        # 👇 AHORA CONSULTAMOS A LA TABLA PROYECTO
        activos = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.estado == 'Activo'
        ).count()

        pendientes = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.estado == 'Pendiente'
        ).count()

        completados = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.estado == 'Completado'
        ).count()

        return {
            "status": "success",
            "data": {
                "activos": activos,
                "pendientes": pendientes,
                "completados": completados
            }
        }
    except Exception as e:
        print(f"Error en KPIs: {e}")
        raise HTTPException(status_code=500, detail="Error al calcular resumen operativo")


@router.get("/proximos-servicios")
async def obtener_proximos_servicios(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
) -> Dict[str, Any]:
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        if not empleado:
             return {"status": "success", "data": []}

        servicios = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.fecha_inicio >= hoy,
            Proyecto.estado.in_(['Activo', 'Pendiente'])
        ).order_by(asc(Proyecto.fecha_inicio)).limit(3).all()

        data_servicios = []
        for s in servicios:
            etiqueta_fecha = "Hoy" if s.fecha_inicio == hoy else s.fecha_inicio.strftime("%d/%m/%Y")

            data_servicios.append({
                "empresa": "TechCorp S.A.", # Simulado por ahora
                "tipo": s.nombre_proyecto,  # Mostrará "SISTEMA ELECTRICO TACNA..."
                "fecha": etiqueta_fecha,
                "hora": s.orden_trabajo,    # Temporalmente mostramos la OT aquí
                "estado": s.estado
            })

        return {"status": "success", "data": data_servicios}

    except Exception as e:
        print(f"Error en servicios: {e}")
        raise HTTPException(status_code=500, detail="Error al cargar próximos servicios")


@router.get("/notificaciones")
async def obtener_notificaciones(
    current_user: dict = Depends(verificar_token),
    db: Session = Depends(get_db)
) -> Dict[str, Any]:
    try:
        usuario_id = current_user.get("id")

        notificaciones = db.query(Notificacion).filter(
            Notificacion.usuario_id == usuario_id
        ).order_by(desc(Notificacion.created_at)).limit(2).all()

        data_notificaciones = []
        for n in notificaciones:
            data_notificaciones.append({
                "titulo": n.titulo,
                "tiempo": n.created_at.strftime("%H:%M")
            })

        return {"status": "success", "data": data_notificaciones}

    except Exception as e:
        print(f"Error en notificaciones: {e}")
        raise HTTPException(status_code=500, detail="Error al cargar notificaciones")