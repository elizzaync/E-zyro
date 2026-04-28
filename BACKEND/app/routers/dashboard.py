from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc, extract
from typing import Dict, Any
from datetime import date, datetime
import calendar

from app.db.database import get_db

from app.models.proyecto import Proyecto
from app.models.cliente import Cliente
from app.models.catalogo_servicio import CatalogoServicio
from app.models.notificacion import Notificacion
from app.models.empleado import Empleado

from app.core.security import verificar_token

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"]
)

@router.get("/resumen")
async def obtener_resumen_kpis(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": {"activos": 0, "pendientes": 0, "completados": 0}}

        activos = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado.id, Proyecto.estado == 'Activo').count()
        pendientes = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado.id, Proyecto.estado == 'Pendiente').count()
        completados = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado.id, Proyecto.estado == 'Completado').count()

        return {"status": "success", "data": {"activos": activos, "pendientes": pendientes, "completados": completados}}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al calcular resumen operativo")


@router.get("/proximos-servicios")
async def obtener_proximos_servicios(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
             return {"status": "success", "data": []}

        # Consulta Avanzada con JOIN a Cliente y Catalogo para obtener nombres reales
        servicios = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            CatalogoServicio, Proyecto.servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.fecha_inicio >= hoy,
            Proyecto.estado.in_(['Activo', 'Pendiente'])
        ).order_by(asc(Proyecto.fecha_inicio)).limit(3).all()

        data_servicios = []
        for proyecto, cliente, catalogo in servicios:
            etiqueta_fecha = "Hoy" if proyecto.fecha_inicio == hoy else proyecto.fecha_inicio.strftime("%d/%m/%Y")

            data_servicios.append({
                "empresa": cliente.razon_social,
                "tipo": catalogo.nombre,
                "fecha": etiqueta_fecha,
                "hora": proyecto.orden_trabajo, # Mostramos la OT como identificador rápido
                "estado": proyecto.estado
            })

        return {"status": "success", "data": data_servicios}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar próximos servicios")


@router.get("/notificaciones")
async def obtener_notificaciones(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        notificaciones = db.query(Notificacion).filter(Notificacion.usuario_id == usuario_id).order_by(desc(Notificacion.created_at)).limit(2).all()
        data_notificaciones = [{"titulo": n.titulo, "tiempo": n.created_at.strftime("%H:%M")} for n in notificaciones]
        return {"status": "success", "data": data_notificaciones}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar notificaciones")


@router.get("/rendimiento-mensual")
async def obtener_rendimiento_mensual(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()
        mes_actual = hoy.month
        anio_actual = hoy.year

        # Nombres de meses en español
        meses_es = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
        nombre_mes = meses_es[mes_actual]

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            raise HTTPException(status_code=400, detail="Usuario no es empleado")

        # Consultar todos los proyectos del mes actual para este usuario
        proyectos_mes = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            extract('month', Proyecto.fecha_inicio) == mes_actual,
            extract('year', Proyecto.fecha_inicio) == anio_actual
        ).all()

        total_servicios = len(proyectos_mes)

        # Clasificar por semanas y estado
        semanas_data = [
            {"nombre": "Semana 1", "completados": 0, "total": 0},
            {"nombre": "Semana 2", "completados": 0, "total": 0},
            {"nombre": "Semana 3", "completados": 0, "total": 0},
            {"nombre": "Semana 4", "completados": 0, "total": 0}
        ]

        total_completados_mes = 0

        for p in proyectos_mes:
            if not p.fecha_inicio: continue
            dia = p.fecha_inicio.day
            indice_semana = min((dia - 1) // 7, 3) # Distribuye del 0 al 3 (Semanas 1 a 4)

            semanas_data[indice_semana]["total"] += 1
            if p.estado == 'Completado':
                semanas_data[indice_semana]["completados"] += 1
                total_completados_mes += 1

        # Calcular porcentaje de éxito
        tasa_exito = round((total_completados_mes / total_servicios) * 100) if total_servicios > 0 else 0

        return {
            "status": "success",
            "data": {
                "mesActual": f"{nombre_mes} {anio_actual}",
                "semanas": semanas_data,
                "stats": {
                    "tasaExito": f"{tasa_exito}%",
                    "totalServicios": total_completados_mes, # Completados exitosos
                    "esteMes": total_servicios # Total asignados este mes
                }
            }
        }
    except Exception as e:
        print(f"Error en rendimiento: {e}")
        raise HTTPException(status_code=500, detail="Error al calcular rendimiento mensual")