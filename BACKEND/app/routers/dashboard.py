# app/routers/dashboard.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc, extract, func, case, or_
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
from app.models.rol import Rol
from app.models.usuario_rol import UsuarioRol
from app.models.permiso import Permiso
from app.models.rol_permiso import RolPermiso
from app.models.usuario_permiso import UsuarioPermiso
from app.models.proyecto_miembro import ProyectoMiembro
# Servicio de Cloudinary optimizado con destructor
from app.services.cloudinary_service import subir_imagen_cloudinary, eliminar_imagen_cloudinary

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"]
)

# =========================================================================
# MODELOS PYDANTIC
# =========================================================================
class NotaCalendario(BaseModel):
    fecha: str
    texto: str

class PerfilUpdate(BaseModel):
    nombre: str
    apellido: str
    telefono: str
    fotoBase64: Optional[str] = None

# =========================================================================
# RUTAS DE WIDGETS (HOME)
# =========================================================================
@router.get("/resumen")
def obtener_resumen_kpis(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": {"activos": 0, "pendientes": 0, "completados": 0}}

        # 🔥 LA MAGIA: Solo ve proyectos si es el jefe O si está asignado como miembro
        condicion_visibilidad = or_(
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
        )

        kpis = db.query(
            func.sum(case((Proyecto.estado == 'En_Proceso', 1), else_=0)).label('activos'),
            func.sum(case((Proyecto.estado == 'Pendiente', 1), else_=0)).label('pendientes'),
            func.sum(case((Proyecto.estado == 'Completado', 1), else_=0)).label('completados')
        ).filter(Proyecto.empresa_id == empresa_id, condicion_visibilidad).first()

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

        condicion_visibilidad = or_(
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
        )

        servicios = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            CatalogoServicio, Proyecto.servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.fecha_inicio >= hoy,
            Proyecto.estado.in_(['En_Proceso', 'Pendiente']),
            condicion_visibilidad
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

        condicion_visibilidad = or_(
            Proyecto.jefe_operaciones_id == empleado.id,
            Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
        )

        primer_dia = date(anio_actual, mes_actual, 1)
        ultimo_dia = date(anio_actual, mes_actual, calendar.monthrange(anio_actual, mes_actual)[1])

        proyectos_mes = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.fecha_inicio >= primer_dia,
            Proyecto.fecha_inicio <= ultimo_dia,
            condicion_visibilidad
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
        hoy = date.today()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        # 🔥 FIX 1: Filtros dinámicos estructurados (Evita el error de "condicion_visibilidad = True")
        filtros_base = [
            Proyecto.empresa_id == empresa_id,
            Proyecto.estado.in_(['En_Proceso', 'Pendiente'])
        ]

        # Si es un empleado, agregamos la condición de que sea jefe o miembro
        if empleado:
            filtros_base.append(or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
            ))

        # Aplicamos los filtros desglosados
        proyectos_usuario = db.query(Proyecto).filter(*filtros_base).all()

        dias_con_servicio = [p.fecha_inicio.strftime("%Y-%m-%d") for p in proyectos_usuario if p.fecha_inicio]

        meses_abrev = ["", "ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]

        # Reutilizamos los filtros base pero añadimos la restricción de fecha para "Próximos Eventos"
        proximos_proyectos = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            CatalogoServicio, Proyecto.servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.fecha_inicio >= hoy,
            *filtros_base
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
            if n.fecha_envio:
                # 🔥 FIX 2: Conversión a prueba de fallos (Soporta DateTime de Python o Strings de la BD)
                if hasattr(n.fecha_envio, 'strftime'):
                    fecha_str = n.fecha_envio.strftime("%Y-%m-%d")
                else:
                    fecha_str = str(n.fecha_envio)[:10]  # Extrae solo el "YYYY-MM-DD"

                notas[fecha_str] = n.mensaje

        return {"status": "success", "data": {"proximosEventos": proximos_eventos, "notas": notas, "diasConServicio": dias_con_servicio}}
    except Exception as e:
        print(f"ERROR FATAL EN CALENDARIO: {str(e)}") # Esto te ayudará a ver qué pasa en los logs de Railway
        raise HTTPException(status_code=500, detail=str(e))

    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        condicion_visibilidad = True
        if empleado:
            condicion_visibilidad = or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
            )

        proyectos_usuario = db.query(Proyecto).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.estado.in_(['En_Proceso', 'Pendiente']),
            condicion_visibilidad
        ).all()

        dias_con_servicio = [p.fecha_inicio.strftime("%Y-%m-%d") for p in proyectos_usuario if p.fecha_inicio]

        meses_abrev = ["", "ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]
        proximos_proyectos = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            CatalogoServicio, Proyecto.servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.empresa_id == empresa_id,
            Proyecto.fecha_inicio >= hoy,
            Proyecto.estado.in_(['En_Proceso', 'Pendiente']),
            condicion_visibilidad
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
# RUTAS DE PERFIL Y SEGURIDAD (RBAC + CLOUDINARY OPTIMIZADO)
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

        # Motor de Permisos (Rol + Directos)
        permisos_rol = db.query(Permiso.modulo).join(
            RolPermiso, RolPermiso.permiso_id == Permiso.id
        ).join(
            UsuarioRol, UsuarioRol.rol_id == RolPermiso.rol_id
        ).filter(UsuarioRol.usuario_id == usuario_id).all()

        permisos_directos = db.query(Permiso.modulo).join(
            UsuarioPermiso, UsuarioPermiso.permiso_id == Permiso.id
        ).filter(UsuarioPermiso.usuario_id == usuario_id).all()

        modulos_permitidos = list(set(
            [p[0].upper() for p in permisos_rol] +
            [p[0].upper() for p in permisos_directos]
        ))

        meses = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
        fecha_txt = ""
        fecha_ref = empleado.fecha_ingreso or usuario.created_at
        if fecha_ref:
            fecha_txt = f"{fecha_ref.day} de {meses[fecha_ref.month]}, {fecha_ref.year}"

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
                    "fechaCreacion": fecha_txt,
                    "permisos_modulo": modulos_permitidos
                },
                "empresa": {
                    "id": empresa.id, # 👈 AQUÍ ESTÁ EL ID DE EMPRESA QUE EVITA QUE ANGULAR EXPLOTE
                    "nombre": empresa.razon_social,
                    "ruc": empresa.ruc,
                    "ubicacion": "Sede Principal"
                }
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar perfil")

@router.put("/perfil")
def actualizar_perfil(datos: PerfilUpdate, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()

        if not usuario:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        usuario.nombre = datos.nombre.strip()
        usuario.apellido = datos.apellido.strip()
        usuario.telefono = datos.telefono

        # Subida a Cloudinary
        if datos.fotoBase64 and datos.fotoBase64.startswith("data:image"):

            # 👇 Si el usuario ya tenía foto, la eliminamos primero para no dejar "archivos huérfanos"
            if usuario.foto_url:
                eliminar_imagen_cloudinary(usuario.foto_url)

            # 👇 Creamos el nombre personalizado (id_nombre)
            primer_nombre = usuario.nombre.split(" ")[0].lower()
            nombre_archivo = f"{usuario.id}_{primer_nombre}"

            url_optimizada = subir_imagen_cloudinary(
                base64_data=datos.fotoBase64,
                folder="e-zyro/perfiles",
                public_id=nombre_archivo,
                is_perfil=True
            )
            usuario.foto_url = url_optimizada

        db.commit()
        return {"status": "success", "foto_url": usuario.foto_url}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error al actualizar perfil")