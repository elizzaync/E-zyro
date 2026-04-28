from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc, extract
from typing import Dict, Any
from datetime import date, datetime
import calendar
from app.models.empresa import Empresa
from app.models.usuario import Usuario
from pydantic import BaseModel
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

class NotaCalendario(BaseModel):
    fecha: str
    texto: str

# 👇 UN SOLO ENDPOINT QUE TRAE TODO EL PANEL DE GOLPE
@router.get("/panel-completo")
def obtener_panel_completo(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            raise HTTPException(status_code=400, detail="Empleado no encontrado")

        empleado_id = empleado.id

        # 1. KPIs
        activos = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado_id, Proyecto.estado == 'Activo').count()
        pendientes = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado_id, Proyecto.estado == 'Pendiente').count()
        completados = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado_id, Proyecto.estado == 'Completado').count()

        # 2. Proyectos y Calendario (En una sola consulta)
        proyectos_usuario = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            CatalogoServicio, Proyecto.servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado_id,
            Proyecto.estado.in_(['Activo', 'Pendiente'])
        ).order_by(asc(Proyecto.fecha_inicio)).all()

        dias_con_servicio = []
        proximos_eventos = []
        meses_abrev = ["", "ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]

        for p, c, cat in proyectos_usuario:
            if p.fecha_inicio:
                dias_con_servicio.append(p.fecha_inicio.strftime("%Y-%m-%d"))
                if p.fecha_inicio >= hoy and len(proximos_eventos) < 3:
                    proximos_eventos.append({
                        "empresa": c.razon_social,
                        "tipo": cat.nombre,
                        "fecha": "Hoy" if p.fecha_inicio == hoy else p.fecha_inicio.strftime("%d/%m/%Y"),
                        "hora": p.orden_trabajo,
                        "estado": p.estado,
                        "dia": str(p.fecha_inicio.day),
                        "mes": meses_abrev[p.fecha_inicio.month],
                        "activo": p.fecha_inicio == hoy
                    })

        # 3. Notificaciones y Notas (En una sola consulta)
        notifs_db = db.query(Notificacion).filter(Notificacion.usuario_id == usuario_id).order_by(desc(Notificacion.created_at)).all()
        notificaciones_lista = []
        notas_calendario = {}

        for n in notifs_db:
            if n.categoria == 'Nota Calendario' and n.fecha_envio:
                notas_calendario[n.fecha_envio.strftime("%Y-%m-%d")] = n.mensaje
            elif len(notificaciones_lista) < 2 and n.categoria != 'Nota Calendario':
                notificaciones_lista.append({"titulo": n.titulo, "tiempo": n.created_at.strftime("%H:%M")})

        # 4. Rendimiento Mensual
        mes_actual = hoy.month
        anio_actual = hoy.year
        proyectos_mes = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado_id,
            extract('month', Proyecto.fecha_inicio) == mes_actual,
            extract('year', Proyecto.fecha_inicio) == anio_actual
        ).all()

        semanas_data = [{"nombre": f"Semana {i+1}", "completados": 0, "total": 0} for i in range(4)]
        total_completados_mes = 0

        for p in proyectos_mes:
            if not p.fecha_inicio: continue
            indice_semana = min((p.fecha_inicio.day - 1) // 7, 3)
            semanas_data[indice_semana]["total"] += 1
            if p.estado == 'Completado':
                semanas_data[indice_semana]["completados"] += 1
                total_completados_mes += 1

        total_servicios = len(proyectos_mes)
        tasa_exito = round((total_completados_mes / total_servicios) * 100) if total_servicios > 0 else 0

        meses_es = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

        # CONSTRUIR EL JSON MAESTRO
        return {
            "status": "success",
            "data": {
                "kpis": {"activos": activos, "pendientes": pendientes, "completados": completados},
                "proximos_servicios": proximos_eventos,
                "notificaciones": notificaciones_lista,
                "calendario": {
                    "proximosEventos": proximos_eventos[:2], # Máximo 2
                    "notas": notas_calendario,
                    "diasConServicio": dias_con_servicio
                },
                "rendimiento": {
                    "mesActual": f"{meses_es[mes_actual]} {anio_actual}",
                    "semanas": semanas_data,
                    "stats": {
                        "tasaExito": f"{tasa_exito}%",
                        "totalServicios": total_completados_mes,
                        "esteMes": total_servicios
                    }
                }
            }
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Error cargando panel principal")

# La ruta POST se mantiene intacta para guardar notas
@router.post("/calendario/nota")
def guardar_nota_calendario(nota: NotaCalendario, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        texto_limpio = nota.texto.strip() if nota.texto else ""
        fecha_obj = datetime.strptime(nota.fecha, "%Y-%m-%d")

        nota_existente = db.query(Notificacion).filter(
            Notificacion.usuario_id == usuario_id,
            Notificacion.categoria == 'Nota Calendario',
            Notificacion.fecha_envio == fecha_obj
        ).first()

        if not texto_limpio:
            if nota_existente:
                db.delete(nota_existente)
                db.commit()
            return {"status": "success"}

        if nota_existente:
            nota_existente.mensaje = texto_limpio
            nota_existente.titulo = f"Alerta: {texto_limpio[:25]}..."
        else:
            nueva_notif = Notificacion(
                empresa_id=empresa_id,
                usuario_id=usuario_id,
                tipo="Alerta",
                categoria="Nota Calendario",
                titulo=f"Alerta: {texto_limpio[:25]}...",
                mensaje=texto_limpio,
                fecha_envio=fecha_obj
            )
            db.add(nueva_notif)

        db.commit()
        return {"status": "success"}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))