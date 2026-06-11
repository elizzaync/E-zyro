# app/services/scheduler_service.py
"""
Scheduler nocturno para recordatorios de calendario.
Corre cada día a las 8:00 AM y busca notas para HOY y MAÑANA.
Instalar dependencia: pip install apscheduler
"""
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import date, datetime, time, timedelta
from sqlalchemy.orm import Session
from app.db.database import SessionLocal
from app.models.notificacion import Notificacion
from app.services.fcm_service import enviar_push_a_usuario

scheduler = BackgroundScheduler(timezone="America/Lima")


def _enviar_recordatorios_calendario():
    """
    Tarea programada: busca notas de calendario para HOY y MAÑANA
    y dispara un push a cada usuario afectado.
    """
    db: Session = SessionLocal()
    try:
        hoy    = date.today()
        manana = hoy + timedelta(days=1)

        # Usamos datetime con hora exacta para evitar problemas de comparación
        inicio = datetime.combine(hoy,    time.min)   # 00:00:00 de hoy
        fin    = datetime.combine(manana, time.max)   # 23:59:59 de mañana

        print(f"[Scheduler] 🔔 Revisando recordatorios para {hoy} y {manana}...")

        notas = db.query(Notificacion).filter(
            Notificacion.categoria == "Nota Calendario",
            Notificacion.leido    == False,
            Notificacion.enviado  == False,
            Notificacion.fecha_envio >= inicio,
            Notificacion.fecha_envio <= fin
        ).all()

        if not notas:
            print("[Scheduler] ✅ Sin recordatorios pendientes para hoy/mañana.")
            return

        for nota in notas:
            fecha_nota = nota.fecha_envio.date() if hasattr(nota.fecha_envio, "date") else nota.fecha_envio
            dias_diff  = (fecha_nota - hoy).days

            cuando = "hoy" if dias_diff == 0 else "mañana"
            titulo  = "📅 Recordatorio de Calendario"
            mensaje = f"Tienes un evento {cuando}: {nota.mensaje}"

            print(f"[Scheduler] 📨 Enviando recordatorio al usuario {nota.usuario_id}: '{mensaje}'")
            resultado = enviar_push_a_usuario(
                usuario_id=nota.usuario_id,
                titulo=titulo,
                mensaje=mensaje,
                db=db
            )
            if resultado:
                nota.enviado = True  # evita re-envíos al día siguiente

        db.commit()

    except Exception as e:
        print(f"[Scheduler] ❌ Error en recordatorios: {e}")
        db.rollback()
    finally:
        db.close()
