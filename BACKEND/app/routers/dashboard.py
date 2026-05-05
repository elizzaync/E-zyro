# app/routers/dashboard.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc, extract, func, case, or_
from typing import Dict, Any, Optional
from datetime import date, datetime
import calendar

from pydantic import BaseModel
from app.db.database import get_db

# Modelos
from app.models.proyecto_servicio import ProyectoServicio
from app.models.empresa import Empresa
from app.models.usuario import Usuario
from app.models.proyecto import Proyecto
from app.models.cliente import Cliente
from app.models.catalogo_servicio import CatalogoServicio
from app.models.notificacion import Notificacion
from app.models.empleado import Empleado
from app.models.rol import Rol
from app.models.usuario_rol import UsuarioRol
from app.models.permiso import Permiso
from app.models.rol_permiso import RolPermiso
from app.models.usuario_permiso import UsuarioPermiso
from app.models.proyecto_miembro import ProyectoMiembro
from app.models.dispositivo_push import DispositivoPush

# Servicios y Seguridad
from app.core.security import verificar_token
from app.services.cloudinary_service import subir_imagen_cloudinary, eliminar_imagen_cloudinary
from app.services.fcm_service import (
    enviar_push_a_usuario,
    notificar_asignacion_servicio,
    notificar_recordatorio_calendario
)

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


class NotaCalendario(BaseModel):
    fecha: str
    texto: str

class PerfilUpdate(BaseModel):
    nombre: str
    apellido: str
    telefono: str
    fotoBase64: Optional[str] = None

class TokenPush(BaseModel):
    token: str
    plataforma: str = "web"


