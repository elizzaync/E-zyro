from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc, extract, func, case
from typing import Dict, Any, Optional
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

# 👇 IMPORTAMOS LA CONFIGURACIÓN CENTRALIZADA DE CLOUDINARY
from app.core.config_cloudinary import cloudinary_uploader

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"]
)

# Modelos Pydantic para recibir datos desde Angular
class NotaCalendario(BaseModel):
    fecha: str
    texto: str
class PerfilUpdate(BaseModel):
    nombre: str
    apellido: str
    telefono: str
    fotoBase64: Optional[str] = None


@router.get("/resumen")
def obtener_resumen_kpis(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": {"activos": 0, "pendientes": 0, "completados": 0}}

        kpis = db.query(
            func.sum(case((Proyecto.estado == 'Activo', 1), else_=0)).label('activos'),
            func.sum(case((Proyecto.estado == 'Pendiente', 1), else_=0)).label('pendientes'),
            func.sum(case((Proyecto.estado == 'Completado', 1), else_=0)).label('completados')
        ).filter(Proyecto.empresa_id == empresa_id, Proyecto.jefe_operaciones_id == empleado.id).first()

        return {"status": "success", "data": {
            "activos": int(kpis.activos or 0),
            "pendientes": int(kpis.pendientes or 0),
            "completados": int(kpis.completados or 0)
        }}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al calcular resumen")

@router.get("/proximos-servicios")
def obtener_proximos_servicios(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado: return {"status": "success", "data": []}

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
        for p, c, cat in servicios:
            data_servicios.append({
                "empresa": c.razon_social,
                "tipo": cat.nombre,
                "fecha": "Hoy" if p.fecha_inicio == hoy else p.fecha_inicio.strftime("%d/%m/%Y"),
                "hora": p.orden_trabajo,
                "estado": p.estado
            })
        return {"status": "success", "data": data_servicios}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar próximos servicios")

@router.get("/notificaciones")
def obtener_notificaciones(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        hoy = date.today()

        notificaciones_db = db.query(Notificacion).filter(
            Notificacion.usuario_id == usuario_id,
            Notificacion.leido == False
        ).order_by(desc(Notificacion.created_at)).all()

        data = []
        for n in notificaciones_db:
            if n.categoria == 'Nota Calendario':
                if n.fecha_envio and (n.fecha_envio.date() - hoy).days <= 1:
                    data.append({"id": n.id, "titulo": n.titulo, "mensaje": n.mensaje, "tiempo": n.created_at.strftime("%H:%M")})
            else:
                data.append({"id": n.id, "titulo": n.titulo, "mensaje": n.mensaje, "tiempo": n.created_at.strftime("%H:%M")})

        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar notificaciones")

@router.put("/notificaciones/{noti_id}/ignorar")
def ignorar_notificacion(noti_id: str, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    noti = db.query(Notificacion).filter(Notificacion.id == noti_id, Notificacion.usuario_id == current_user.get("id")).first()
    if noti:
        noti.leido = True
        db.commit()
    return {"status": "success"}

@router.get("/rendimiento-mensual")
def obtener_rendimiento_mensual(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()
        mes_actual, anio_actual = hoy.month, hoy.year
        meses_es = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado: raise HTTPException(status_code=400, detail="Usuario no es empleado")

        primer_dia = date(anio_actual, mes_actual, 1)
        ultimo_dia = date(anio_actual, mes_actual, calendar.monthrange(anio_actual, mes_actual)[1])

        proyectos_mes = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.fecha_inicio >= primer_dia,
            Proyecto.fecha_inicio <= ultimo_dia
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

        return {
            "status": "success",
            "data": {
                "mesActual": f"{meses_es[mes_actual]} {anio_actual}",
                "semanas": semanas_data,
                "stats": {"tasaExito": f"{tasa_exito}%", "totalServicios": total_completados_mes, "esteMes": total_servicios}
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error rendimiento")

@router.get("/calendario")
def obtener_calendario(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        hoy = date.today()

        proyectos_usuario = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id if empleado else True,
            Proyecto.estado.in_(['Activo', 'Pendiente'])
        ).all()

        dias_con_servicio = [p.fecha_inicio.strftime("%Y-%m-%d") for p in proyectos_usuario if p.fecha_inicio]

        meses_abrev = ["", "ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]
        proximos_proyectos = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            CatalogoServicio, Proyecto.servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.jefe_operaciones_id == empleado.id if empleado else True,
            Proyecto.fecha_inicio >= hoy,
            Proyecto.estado.in_(['Activo', 'Pendiente'])
        ).order_by(asc(Proyecto.fecha_inicio)).limit(2).all()

        proximos_eventos = []
        for p, c, cat in proximos_proyectos:
            if p.fecha_inicio:
                proximos_eventos.append({
                    "dia": str(p.fecha_inicio.day), "mes": meses_abrev[p.fecha_inicio.month],
                    "empresa": c.razon_social, "tipo": cat.nombre,
                    "hora": "09:00 AM", "activo": p.fecha_inicio == hoy
                })

        notas_db = db.query(Notificacion).filter(
            Notificacion.usuario_id == usuario_id, Notificacion.categoria == 'Nota Calendario'
        ).all()

        notas = {}
        for n in notas_db:
            if n.fecha_envio: notas[n.fecha_envio.strftime("%Y-%m-%d")] = n.mensaje

        return {"status": "success", "data": {"proximosEventos": proximos_eventos, "notas": notas, "diasConServicio": dias_con_servicio}}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error cargando calendario")

@router.post("/calendario/nota")
def guardar_nota_calendario(nota: NotaCalendario, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        texto_limpio = nota.texto.strip() if nota.texto else ""
        fecha_obj = datetime.strptime(nota.fecha, "%Y-%m-%d")

        nota_existente = db.query(Notificacion).filter(Notificacion.usuario_id == usuario_id, Notificacion.categoria == 'Nota Calendario', Notificacion.fecha_envio == fecha_obj).first()

        if not texto_limpio:
            if nota_existente:
                db.delete(nota_existente)
                db.commit()
            return {"status": "success"}

        if nota_existente:
            nota_existente.mensaje = texto_limpio
            nota_existente.titulo = f"Alerta: {texto_limpio[:25]}..."
        else:
            nueva_notif = Notificacion(empresa_id=empresa_id, usuario_id=usuario_id, tipo="Alerta", categoria="Nota Calendario", titulo=f"Alerta: {texto_limpio[:25]}...", mensaje=texto_limpio, fecha_envio=fecha_obj)
            db.add(nueva_notif)
        db.commit()
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# =========================================================================
# RUTAS DE PERFIL (CONSULTA Y ACTUALIZACIÓN CON CLOUDINARY)
# =========================================================================

@router.get("/perfil")
def obtener_perfil_usuario(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")

        resultado = db.query(Usuario, Empleado, Empresa).join(
            Empleado, Empleado.usuario_id == Usuario.id
        ).join(
            Empresa, Empresa.id == Usuario.empresa_id
        ).filter(Usuario.id == usuario_id).first()

        if not resultado:
            raise HTTPException(status_code=404, detail="Perfil no encontrado")

        usuario, empleado, empresa = resultado
        meses = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
        fecha_txt = ""

        fecha_referencia = empleado.fecha_ingreso or usuario.created_at
        if fecha_referencia:
            fecha_txt = f"{fecha_referencia.day} de {meses[fecha_referencia.month]}, {fecha_referencia.year}"

        # 👇 ENVIAMOS NOMBRE Y APELLIDO SEPARADOS AL FRONTEND
        return {
            "status": "success",
            "data": {
                "personal": {
                    "id": usuario.id,
                    "nombre": usuario.nombre,
                    "apellido": usuario.apellido,
                    "correo": usuario.email,
                    "telefono": usuario.telefono or "",
                    "fotoUrl": usuario.foto_url or "",
                    "rol": empleado.cargo,
                    "fechaCreacion": fecha_txt
                },
                "empresa": {
                    "id": empresa.id,
                    "nombre": empresa.razon_social,
                    "ruc": empresa.ruc,
                    "ubicacion": "Sede Principal"
                }
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar el perfil")

@router.put("/perfil")
def actualizar_perfil(datos: PerfilUpdate, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()

        if not usuario:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        # 👇 GUARDAMOS DIRECTAMENTE SIN HACER SPLIT
        usuario.nombre = datos.nombre.strip()
        usuario.apellido = datos.apellido.strip()
        usuario.telefono = datos.telefono

        if datos.fotoBase64 and datos.fotoBase64.startswith("data:image"):
            upload_result = cloudinary_uploader.upload(
                datos.fotoBase64,
                public_id=f"perfil_{usuario.id}",
                folder="e-zyro/perfiles",
                overwrite=True,
                invalidate=True
            )
            usuario.foto_url = upload_result.get("secure_url")

        db.commit()
        return {"status": "success", "foto_url": usuario.foto_url}

    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error interno actualizando perfil")