def _alertas_mantenimiento_equipos():
    """Equipos Intervenidos (Fase A): avisa a Admin / Jefe de Operaciones cuando
    se acerca o vence el próximo mantenimiento de un equipo. Umbrales 30/15/7/vencido.

    Idempotente por (equipo, fecha objetivo, umbral): no repite el mismo aviso.
    El cliente NO se notifica todavía — hook futuro (otra empresa_id + correo).
    """
    from app.models.equipo import Equipo
    from app.models.calibracion import Calibracion
    from app.models.usuario import Usuario
    from app.models.usuario_rol import UsuarioRol
    from app.models.rol import Rol
    from app.models.proyecto import Proyecto
    from app.models.cliente import Cliente
    import uuid as _uuid

    ROLES_DESTINO = ["Administrador", "Jefe de Operaciones"]

    def _umbral(dias: int):
        if dias < 0:
            return "vencido"
        for lim in (7, 15, 30):
            if dias <= lim:
                return str(lim)
        return None

    db: Session = SessionLocal()
    try:
        hoy = date.today()
        equipos = db.query(Equipo).filter(Equipo.requiere_mantenimiento.is_(True)).all()
        if not equipos:
            return

        # Destinatarios Admin/JefeOp por empresa (cache).
        dest_por_empresa: dict[str, list[str]] = {}

        def _destinatarios(empresa_id: str) -> list[str]:
            if empresa_id not in dest_por_empresa:
                rows = (
                    db.query(Usuario.id)
                    .join(UsuarioRol, UsuarioRol.usuario_id == Usuario.id)
                    .join(Rol, Rol.id == UsuarioRol.rol_id)
                    .filter(Usuario.empresa_id == empresa_id,
                            Usuario.activo.is_(True),
                            Rol.nombre.in_(ROLES_DESTINO))
                    .all()
                )
                dest_por_empresa[empresa_id] = [r.id for r in rows]
            return dest_por_empresa[empresa_id]

        enviados = 0
        for e in equipos:
            # Próxima fecha efectiva: calibración (certificado) > equipo.
            calib = (
                db.query(Calibracion)
                .filter(Calibracion.empresa_id == e.empresa_id,
                        Calibracion.equipo_id == str(e.id))
                .order_by(Calibracion.fecha_proxima.desc().nullslast())
                .first()
            )
            prox = (calib.fecha_proxima if calib and calib.fecha_proxima
                    else e.proxima_fecha_mantenimiento)
            if not prox:
                continue
            umbral = _umbral((prox - hoy).days)
            if not umbral:
                continue

            ref_tabla = f"eqmant:{e.id}"          # ≤ 100
            ref_id = f"{prox.isoformat()}:{umbral}"  # ≤ 36

            ya = db.query(Notificacion.id).filter(
                Notificacion.referencia_tabla == ref_tabla,
                Notificacion.referencia_id == ref_id,
            ).first()
            if ya:
                continue  # ya avisado este ciclo/umbral

            # Cliente (para el texto): directo o vía proyecto.
            cliente_nombre = ""
            cid = e.cliente_id
            if not cid and e.proyecto_id:
                p = db.query(Proyecto.cliente_id).filter(Proyecto.id == e.proyecto_id).first()
                cid = p.cliente_id if p else None
            if cid:
                c = db.query(Cliente.razon_social).filter(Cliente.id == cid).first()
                cliente_nombre = (c.razon_social if c else "") or ""

            if umbral == "vencido":
                titulo = "⚠️ Mantenimiento vencido"
                cuando = f"venció el {prox.isoformat()}"
            else:
                titulo = "🔧 Mantenimiento por vencer"
                cuando = f"vence el {prox.isoformat()} (faltan {(prox - hoy).days} días)"
            ref_cli = f" · Cliente: {cliente_nombre}" if cliente_nombre else ""
            mensaje = (f"{e.nombre}{ref_cli}: {cuando}. "
                       f"Contactar al cliente para coordinar la recontratación del mantenimiento.")

            destinatarios = _destinatarios(e.empresa_id)
            if not destinatarios:
                continue
            for uid in destinatarios:
                db.add(Notificacion(
                    id=str(_uuid.uuid4()), empresa_id=e.empresa_id, usuario_id=uid,
                    tipo="warning", categoria="mantenimiento",
                    titulo=titulo, mensaje=mensaje,
                    leido=False, enviado=False, fecha_envio=datetime.utcnow(),
                    referencia_tabla=ref_tabla, referencia_id=ref_id,
                ))
                try:
                    enviar_push_a_usuario(usuario_id=uid, titulo=titulo, mensaje=mensaje, db=db,
                                          tipo="warning", categoria="mantenimiento",
                                          referencia_tabla=ref_tabla, referencia_id=ref_id)
                except Exception:
                    pass
            enviados += 1
            # TODO (futuro): notificar a la empresa solicitante (cliente con su
            # propia empresa_id, multi-tenant) y/o enviar correo automático.

        db.commit()
        print(f"[Scheduler] 🔧 Alertas de mantenimiento emitidas: {enviados}")
    except Exception as e:
        print(f"[Scheduler] ❌ Error en alertas de mantenimiento: {e}")
        db.rollback()
    finally:
        db.close()


