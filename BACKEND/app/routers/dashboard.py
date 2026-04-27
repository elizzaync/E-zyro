from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc
from typing import Dict, Any
from datetime import date

from app.db.database import get_db
from app.models.orden_mantenimiento import OrdenMantenimiento
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

        activos = db.query(OrdenMantenimiento).filter(
            OrdenMantenimiento.empresa_id == empresa_id,
            OrdenMantenimiento.tecnico_id == empleado.id,
            OrdenMantenimiento.estado == 'Activo'
        ).count()

        pendientes = db.query(OrdenMantenimiento).filter(
            OrdenMantenimiento.empresa_id == empresa_id,
            OrdenMantenimiento.tecnico_id == empleado.id,
            OrdenMantenimiento.estado == 'Pendiente'
        ).count()

        completados = db.query(OrdenMantenimiento).filter(
            OrdenMantenimiento.empresa_id == empresa_id,
            OrdenMantenimiento.tecnico_id == empleado.id,
            OrdenMantenimiento.estado == 'Completado'
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

        servicios = db.query(OrdenMantenimiento).filter(
            OrdenMantenimiento.empresa_id == empresa_id,
            OrdenMantenimiento.tecnico_id == empleado.id,
            OrdenMantenimiento.fecha >= hoy,
            OrdenMantenimiento.estado.in_(['Activo', 'Pendiente'])
        ).order_by(asc(OrdenMantenimiento.fecha)).limit(3).all()

        data_servicios = []
        for s in servicios:
            etiqueta_fecha = "Hoy" if s.fecha == hoy else s.fecha.strftime("%d/%m/%Y")

            data_servicios.append({
                "empresa": "Cliente Asignado",
                "tipo": s.tipo,
                "fecha": etiqueta_fecha,
                "hora": "Por definir",
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