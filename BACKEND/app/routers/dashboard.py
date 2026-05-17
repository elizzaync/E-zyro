# app/routers/dashboard.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import asc, desc, extract, func, case, or_, cast, Date
from typing import Dict, Any, Optional
from datetime import date, datetime, timedelta
from collections import defaultdict
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
from app.models.auditoria import Auditoria
from app.models.empleado_habilidad import EmpleadoHabilidad
from app.models.habilidad import Habilidad
from app.models.categoria_habilidad import CategoriaHabilidad
from app.models.registro_asistencia import RegistroAsistencia
from app.models.solicitud_laboral import SolicitudLaboral
from app.models.sesion_usuario import SesionUsuario
from app.models.contrato import Contrato
from app.models.documento_laboral import DocumentoLaboral

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
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/resumen")
def obtener_resumen_kpis(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        empresa_id = current_user.get("empresa_id")
        usuario_id = current_user.get("id")
        usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        # ── Servicios completados ──────────────────────────────────────────────
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

        servicios_completados = int(kpis.completados or 0) if kpis else 0

        # ── Asistencias del mes ────────────────────────────────────────────────
        hoy = date.today()
        primer_dia_mes = date(hoy.year, hoy.month, 1)
        ultimo_dia_mes = date(hoy.year, hoy.month, calendar.monthrange(hoy.year, hoy.month)[1])

        asistencias_mes = 0
        if empleado:
            asistencias_mes = db.query(RegistroAsistencia).filter(
                RegistroAsistencia.empleado_id == empleado.id,
                RegistroAsistencia.empresa_id == empresa_id,
                RegistroAsistencia.estado.in_(['APROBADO', 'aprobado']),
                cast(RegistroAsistencia.fecha_hora, Date) >= primer_dia_mes,
                cast(RegistroAsistencia.fecha_hora, Date) <= ultimo_dia_mes
            ).count()

        # ── Solicitudes pendientes ─────────────────────────────────────────────
        solicitudes_pendientes = 0
        if empleado:
            solicitudes_pendientes = db.query(SolicitudLaboral).filter(
                SolicitudLaboral.empleado_id == empleado.id,
                SolicitudLaboral.empresa_id == empresa_id,
                SolicitudLaboral.estado.in_(['pendiente', 'PENDIENTE'])
            ).count()

        return {"status": "success", "data": {
            "activos": int(kpis.activos or 0) if kpis else 0,
            "pendientes": int(kpis.pendientes or 0) if kpis else 0,
            "completados": servicios_completados,
            "asistencias_mes": asistencias_mes,
            "solicitudes_pendientes": solicitudes_pendientes,
            "usuario": {
                "nombre": usuario.nombre if usuario else "",
                "apellido": usuario.apellido if usuario else "",
                "email": usuario.email if usuario else "",
                "telefono": usuario.telefono if usuario else "",
                "foto_url": usuario.foto_url if usuario else ""
            }
        }}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Error interno del servidor")


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
        raise HTTPException(status_code=500, detail="Error interno del servidor")


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

        # ── Push inmediato para confirmar que la nota fue guardada ───────────
        fecha_nota = fecha_obj.date()
        hoy        = date.today()
        dias_diff  = (fecha_nota - hoy).days

        if dias_diff == 0:
            cuando = "hoy"
        elif dias_diff == 1:
            cuando = "mañana"
        elif dias_diff > 1:
            cuando = f"el {fecha_nota.strftime('%d/%m/%Y')}"
        else:
            cuando = None   # fecha pasada, no notificar

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
        raise HTTPException(status_code=500, detail="Error interno del servidor")


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
                    fecha_obj = n.fecha_envio.date() if hasattr(n.fecha_envio, 'date') else datetime.strptime(str(n.fecha_envio)[:10], "%Y-%m-%d").date()
                    dias_diff = (fecha_obj - hoy).days

                    # Mostramos notas de hoy hasta los próximos 7 días
                    if 0 <= dias_diff <= 7:
                        if dias_diff == 0:
                            tiempo_str = "Hoy"
                        elif dias_diff == 1:
                            tiempo_str = "Mañana"
                        else:
                            tiempo_str = f"En {dias_diff} días"
                        data.append({
                            "id":      n.id,
                            "titulo":  "📅 Evento Próximo",
                            "mensaje": n.mensaje,
                            "tiempo":  tiempo_str,
                            "tipo":    n.tipo
                        })
                except Exception:
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
    except Exception:
        raise HTTPException(status_code=500, detail="Error al cargar notificaciones")


class AsignacionMiembro(BaseModel):
    proyecto_id: str
    empleado_id: str
    rol_proyecto: Optional[str] = "Técnico"


@router.get("/calendario/servicio/{fecha}")
def obtener_detalle_servicio_dia(fecha: str, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """Devuelve los proyectos asignados al usuario para una fecha dada, con equipo y jefe."""
    try:
        usuario_id = current_user.get("id")
        empresa_id = current_user.get("empresa_id")
        fecha_obj  = datetime.strptime(fecha, "%Y-%m-%d").date()

        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        filtros = [
            Proyecto.empresa_id == empresa_id,
            Proyecto.fecha_inicio == fecha_obj,
            Proyecto.estado.in_(["En_Proceso", "Pendiente", "Completado"])
        ]
        if empleado:
            filtros.append(or_(
                Proyecto.jefe_operaciones_id == empleado.id,
                Proyecto.id.in_(
                    db.query(ProyectoMiembro.proyecto_id).filter(
                        ProyectoMiembro.empleado_id == empleado.id,
                        ProyectoMiembro.activo == True
                    )
                )
            ))

        proyectos = db.query(Proyecto, Cliente, CatalogoServicio).join(
            Cliente, Proyecto.cliente_id == Cliente.id
        ).join(
            ProyectoServicio, Proyecto.id == ProyectoServicio.proyecto_id
        ).join(
            CatalogoServicio, ProyectoServicio.catalogo_servicio_id == CatalogoServicio.id
        ).filter(*filtros).all()

        if not proyectos:
            return {"status": "success", "data": []}

        resultado = []
        for p, c, cat in proyectos:
            # Jefe de operaciones
            jefe_data = None
            if p.jefe_operaciones_id:
                jefe_emp = db.query(Empleado).filter(Empleado.id == p.jefe_operaciones_id).first()
                if jefe_emp:
                    jefe_usr = db.query(Usuario).filter(Usuario.id == jefe_emp.usuario_id).first()
                    jefe_data = {
                        "nombre": f"{jefe_usr.nombre} {jefe_usr.apellido}" if jefe_usr else "—",
                        "cargo": jefe_emp.cargo
                    }

            # Equipo de trabajo
            equipo_rows = db.query(ProyectoMiembro, Empleado, Usuario).join(
                Empleado, ProyectoMiembro.empleado_id == Empleado.id
            ).join(
                Usuario, Empleado.usuario_id == Usuario.id
            ).filter(
                ProyectoMiembro.proyecto_id == p.id,
                ProyectoMiembro.activo == True
            ).all()

            equipo = [
                {
                    "nombre": f"{u.nombre} {u.apellido}",
                    "cargo": e.cargo,
                    "rol_proyecto": m.rol_proyecto or "Técnico"
                }
                for m, e, u in equipo_rows
            ]

            estado_map = {
                "En_Proceso": "En Proceso", "Pendiente": "Pendiente", "Completado": "Completado"
            }
            resultado.append({
                "id":             p.id,
                "nombre":         p.nombre_proyecto,
                "orden_trabajo":  p.orden_trabajo,
                "estado":         estado_map.get(p.estado, p.estado),
                "servicio":       cat.nombre,
                "cliente":        c.razon_social,
                "fecha":          fecha,
                "jefe_operaciones": jefe_data,
                "equipo":         equipo
            })

        return {"status": "success", "data": resultado}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.post("/proyectos/asignar-tecnico")
def asignar_tecnico_grupo(datos: AsignacionMiembro, current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """Asigna un técnico a un proyecto y le envía una notificación push."""
    try:
        proyecto = db.query(Proyecto).filter(Proyecto.id == datos.proyecto_id).first()
        if not proyecto:
            raise HTTPException(status_code=404, detail="Proyecto no encontrado")

        empleado = db.query(Empleado).filter(Empleado.id == datos.empleado_id).first()
        if not empleado:
            raise HTTPException(status_code=404, detail="Técnico no encontrado")

        # Verificar que no esté ya asignado
        existente = db.query(ProyectoMiembro).filter(
            ProyectoMiembro.proyecto_id == datos.proyecto_id,
            ProyectoMiembro.empleado_id == datos.empleado_id
        ).first()

        if existente:
            if not existente.activo:
                existente.activo = True
                db.commit()
            return {"status": "success", "mensaje": "El técnico ya estaba en el grupo"}

        nuevo_miembro = ProyectoMiembro(
            proyecto_id=datos.proyecto_id,
            empleado_id=datos.empleado_id,
            rol_proyecto=datos.rol_proyecto,
            activo=True
        )
        db.add(nuevo_miembro)
        db.commit()

        # Notificar al técnico por push
        if empleado.usuario_id:
            usuario_tec = db.query(Usuario).filter(Usuario.id == empleado.usuario_id).first()
            nombre_tecnico = f"{usuario_tec.nombre} {usuario_tec.apellido}" if usuario_tec else "Técnico"
            cliente = db.query(Cliente).filter(Cliente.id == proyecto.cliente_id).first()
            nombre_cliente = cliente.razon_social if cliente else "cliente"
            fecha_str = proyecto.fecha_inicio.strftime("%d/%m/%Y") if proyecto.fecha_inicio else "por definir"

            notificar_asignacion_servicio(
                usuario_id_tecnico=empleado.usuario_id,
                nombre_tecnico=nombre_tecnico,
                nombre_servicio=proyecto.nombre_proyecto or "Servicio",
                nombre_cliente=nombre_cliente,
                fecha_servicio=fecha_str,
                db=db
            )

        return {"status": "success", "mensaje": f"Técnico {empleado.nombre} asignado al proyecto"}
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail="Error interno del servidor")


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
                    "area":           empleado.area or "",
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


# Tablas y acciones que nunca se exponen al usuario por seguridad
_TABLAS_SENSIBLES = frozenset({
    'recuperacion_password', 'sesion_usuario', 'sesion_cliente',
    'dispositivo_push', 'firma_digital', 'historial_firma', 'usuario'
})
_ACCIONES_PRIVADAS = frozenset({'LOGIN', 'LOGOUT'})


@router.get("/perfil/capacitaciones")
def obtener_capacitaciones(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """Retorna las habilidades/capacitaciones registradas para el empleado autenticado."""
    try:
        usuario_id = current_user.get("id")
        empleado   = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        if not empleado:
            return {"status": "success", "data": []}

        rows = (
            db.query(EmpleadoHabilidad, Habilidad, CategoriaHabilidad)
            .join(Habilidad, EmpleadoHabilidad.habilidad_id == Habilidad.id)
            .join(CategoriaHabilidad, Habilidad.categoria_id == CategoriaHabilidad.id)
            .filter(EmpleadoHabilidad.empleado_id == empleado.id)
            .order_by(CategoriaHabilidad.nombre, Habilidad.nombre)
            .all()
        )

        nivel_es = {
            'basico': 'Básico', 'intermedio': 'Intermedio',
            'avanzado': 'Avanzado', 'experto': 'Experto'
        }

        data = [
            {
                "id":         eh.id,
                "nombre":     h.nombre,
                "categoria":  c.nombre,
                "nivel":      nivel_es.get(eh.nivel, eh.nivel),
                "nivel_raw":  eh.nivel,
                "verificado": eh.verificado
            }
            for eh, h, c in rows
        ]

        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar capacitaciones")


@router.get("/perfil/actividad")
def obtener_actividad_reciente(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """
    Retorna los últimos registros de auditoría del usuario autenticado.
    Se omiten explícitamente eventos de sesión, contraseñas y datos sensibles.
    """
    try:
        usuario_id = current_user.get("id")

        registros = (
            db.query(Auditoria)
            .filter(
                Auditoria.usuario_id == usuario_id,
                ~Auditoria.tabla_afectada.in_(_TABLAS_SENSIBLES),
                ~Auditoria.accion.in_(_ACCIONES_PRIVADAS)
            )
            .order_by(desc(Auditoria.fecha))
            .limit(15)
            .all()
        )

        accion_label = {
            'INSERT':          'creado',
            'UPDATE':          'actualizado',
            'DELETE':          'eliminado',
            'EXPORT':          'exportado',
            'ACCESO_DENEGADO': 'acceso denegado'
        }

        data = []
        for r in registros:
            desc_safe = r.descripcion or f"Registro {accion_label.get(r.accion, r.accion)} en {r.modulo or r.tabla_afectada}"
            data.append({
                "id":          r.id,
                "accion":      r.accion,
                "modulo":      r.modulo or r.tabla_afectada,
                "descripcion": desc_safe,
                "fecha":       r.fecha.isoformat() if r.fecha else None
            })

        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error al cargar actividad reciente")


@router.get("/perfil/estadisticas")
def obtener_estadisticas_perfil(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """
    Retorna 4 métricas personales del empleado autenticado:
    - Servicios completados (proyecto_servicio donde es responsable)
    - Asistencias del mes (días con entrada Y salida en el mes actual)
    - Solicitudes laborales pendientes
    - Tiempo promedio de sesión (de sesion_usuario)
    """
    try:
        usuario_id = current_user.get("id")
        empleado   = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        hoy        = date.today()

        if not empleado:
            return {"status": "success", "data": {
                "servicios_completados": 0,
                "asistencias_mes": 0,
                "solicitudes_pendientes": 0,
                "tiempo_promedio": "—"
            }}

        # 1. Servicios completados donde el empleado es responsable
        servicios_completados = db.query(func.count(ProyectoServicio.id)).filter(
            ProyectoServicio.responsable_id == empleado.id,
            ProyectoServicio.estado         == 'Completado'
        ).scalar() or 0

        # 2. Asistencias del mes: días donde existe tanto 'entrada' como 'salida'
        fechas_entrada = {
            r[0] for r in db.query(cast(RegistroAsistencia.fecha_hora, Date))
            .filter(
                RegistroAsistencia.empleado_id == empleado.id,
                RegistroAsistencia.tipo        == 'entrada',
                extract('month', RegistroAsistencia.fecha_hora) == hoy.month,
                extract('year',  RegistroAsistencia.fecha_hora) == hoy.year
            ).distinct().all()
        }
        fechas_salida = {
            r[0] for r in db.query(cast(RegistroAsistencia.fecha_hora, Date))
            .filter(
                RegistroAsistencia.empleado_id == empleado.id,
                RegistroAsistencia.tipo        == 'salida',
                extract('month', RegistroAsistencia.fecha_hora) == hoy.month,
                extract('year',  RegistroAsistencia.fecha_hora) == hoy.year
            ).distinct().all()
        }
        asistencias_mes = len(fechas_entrada & fechas_salida)

        # 3. Solicitudes laborales pendientes del empleado
        solicitudes_pendientes = db.query(func.count(SolicitudLaboral.id)).filter(
            SolicitudLaboral.empleado_id == empleado.id,
            SolicitudLaboral.estado      == 'pendiente'
        ).scalar() or 0

        # 4. Tiempo promedio de sesión (segundos → formato legible)
        avg_seg = db.query(
            func.avg(
                func.extract(
                    'epoch',
                    func.coalesce(SesionUsuario.fecha_cierre, func.now()) - SesionUsuario.created_at
                )
            )
        ).filter(SesionUsuario.usuario_id == usuario_id).scalar()

        avg_mins = round((avg_seg or 0) / 60)
        if avg_mins < 1:
            tiempo_promedio = "< 1m"
        elif avg_mins < 60:
            tiempo_promedio = f"{avg_mins}m"
        else:
            h = avg_mins // 60
            m = avg_mins % 60
            tiempo_promedio = f"{h}h {m}m" if m else f"{h}h"

        return {
            "status": "success",
            "data": {
                "servicios_completados": int(servicios_completados),
                "asistencias_mes":       int(asistencias_mes),
                "solicitudes_pendientes": int(solicitudes_pendientes),
                "tiempo_promedio":        tiempo_promedio
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/perfil/asistencia")
def obtener_asistencia_perfil(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    """
    Retorna los registros de asistencia del empleado autenticado para los últimos 30 días,
    agrupados por día con entrada, salida, horas trabajadas, localización y estado.
    """
    try:
        usuario_id = current_user.get("id")
        empleado   = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()

        if not empleado:
            return {"status": "success", "data": {
                "registros": [],
                "resumen": {"dias_asistidos": 0, "promedio_horas": "—"}
            }}

        hoy    = date.today()
        inicio = datetime.combine(hoy - timedelta(days=29), datetime.min.time())

        registros_db = db.query(RegistroAsistencia).filter(
            RegistroAsistencia.empleado_id == empleado.id,
            RegistroAsistencia.fecha_hora  >= inicio
        ).order_by(RegistroAsistencia.fecha_hora).all()

        por_dia: dict = defaultdict(lambda: {"entradas": [], "salidas": [], "observacion": ""})
        for r in registros_db:
            fecha_key = r.fecha_hora.date().isoformat()
            if r.tipo == "entrada":
                por_dia[fecha_key]["entradas"].append(r.fecha_hora)
            elif r.tipo == "salida":
                por_dia[fecha_key]["salidas"].append(r.fecha_hora)
            if r.observacion:
                por_dia[fecha_key]["observacion"] = r.observacion

        dias_semana_es = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
        dias_corto_es  = ["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"]
        meses_es       = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun",
                          "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]

        resultado = []
        for fecha_str in sorted(por_dia.keys(), reverse=True):
            d       = por_dia[fecha_str]
            fecha_o = date.fromisoformat(fecha_str)

            entrada_dt = min(d["entradas"]) if d["entradas"] else None
            salida_dt  = max(d["salidas"])  if d["salidas"]  else None

            if entrada_dt and salida_dt:
                segs      = (salida_dt - entrada_dt).total_seconds()
                mins_tot  = int(segs // 60)
                h, m      = divmod(mins_tot, 60)
                horas_txt = f"{h}h {m:02d}m" if m else f"{h}h"
                estado    = "completo"
            elif entrada_dt:
                horas_txt = "En curso"
                estado    = "en_curso"
            else:
                horas_txt = "—"
                estado    = "incompleto"

            resultado.append({
                "dia":              f"{fecha_o.day:02d}",
                "mes":              meses_es[fecha_o.month],
                "anio":             str(fecha_o.year),
                "dia_semana":       dias_semana_es[fecha_o.weekday()],
                "dia_corto":        dias_corto_es[fecha_o.weekday()],
                "entrada":          entrada_dt.strftime("%H:%M") if entrada_dt else None,
                "salida":           salida_dt.strftime("%H:%M")  if salida_dt  else None,
                "horas_trabajadas": horas_txt,
                "estado":           estado,
                "localizacion":     d["observacion"] or "Sede Principal"
            })

        # Resumen: solo días del mes actual con entrada Y salida
        dias_completos_mes = [
            k for k, v in por_dia.items()
            if date.fromisoformat(k).month == hoy.month
            and date.fromisoformat(k).year  == hoy.year
            and v["entradas"] and v["salidas"]
        ]
        total_secs = sum(
            (max(por_dia[k]["salidas"]) - min(por_dia[k]["entradas"])).total_seconds()
            for k in dias_completos_mes
        )
        if dias_completos_mes:
            avg_mins = round(total_secs / len(dias_completos_mes) / 60)
            h, m     = divmod(avg_mins, 60)
            promedio_txt = f"{h}h {m:02d}m" if m else f"{h}h"
        else:
            promedio_txt = "—"

        return {
            "status": "success",
            "data": {
                "registros": resultado,
                "resumen": {
                    "dias_asistidos": len(dias_completos_mes),
                    "promedio_horas": promedio_txt
                }
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/perfil/contratos")
def obtener_contratos(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": []}

        contratos = db.query(Contrato).filter(
            Contrato.empleado_id == empleado.id
        ).order_by(desc(Contrato.created_at)).all()

        meses = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
        tipo_label = {
            'planilla': 'Planilla', 'recibo_honorarios': 'Recibo por Honorarios',
            'practicante': 'Practicante', 'contrato': 'Tiempo Definido',
        }
        estado_label = {
            'vigente': 'Vigente', 'vencido': 'Vencido',
            'rescindido': 'Rescindido', 'renovado': 'Renovado',
        }

        data = []
        for c in contratos:
            fi = c.fecha_inicio
            fecha_fmt = f"{fi.day} {meses[fi.month]}, {fi.year}" if fi else "—"
            ff = c.fecha_fin
            fecha_fin_fmt = f"{ff.day} {meses[ff.month]}, {ff.year}" if ff else None
            data.append({
                "id":          str(c.id),
                "titulo":      f"Contrato {tipo_label.get(c.tipo, c.tipo.replace('_', ' ').title())}",
                "tipo":        c.tipo,
                "estado":      estado_label.get(c.estado, c.estado.title()),
                "fecha_inicio": fecha_fmt,
                "fecha_fin":   fecha_fin_fmt,
                "url":         c.documento_url,
            })
        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/perfil/boletas")
def obtener_boletas(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": []}

        documentos = db.query(DocumentoLaboral).filter(
            DocumentoLaboral.empleado_id == empleado.id
        ).order_by(desc(DocumentoLaboral.fecha_emision)).all()

        meses = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]

        data = []
        for d in documentos:
            fe = d.fecha_emision
            fecha_fmt = f"{fe.day} {meses[fe.month]}, {fe.year}" if fe else "—"
            data.append({
                "id":    str(d.id),
                "titulo": d.nombre,
                "tipo":  d.tipo,
                "fecha": fecha_fmt,
                "url":   d.url_archivo,
            })
        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


@router.get("/perfil/permisos")
def obtener_permisos_laborales(current_user: dict = Depends(verificar_token), db: Session = Depends(get_db)):
    try:
        usuario_id = current_user.get("id")
        empleado = db.query(Empleado).filter(Empleado.usuario_id == usuario_id).first()
        if not empleado:
            return {"status": "success", "data": []}

        solicitudes = db.query(SolicitudLaboral).filter(
            SolicitudLaboral.empleado_id == empleado.id
        ).order_by(desc(SolicitudLaboral.created_at)).all()

        meses = ["", "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
        tipo_label = {
            'justificacion_falta':    'Justificación de Falta',
            'permiso':                'Permiso',
            'vacaciones':             'Vacaciones',
            'adelanto':               'Adelanto',
            'otro':                   'Otro',
            'permiso_personal':       'Permiso Personal',
            'comision_trabajo':       'Comisión de Trabajo',
            'cita_essalud':           'Cita Essalud / Clínica',
            'permanencia_capacitacion': 'Permanencia Capacitación',
            'permanencia_extra':      'Permanencia Extra (H)',
            'recuperacion':           'Recuperación (H)',
            'dias_libres':            'Día(s) Libre(s)',
            'transferencia':          'Transferencia',
            'otros':                  'Otros',
        }
        estado_label = {
            'pendiente': 'Pendiente', 'aprobada': 'Aprobada',
            'rechazada': 'Rechazada', 'anulada': 'Anulada',
        }

        data = []
        for s in solicitudes:
            fecha_ref = s.fecha_inicio or (s.created_at.date() if s.created_at else None)
            if hasattr(fecha_ref, 'date'):
                fecha_ref = fecha_ref.date()
            fecha_fmt = f"{fecha_ref.day} {meses[fecha_ref.month]}, {fecha_ref.year}" if fecha_ref else "—"

            titulo = tipo_label.get(s.tipo, s.tipo.replace('_', ' ').title())
            motivo = s.descripcion or ""
            if '|' in motivo:
                motivo = motivo.split('|')[1].strip() if len(motivo.split('|')) > 1 else ''
            if motivo:
                titulo += f" — {motivo[:60]}"

            fi = s.fecha_inicio
            ff = s.fecha_fin
            data.append({
                "id":           str(s.id),
                "titulo":       titulo,
                "tipo":         s.tipo,
                "estado":       estado_label.get(s.estado, s.estado.title()),
                "fecha":        fecha_fmt,
                "fecha_inicio": f"{fi.day} {meses[fi.month]}, {fi.year}" if fi else None,
                "fecha_fin":    f"{ff.day} {meses[ff.month]}, {ff.year}" if ff else None,
                "url":          getattr(s, 'url_pdf', None),
            })
        return {"status": "success", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error interno del servidor")


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