def _aviso_pre_almuerzo():
    """
    11:45 AM Lima: notifica a todos los empleados activos que registraron
    entrada hoy pero aún no iniciaron su almuerzo.
    Idempotente: usa (referencia_tabla='asistencia:pre_almuerzo', referencia_id='<empleado_id>:<fecha>')
    """
    from app.models.empleado import Empleado
    from app.models.registro_asistencia import RegistroAsistencia
    from app.models.usuario import Usuario
    from sqlalchemy import cast, Date as SaDate
    import uuid as _uuid

    db: Session = SessionLocal()
    try:
        hoy = date.today()

        # Empleados con entrada hoy
        con_entrada = {
            r.empleado_id
            for r in db.query(RegistroAsistencia.empleado_id).filter(
                RegistroAsistencia.tipo == "entrada",
                cast(RegistroAsistencia.fecha_hora, SaDate) == hoy,
            ).all()
        }
        if not con_entrada:
            return

        # Empleados que ya iniciaron almuerzo hoy
        ya_en_almuerzo = {
            r.empleado_id
            for r in db.query(RegistroAsistencia.empleado_id).filter(
                RegistroAsistencia.tipo == "entrada_almuerzo",
                cast(RegistroAsistencia.fecha_hora, SaDate) == hoy,
            ).all()
        }

        pendientes = con_entrada - ya_en_almuerzo
        if not pendientes:
            return

        enviados = 0
        for emp_id in pendientes:
            ref_tabla = "asistencia:pre_almuerzo"
            ref_id    = f"{emp_id}:{hoy.isoformat()}"

            # Idempotencia
            ya = db.query(Notificacion.id).filter(
                Notificacion.referencia_tabla == ref_tabla,
                Notificacion.referencia_id   == ref_id,
            ).first()
            if ya:
                continue

            empleado = db.query(Empleado).filter(Empleado.id == emp_id, Empleado.activo.is_(True)).first()
            if not empleado:
                continue
            usuario = db.query(Usuario).filter(Usuario.id == empleado.usuario_id).first()
            if not usuario:
                continue

            titulo  = "Hora del almuerzo"
            mensaje = "En 15 minutos comienza tu descanso de almuerzo. Prepárate para salir."

            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empleado.empresa_id,
                usuario_id=usuario.id, tipo="recordatorio", categoria="almuerzo",
                titulo=titulo, mensaje=mensaje, leido=False, enviado=False,
                fecha_envio=datetime.utcnow(),
                referencia_tabla=ref_tabla, referencia_id=ref_id,
            ))
            try:
                enviar_push_a_usuario(usuario_id=usuario.id, titulo=titulo,
                                      mensaje=mensaje, db=db,
                                      tipo="recordatorio", categoria="almuerzo",
                                      referencia_tabla=ref_tabla, referencia_id=ref_id)
            except Exception:
                pass
            enviados += 1

        db.commit()
        print(f"[Scheduler] Avisos pre-almuerzo enviados: {enviados}")
    except Exception as e:
        print(f"[Scheduler] Error en aviso pre-almuerzo: {e}")
        db.rollback()
    finally:
        db.close()