@router.post("/guardar-token-push")
def guardar_token_push(datos: TokenPush, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")

        dispositivo_existente = db.query(DispositivoPush).filter(
            DispositivoPush.token_push == datos.token
        ).first()

        if not dispositivo_existente:
            nuevo_dispositivo = DispositivoPush(
                usuario_id=usuario_id,
                token_push=datos.token,
                plataforma=datos.plataforma,
                activo=True
            )
            db.add(nuevo_dispositivo)
            db.commit()

        return {"status": "success", "mensaje": "Token sincronizado"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/resumen")
def obtener_resumen_kpis(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        filtros = [Proyecto.empresa_id == empresa_id]
        if empleado:
            filtros.append(or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
            ))

        kpis = db.query(
            func.sum(case((Proyecto.estado == 'En_Proceso', 1), else_=0)).label('activos'),
            func.sum(case((Proyecto.estado == 'Pendiente', 1), else_=0)).label('pendientes'),
            func.sum(case((Proyecto.estado == 'Completado', 1), else_=0)).label('completados')
        ).filter(*filtros).first()

        return {"status": "success", "data": {
            "activos": int(kpis.activos or 0),
            "pendientes": int(kpis.pendientes or 0),
            "completados": int(kpis.completados or 0)
        }}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error resumen")


@router.get("/proximos-servicios")
def obtener_proximos_servicios(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        filtros = [
            Proyecto.empresa_id == empresa_id,
            Proyecto.fecha_inicio >= hoy,
            Proyecto.estado.in_(['En_Proceso', 'Pendiente'])
        ]
        if empleado:
            filtros.append(or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
            ))

        servicios = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            ProyectoServicio, Proyecto.id == ProyectoServicio.proyecto_id
        ).join(
            CatalogoServicio, ProyectoServicio.catalogo_servicio_id == CatalogoServicio.id
        ).filter(*filtros).order_by(asc(Proyecto.fecha_inicio)).limit(3).all()

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
        raise HTTPException(status_code=500, detail="Error próximos servicios")


@router.get("/rendimiento-mensual")
def obtener_rendimiento_mensual(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        hoy = date.today()
        mes_actual, anio_actual = hoy.month, hoy.year
        meses_es = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        primer_dia = date(anio_actual, mes_actual, 1)
        ultimo_dia = date(anio_actual, mes_actual, calendar.monthrange(anio_actual, mes_actual)[1])

        filtros = [
            Proyecto.empresa_id == empresa_id,
            Proyecto.fecha_inicio >= primer_dia,
            Proyecto.fecha_inicio <= ultimo_dia
        ]
        if empleado:
            filtros.append(or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
            ))

        proyectos_mes = db.query(Proyecto).filter(*filtros).all()

        semanas_data = [{"nombre": f"Semana {i+1}", "completados": 0, "total": 0} for i in range(4)]
        total_completados_mes = 0

        for p in proyectos_mes:
            if not p.fecha_inicio:
                continue
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
                "stats": {
                    "tasaExito": f"{tasa_exito}%",
                    "totalServicios": total_completados_mes,
                    "esteMes": total_servicios
                }
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

        filtros_base = [
            Proyecto.empresa_id == empresa_id,
            Proyecto.estado.in_(['En_Proceso', 'Pendiente'])
        ]
        if empleado:
            filtros_base.append(or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(db.query(ProyectoMiembro.proyecto_id).filter(ProyectoMiembro.empleado_id == empleado.id))
            ))

        proyectos_usuario = db.query(Proyecto).filter(*filtros_base).all()
        dias_con_servicio = [p.fecha_inicio.strftime("%Y-%m-%d") for p in proyectos_usuario if p.fecha_inicio]

        meses_abrev = ["", "ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]

        proximos_proyectos = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            ProyectoServicio, Proyecto.id == ProyectoServicio.proyecto_id
        ).join(
            CatalogoServicio, ProyectoServicio.catalogo_servicio_id == CatalogoServicio.id
        ).filter(
            Proyecto.fecha_inicio >= hoy,
            *filtros_base
        ).order_by(asc(Proyecto.fecha_inicio)).limit(2).all()

        proximos_eventos = []
        for p, c, cat in proximos_proyectos:
            if p.fecha_inicio:
                proximos_eventos.append({
                    "dia": str(p.fecha_inicio.day),
                    "mes": meses_abrev[p.fecha_inicio.month],
                    "empresa": c.razon_social,
                    "tipo": cat.nombre,
                    "hora": p.orden_trabajo,
                    "activo": p.fecha_inicio == hoy
                })

        notas_db = db.query(Notificacion).filter(
            Notificacion.usuario_id == usuario_id,
            Notificacion.categoria == 'Nota Calendario'
        ).all()

        notas = {}
        for n in notas_db:
            if n.fecha_envio:
                fecha_str = n.fecha_envio.strftime("%Y-%m-%d") if hasattr(n.fecha_envio, 'strftime') else str(n.fecha_envio)[:10]
                notas[fecha_str] = n.mensaje

        return {
            "status": "success",
            "data": {
                "proximosEventos": proximos_eventos,
                "notas": notas,
                "diasConServicio": dias_con_servicio
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


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

        # Si mandan texto vacío → eliminar la nota
        if not texto_limpio:
            if nota_existente:
                db.delete(nota_existente)
                db.commit()
            return {"status": "success"}

        # Crear o actualizar
        if nota_existente:
            nota_existente.mensaje = texto_limpio
            nota_existente.titulo  = "Alerta de Calendario"
            nota_existente.leido   = False
        else:
            nueva_notif = Notificacion(
                empresa_id=empresa_id,
                usuario_id=usuario_id,
                tipo="Alerta",
                categoria="Nota Calendario",
                titulo="Alerta de Calendario",
                mensaje=texto_limpio,
                fecha_envio=fecha_obj,
                leido=False
            )
            db.add(nueva_notif)

        db.commit()

        # ── Push inmediato solo si el evento es HOY o MAÑANA ─────────────────
        # Para fechas futuras, el scheduler nocturno (8 AM) se encarga.
        fecha_nota = fecha_obj.date()
        hoy        = date.today()
        dias_diff  = (fecha_nota - hoy).days

        if dias_diff == 0:
            cuando = "hoy"
        elif dias_diff == 1:
            cuando = "mañana"
        else:
            cuando = None   # el scheduler lo enviará en su momento

        if cuando:
            notificar_recordatorio_calendario(
                usuario_id=usuario_id,
                texto_nota=texto_limpio,
                cuando=cuando,
                db=db
            )

        return {"status": "success"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


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
                if not n.fecha_envio:
                    continue
                try:
                    fecha_obj     = n.fecha_envio.date() if hasattr(n.fecha_envio, 'date') else datetime.strptime(str(n.fecha_envio)[:10], "%Y-%m-%d").date()
                    dias_diff     = (fecha_obj - hoy).days

                    # Solo mostramos notas de hoy y mañana en el panel
                    if 0 <= dias_diff <= 1:
                        tiempo_str = "Hoy" if dias_diff == 0 else "Mañana"
                        data.append({
                            "id":      n.id,
                            "titulo":  "📅 Evento Próximo",
                            "mensaje": n.mensaje,
                            "tiempo":  tiempo_str,
                            "tipo":    n.tipo
                        })
                except Exception as e:
                    print(f"Error de fecha en notificacion: {e}")
                    continue
            else:
                tiempo_formato = n.created_at.strftime("%d/%m %H:%M") if n.created_at else ""
                data.append({
                    "id":      n.id,
                    "titulo":  n.titulo,
                    "mensaje": n.mensaje,
                    "tiempo":  tiempo_formato,
                    "tipo":    n.tipo
                })

        return {"status": "success", "data": data}
    except Exception as e:
        print(f"Error notificaciones: {e}")
        raise HTTPException(status_code=500, detail="Error al cargar notificaciones")


@router.put("/notificaciones/{noti_id}/ignorar")
def ignorar_notificacion(noti_id: str, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        noti = db.query(Notificacion).filter(
            Notificacion.id == noti_id,
            Notificacion.usuario_id == current_user.get("id")
        ).first()

        if not noti:
            raise HTTPException(status_code=404, detail="Notificación no encontrada")

        noti.leido = True
        db.commit()

        return {"status": "success", "mensaje": "Notificación marcada como leída"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error al actualizar notificación")


@router.get("/perfil")
def obtener_perfil_usuario(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        resultado  = db.query(Usuario, Empleado, Empresa).join(
            Empleado, Empleado.usuario_id == Usuario.id
        ).join(
            Empresa, Empresa.id == Usuario.empresa_id
        ).filter(Usuario.id == usuario_id).first()

        if not resultado:
            raise HTTPException(status_code=404, detail="Perfil no encontrado")

        usuario, empleado, empresa = resultado

        permisos_rol      = db.query(Permiso.modulo).join(RolPermiso, RolPermiso.permiso_id == Permiso.id).join(UsuarioRol, UsuarioRol.rol_id == RolPermiso.rol_id).filter(UsuarioRol.usuario_id == usuario_id).all()
        permisos_directos = db.query(Permiso.modulo).join(UsuarioPermiso, UsuarioPermiso.permiso_id == Permiso.id).filter(UsuarioPermiso.usuario_id == usuario_id).all()

        modulos_permitidos = list(set([p[0].upper() for p in permisos_rol] + [p[0].upper() for p in permisos_directos]))

        meses     = ["", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                     "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
        fecha_txt = ""
        fecha_ref = empleado.fecha_ingreso or usuario.created_at
        if fecha_ref:
            fecha_txt = f"{fecha_ref.day} de {meses[fecha_ref.month]}, {fecha_ref.year}"

        return {
            "status": "success",
            "data": {
                "personal": {
                    "id":             usuario.id,
                    "nombre":         usuario.nombre,
                    "apellido":       usuario.apellido,
                    "correo":         usuario.email,
                    "telefono":       usuario.telefono or "",
                    "fotoUrl":        usuario.foto_url or "",
                    "rol":            empleado.cargo,
                    "fechaCreacion":  fecha_txt,
                    "permisos_modulo": modulos_permitidos
                },
                "empresa": {
                    "id":        empresa.id,
                    "nombre":    empresa.razon_social,
                    "ruc":       empresa.ruc,
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
        usuario    = db.query(Usuario).filter(Usuario.id == usuario_id).first()

        if not usuario:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        usuario.nombre   = datos.nombre.strip()
        usuario.apellido = datos.apellido.strip()
        usuario.telefono = datos.telefono

        if datos.fotoBase64 and datos.fotoBase64.startswith("data:image"):
            if usuario.foto_url:
                eliminar_imagen_cloudinary(usuario.foto_url)
            primer_nombre  = usuario.nombre.split(" ")[0].lower()
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