def _aviso_fin_almuerzo():
    """
    Corre cada 5 min: busca empleados en almuerzo activo cuyo tiempo restante
    sea <= 10 min y les avisa que deben volver.
    La duración del almuerzo viene de turno.duracion_almuerzo_minutos (default 60).
    Idempotente por (referencia_tabla='asistencia:fin_almuerzo', referencia_id=<registro.id>).
    """
    from app.models.empleado import Empleado
    from app.models.registro_asistencia import RegistroAsistencia
    from app.models.turno import Turno, TurnoEmpleado
    from app.models.usuario import Usuario
    from sqlalchemy import cast, Date as SaDate, or_
    from zoneinfo import ZoneInfo
    import uuid as _uuid

    db: Session = SessionLocal()
    try:
        ahora = datetime.now(ZoneInfo("America/Lima")).replace(tzinfo=None)
        hoy   = ahora.date()

        # Todos los registros de inicio de almuerzo de hoy
        en_almuerzo = db.query(RegistroAsistencia).filter(
            RegistroAsistencia.tipo == "entrada_almuerzo",
            cast(RegistroAsistencia.fecha_hora, SaDate) == hoy,
        ).all()
        if not en_almuerzo:
            return

        # Empleados que ya marcaron salida de almuerzo hoy
        ya_salieron = {
            r.empleado_id
            for r in db.query(RegistroAsistencia.empleado_id).filter(
                RegistroAsistencia.tipo == "salida_almuerzo",
                cast(RegistroAsistencia.fecha_hora, SaDate) == hoy,
            ).all()
        }

        enviados = 0
        for reg in en_almuerzo:
            if reg.empleado_id in ya_salieron:
                continue

            # Duración configurada en turno, o 60 min por defecto
            duracion = 60
            te = db.query(TurnoEmpleado).filter(
                TurnoEmpleado.empleado_id == reg.empleado_id,
                TurnoEmpleado.activo.is_(True),
                TurnoEmpleado.fecha_desde <= hoy,
                or_(TurnoEmpleado.fecha_hasta.is_(None), TurnoEmpleado.fecha_hasta >= hoy),
            ).first()
            if te:
                turno = db.query(Turno).filter(Turno.id == te.turno_id).first()
                if turno and turno.duracion_almuerzo_minutos:
                    duracion = turno.duracion_almuerzo_minutos

            fin_esperado = reg.fecha_hora + timedelta(minutes=duracion)
            aviso_desde  = fin_esperado - timedelta(minutes=10)

            # Solo avisar en la ventana [aviso_desde, fin_esperado]
            if not (aviso_desde <= ahora <= fin_esperado):
                continue

            # Idempotencia
            ref_tabla = "asistencia:fin_almuerzo"
            ref_id    = reg.id
            ya = db.query(Notificacion.id).filter(
                Notificacion.referencia_tabla == ref_tabla,
                Notificacion.referencia_id   == ref_id,
            ).first()
            if ya:
                continue

            empleado = db.query(Empleado).filter(Empleado.id == reg.empleado_id).first()
            if not empleado:
                continue
            usuario = db.query(Usuario).filter(Usuario.id == empleado.usuario_id).first()
            if not usuario:
                continue

            minutos_restantes = max(0, int((fin_esperado - ahora).total_seconds() // 60))
            titulo  = "Fin del descanso"
            mensaje = (
                f"Tu descanso termina en {minutos_restantes} min. "
                "Recuerda marcar tu regreso del almuerzo."
            )

            db.add(Notificacion(
                id=str(_uuid.uuid4()), empresa_id=empleado.empresa_id,
                usuario_id=usuario.id, tipo="recordatorio", categoria="almuerzo",
                titulo=titulo, mensaje=mensaje, leido=False, enviado=False,
                fecha_envio=datetime.utcnow(),
                referencia_tabla=ref_tabla, referencia_id=ref_id,
            ))
            try:
                enviar_push_a_usuario(usuario_id=usuario.id, titulo=titulo,
                                      mensaje=mensaje, db=db,
                                      tipo="recordatorio", categoria="almuerzo",
                                      referencia_tabla=ref_tabla, referencia_id=ref_id)
            except Exception:
                pass
            enviados += 1

        db.commit()
        if enviados:
            print(f"[Scheduler] Avisos fin de almuerzo enviados: {enviados}")
    except Exception as e:
        print(f"[Scheduler] Error en aviso fin de almuerzo: {e}")
        db.rollback()
    finally:
        db.close()


def iniciar_scheduler():
    """Registra las tareas y arranca el scheduler. Llamar desde main.py."""
    # Recordatorio diario a las 08:00 AM
    scheduler.add_job(
        func=_enviar_recordatorios_calendario,
        trigger=CronTrigger(hour=8, minute=0),
        id="recordatorio_calendario",
        replace_existing=True
    )
    # Alertas de mantenimiento de equipos intervenidos, 08:15 AM
    scheduler.add_job(
        func=_alertas_mantenimiento_equipos,
        trigger=CronTrigger(hour=8, minute=15),
        id="alertas_mantenimiento",
        replace_existing=True
    )
    # Aviso pre-almuerzo: 11:45 AM, empleados con entrada sin almuerzo aún
    scheduler.add_job(
        func=_aviso_pre_almuerzo,
        trigger=CronTrigger(hour=11, minute=45),
        id="aviso_pre_almuerzo",
        replace_existing=True
    )
    # Aviso fin de almuerzo: cada 5 min, 10 min antes de que termine el descanso
    scheduler.add_job(
        func=_aviso_fin_almuerzo,
        trigger=CronTrigger(minute="*/5"),
        id="aviso_fin_almuerzo",
        replace_existing=True
    )
    scheduler.start()
    print("⏰ Scheduler iniciado → recordatorios 08:00 + alertas mantenimiento 08:15 "
          "+ aviso pre-almuerzo 11:45 + aviso fin almuerzo cada 5 min")
def detener_scheduler():
    """Detiene el scheduler al cerrar la app."""
    if scheduler.running:
        scheduler.shutdown()
        print("⏰ Scheduler detenido.")