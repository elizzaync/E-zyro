# app/services/scheduler_service.py
"""
Scheduler nocturno para recordatorios de calendario.
Corre cada día a las 8:00 AM y busca notas para HOY y MAÑANA.
Instalar dependencia: pip install apscheduler
"""
import uuid as _uuid
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import date, datetime, time, timedelta
from sqlalchemy.orm import Session
from app.db.database import SessionLocal
from app.models.notificacion import Notificacion
from app.services.fcm_service import enviar_push_a_usuario
from app.core.permisos import usuarios_con_permiso


# ── Días laborables ──────────────────────────────────────────────────────────
def _es_dia_laborable(d: date) -> bool:
    """Días de trabajo: lunes a sábado (excluye domingo).
    weekday(): lun=0 … sáb=5 … dom=6. Misma convención que los reportes."""
    return d.weekday() < 6


# ── Helpers compartidos ──────────────────────────────────────────────────────
def _usuarios_por_rol(db, empresa_id, roles):
    """IDs de usuarios activos de la empresa que tengan alguno de los roles."""
    from app.models.usuario import Usuario
    from app.models.usuario_rol import UsuarioRol
    from app.models.rol import Rol
    rows = (
        db.query(Usuario.id)
        .join(UsuarioRol, UsuarioRol.usuario_id == Usuario.id)
        .join(Rol, Rol.id == UsuarioRol.rol_id)
        .filter(Usuario.empresa_id == empresa_id,
                Usuario.activo.is_(True),
                Rol.nombre.in_(roles))
        .distinct()
        .all()
    )
    return [r.id for r in rows]


def _emitir(db, *, empresa_id, usuarios, tipo, categoria, titulo, mensaje, ref_key):
    """Crea la notificación + push para cada usuario. Idempotente por `ref_key`
    (clave completa en referencia_tabla; referencia_id es uuid y queda NULL).
    Devuelve True si emitió (no existía antes)."""
    if not usuarios:
        return False
    ya = db.query(Notificacion.id).filter(
        Notificacion.referencia_tabla == ref_key,
    ).first()
    if ya:
        return False
    for uid in usuarios:
        db.add(Notificacion(
            id=str(_uuid.uuid4()), empresa_id=empresa_id, usuario_id=uid,
            tipo=tipo, categoria=categoria, titulo=titulo, mensaje=mensaje,
            leido=False, enviado=False, fecha_envio=datetime.utcnow(),
            referencia_tabla=ref_key, referencia_id=None,
        ))
        try:
            enviar_push_a_usuario(usuario_id=uid, titulo=titulo, mensaje=mensaje,
                                  db=db, tipo=tipo, categoria=categoria,
                                  referencia_tabla=ref_key)
        except Exception:
            pass
    return True

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

            # Clave de idempotencia COMPLETA en referencia_tabla (varchar 100).
            # referencia_id es uuid en BD: no admite strings compuestos.
            ref_tabla = f"eqmant:{e.id}:{prox.isoformat()}:{umbral}"  # ≤ 100

            ya = db.query(Notificacion.id).filter(
                Notificacion.referencia_tabla == ref_tabla,
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
                    referencia_tabla=ref_tabla, referencia_id=None,
                ))
                try:
                    enviar_push_a_usuario(usuario_id=uid, titulo=titulo, mensaje=mensaje, db=db,
                                          tipo="warning", categoria="mantenimiento",
                                          referencia_tabla=ref_tabla)
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
        if not _es_dia_laborable(hoy):
            return  # domingo: no se notifica asistencia

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
        if not _es_dia_laborable(hoy):
            return  # domingo: no se notifica asistencia

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


def _alertas_vencimientos():
    """Diario: contratos, calibraciones, CXP y CXC próximos a vencer / vencidos.
    Destinatarios: Administradores de la empresa. Idempotente por umbral."""
    from app.models.empleado import Empleado
    from app.models.usuario import Usuario
    from app.models.calibracion import Calibracion
    from app.models.cuentas_por_pagar import FacturaProveedor
    from app.models.cuentas_por_cobrar import FacturaCliente
    from app.models.equipo import Equipo
    from app.models.proveedor import Proveedor
    from app.models.cliente import Cliente
    from app.models.documento_sst import DocumentoSst

    def _umbral(dias: int):
        if dias < 0:
            return "vencido"
        for lim in (3, 7, 15, 30):
            if dias <= lim:
                return str(lim)
        return None

    db: Session = SessionLocal()
    try:
        hoy = date.today()
        dest_cache: dict[tuple, list[str]] = {}

        def dest(emp_id, modulo, accion):
            """Destinatarios = quienes tienen el permiso (modulo.accion) + admins."""
            key = (emp_id, modulo, accion)
            if key not in dest_cache:
                dest_cache[key] = usuarios_con_permiso(db, emp_id, modulo, accion)
            return dest_cache[key]

        emitidos = 0

        # 1) Contratos por vencer (usa dias_aviso_vencimiento del propio empleado)
        empleados = db.query(Empleado).filter(
            Empleado.activo.is_(True),
            Empleado.fecha_fin_contrato.isnot(None),
        ).all()
        for emp in empleados:
            dias = (emp.fecha_fin_contrato - hoy).days
            aviso = emp.dias_aviso_vencimiento or 7
            if dias > aviso:
                continue
            u = db.query(Usuario.nombre, Usuario.apellido).filter(
                Usuario.id == emp.usuario_id).first()
            nombre = (f"{u.nombre} {u.apellido}".strip() if u else "Empleado")
            if dias < 0:
                titulo, cuando, umbral = ("Contrato vencido",
                    f"venció el {emp.fecha_fin_contrato.isoformat()}", "vencido")
            else:
                titulo, cuando, umbral = ("Contrato por vencer",
                    f"vence el {emp.fecha_fin_contrato.isoformat()} (faltan {dias} días)",
                    "aviso")
            ref_key = f"contrato:{emp.id}:{emp.fecha_fin_contrato.isoformat()}:{umbral}"
            if _emitir(db, empresa_id=emp.empresa_id,
                       usuarios=dest(emp.empresa_id, "empleados", "ver"),
                       tipo="warning", categoria="rrhh", titulo=titulo,
                       mensaje=f"El contrato de {nombre} {cuando}.", ref_key=ref_key):
                emitidos += 1

        # 2) Calibraciones por vencer
        for c in db.query(Calibracion).filter(Calibracion.fecha_proxima.isnot(None)).all():
            umbral = _umbral((c.fecha_proxima - hoy).days)
            if not umbral:
                continue
            eq = db.query(Equipo.nombre).filter(Equipo.id == c.equipo_id).first()
            eqn = eq.nombre if eq else "Equipo"
            if umbral == "vencido":
                titulo, cuando = "Calibración vencida", f"venció el {c.fecha_proxima.isoformat()}"
            else:
                titulo, cuando = ("Calibración por vencer",
                    f"vence el {c.fecha_proxima.isoformat()} (faltan {(c.fecha_proxima - hoy).days} días)")
            ref_key = f"calib:{c.id}:{c.fecha_proxima.isoformat()}:{umbral}"
            if _emitir(db, empresa_id=c.empresa_id,
                       usuarios=dest(c.empresa_id, "calibracion", "ver"),
                       tipo="warning", categoria="calibracion", titulo=titulo,
                       mensaje=f"Calibración de {eqn}: {cuando}.", ref_key=ref_key):
                emitidos += 1

        # 3) Cuentas por pagar (facturas de proveedor pendientes)
        for f in db.query(FacturaProveedor).filter(
            FacturaProveedor.estado.in_(["pendiente", "pagada_parcial"]),
        ).all():
            if not f.fecha_vencimiento:
                continue
            umbral = _umbral((f.fecha_vencimiento - hoy).days)
            if not umbral:
                continue
            prov = db.query(Proveedor.razon_social).filter(Proveedor.id == f.proveedor_id).first()
            provn = (prov.razon_social if prov else "") or "proveedor"
            if umbral == "vencido":
                titulo, cuando = "Cuenta por pagar vencida", f"venció el {f.fecha_vencimiento.isoformat()}"
            else:
                titulo, cuando = ("Cuenta por pagar próxima",
                    f"vence el {f.fecha_vencimiento.isoformat()} (faltan {(f.fecha_vencimiento - hoy).days} días)")
            ref_key = f"cxp:{f.id}:{f.fecha_vencimiento.isoformat()}:{umbral}"
            if _emitir(db, empresa_id=f.empresa_id,
                       usuarios=dest(f.empresa_id, "cxp", "ver"),
                       tipo="warning", categoria="finanzas", titulo=titulo,
                       mensaje=f"Factura {f.numero_documento} de {provn} por S/ {f.total}: {cuando}.",
                       ref_key=ref_key):
                emitidos += 1

        # 4) Cuentas por cobrar (comprobantes de cliente pendientes) — próximas ≤7d y vencidas
        for f in db.query(FacturaCliente).filter(
            FacturaCliente.estado.in_(["pendiente", "cobrada_parcial"]),
            FacturaCliente.fecha_vencimiento.isnot(None),
        ).all():
            dias = (f.fecha_vencimiento - hoy).days
            if dias > 7:
                continue
            cli = db.query(Cliente.razon_social).filter(Cliente.id == f.cliente_id).first()
            clin = (cli.razon_social if cli else "") or "cliente"
            if dias < 0:
                titulo, cuando, umbral = ("Cuenta por cobrar vencida",
                    f"venció el {f.fecha_vencimiento.isoformat()}", "vencido")
            else:
                titulo, cuando, umbral = ("Cuenta por cobrar próxima",
                    f"vence el {f.fecha_vencimiento.isoformat()} (faltan {dias} días)", "aviso")
            ref_key = f"cxc:{f.id}:{f.fecha_vencimiento.isoformat()}:{umbral}"
            if _emitir(db, empresa_id=f.empresa_id,
                       usuarios=dest(f.empresa_id, "cxc", "ver"),
                       tipo="warning", categoria="finanzas", titulo=titulo,
                       mensaje=f"Comprobante {f.numero_documento} de {clin} por S/ {f.total}: {cuando}.",
                       ref_key=ref_key):
                emitidos += 1

        # 5) Documentos SST (homologaciones, ATS, PETAR) por vencer / vencidos
        etiquetas = {"homologacion": "Homologación", "ats": "ATS", "petar": "PETAR"}
        for d in db.query(DocumentoSst).filter(
            DocumentoSst.fecha_vencimiento.isnot(None),
        ).all():
            umbral = _umbral((d.fecha_vencimiento - hoy).days)
            if not umbral:
                continue
            etiqueta = etiquetas.get(d.tipo, "Documento")
            if umbral == "vencido":
                titulo = "Documento SST vencido"
                cuando = f"venció el {d.fecha_vencimiento.isoformat()}"
            else:
                titulo = "Documento SST por vencer"
                cuando = (f"vence el {d.fecha_vencimiento.isoformat()} "
                          f"(faltan {(d.fecha_vencimiento - hoy).days} días)")
            ref_key = f"docsst:{d.id}:{d.fecha_vencimiento.isoformat()}:{umbral}"
            if _emitir(db, empresa_id=d.empresa_id,
                       usuarios=dest(d.empresa_id, "documentos_sst", "ver"),
                       tipo="warning", categoria="documentos", titulo=titulo,
                       mensaje=f"{etiqueta} «{d.titulo}»: {cuando}.", ref_key=ref_key):
                emitidos += 1

        db.commit()
        print(f"[Scheduler] Alertas de vencimientos emitidas: {emitidos}")
    except Exception as e:
        print(f"[Scheduler] Error en alertas de vencimientos: {e}")
        db.rollback()
    finally:
        db.close()


def _alertas_prestamos_sin_devolver():
    """Diario: préstamos en estado 'entregado' que llevan ≥3 días sin devolverse.
    Avisa a Logística/Admin y al técnico solicitante. Umbrales 3/7/15 días."""
    from app.models.prestamo import Prestamo
    from app.models.empleado import Empleado
    from app.models.proyecto_servicio import ProyectoServicio

    def _bucket(dias_fuera: int):
        if dias_fuera >= 15:
            return "15"
        if dias_fuera >= 7:
            return "7"
        if dias_fuera >= 3:
            return "3"
        return None

    db: Session = SessionLocal()
    try:
        ahora = datetime.utcnow()
        prestamos = db.query(Prestamo).filter(
            Prestamo.estado == "entregado",
            Prestamo.fecha_entrega.isnot(None),
        ).all()
        emitidos = 0
        for p in prestamos:
            dias_fuera = (ahora - p.fecha_entrega).days
            umbral = _bucket(dias_fuera)
            if not umbral:
                continue

            # Destinatarios: quien gestiona inventario/logística + el técnico solicitante.
            destinatarios = set(usuarios_con_permiso(db, p.empresa_id, "inventario", "gestionar"))
            emp = db.query(Empleado.usuario_id).filter(Empleado.id == p.solicitante_id).first()
            if emp and emp.usuario_id:
                destinatarios.add(emp.usuario_id)
            if not destinatarios:
                continue

            ps = db.query(ProyectoServicio.nombre).filter(
                ProyectoServicio.id == p.proyecto_servicio_id).first()
            psn = (ps.nombre if ps else "") or "un servicio"

            titulo = "Herramientas sin devolver"
            mensaje = (f"Hay equipos/herramientas del servicio '{psn}' entregados hace "
                       f"{dias_fuera} días sin registrar su devolución.")
            ref_key = f"prestamo_devol:{p.id}:{umbral}"
            if _emitir(db, empresa_id=p.empresa_id, usuarios=list(destinatarios),
                       tipo="warning", categoria="prestamos", titulo=titulo,
                       mensaje=mensaje, ref_key=ref_key):
                emitidos += 1

        db.commit()
        print(f"[Scheduler] Alertas de préstamos sin devolver: {emitidos}")
    except Exception as e:
        print(f"[Scheduler] Error en alertas de préstamos: {e}")
        db.rollback()
    finally:
        db.close()


def _alertas_tardanza():
    """Cada 15 min (mañana): empleados con turno activo que ya pasaron su hora
    de entrada + tolerancia y aún no marcaron entrada hoy. Avisa al empleado y a
    sus supervisores. Idempotente por (empleado, fecha)."""
    from app.models.turno import Turno, TurnoEmpleado
    from app.models.empleado import Empleado
    from app.models.registro_asistencia import RegistroAsistencia
    from app.models.usuario import Usuario
    from sqlalchemy import cast, Date as SaDate, or_
    from zoneinfo import ZoneInfo

    db: Session = SessionLocal()
    try:
        ahora = datetime.now(ZoneInfo("America/Lima")).replace(tzinfo=None)
        hoy = ahora.date()
        if not _es_dia_laborable(hoy):
            return  # domingo: no se notifica asistencia

        # Empleados que ya marcaron entrada hoy (para excluirlos)
        con_entrada = {
            r.empleado_id
            for r in db.query(RegistroAsistencia.empleado_id).filter(
                RegistroAsistencia.tipo == "entrada",
                cast(RegistroAsistencia.fecha_hora, SaDate) == hoy,
            ).all()
        }

        # Turnos activos vigentes hoy
        asignaciones = db.query(TurnoEmpleado).filter(
            TurnoEmpleado.activo.is_(True),
            TurnoEmpleado.fecha_desde <= hoy,
            or_(TurnoEmpleado.fecha_hasta.is_(None), TurnoEmpleado.fecha_hasta >= hoy),
        ).all()

        dest_cache: dict[str, list[str]] = {}
        emitidos = 0
        for te in asignaciones:
            if te.empleado_id in con_entrada:
                continue
            turno = db.query(Turno).filter(Turno.id == te.turno_id, Turno.activo.is_(True)).first()
            if not turno:
                continue
            tol = turno.tolerancia_minutos or 5
            limite = datetime.combine(hoy, turno.hora_entrada) + timedelta(minutes=tol)
            # Ventana: desde que vence la tolerancia hasta 3h después (evita avisar todo el día)
            if not (limite <= ahora <= limite + timedelta(hours=3)):
                continue

            emp = db.query(Empleado).filter(Empleado.id == te.empleado_id, Empleado.activo.is_(True)).first()
            if not emp:
                continue

            if emp.empresa_id not in dest_cache:
                dest_cache[emp.empresa_id] = usuarios_con_permiso(
                    db, emp.empresa_id, "asistencia", "validar")
            destinatarios = set(dest_cache[emp.empresa_id])
            if emp.usuario_id:
                destinatarios.add(emp.usuario_id)
            if not destinatarios:
                continue

            u = db.query(Usuario.nombre, Usuario.apellido).filter(Usuario.id == emp.usuario_id).first()
            nombre = (f"{u.nombre} {u.apellido}".strip() if u else "Empleado")
            hora_txt = turno.hora_entrada.strftime("%H:%M")
            ref_key = f"tardanza:{emp.id}:{hoy.isoformat()}"
            # Mensaje distinto para el propio empleado vs supervisores: usamos uno
            # general y emitimos a todos con la misma clave de idempotencia.
            titulo = "Entrada no registrada"
            mensaje = (f"{nombre} no ha marcado su entrada (turno {hora_txt}). "
                       f"Si ya estás en planta, registra tu asistencia ahora.")
            if _emitir(db, empresa_id=emp.empresa_id, usuarios=list(destinatarios),
                       tipo="warning", categoria="asistencia",
                       titulo=titulo, mensaje=mensaje, ref_key=ref_key):
                emitidos += 1

        db.commit()
        if emitidos:
            print(f"[Scheduler] Alertas de tardanza emitidas: {emitidos}")
    except Exception as e:
        print(f"[Scheduler] Error en alertas de tardanza: {e}")
        db.rollback()
    finally:
        db.close()


def _aviso_pre_horario():
    """Cada 5 min (madrugada–noche): avisa a cada empleado activo 15 min antes
    de su hora de entrada. La hora sale del turno-excepción vigente hoy; si no
    tiene asignación, se usa el horario normal (08:00). No avisa si el empleado
    ya marcó entrada hoy. Idempotente por (empleado, fecha)."""
    from app.models.turno import Turno, TurnoEmpleado
    from app.models.empleado import Empleado
    from app.models.registro_asistencia import RegistroAsistencia
    from sqlalchemy import cast, Date as SaDate, or_
    from zoneinfo import ZoneInfo

    DEF_ENTRADA = time(8, 0)
    ANTICIPACION_MIN = 15

    db: Session = SessionLocal()
    try:
        ahora = datetime.now(ZoneInfo("America/Lima")).replace(tzinfo=None)
        hoy = ahora.date()
        if not _es_dia_laborable(hoy):
            return  # domingo: no se notifica asistencia

        empleados = db.query(Empleado).filter(Empleado.activo.is_(True)).all()
        if not empleados:
            return

        # Turno-excepción vigente hoy por empleado (primera asignación gana).
        asignaciones = (
            db.query(TurnoEmpleado, Turno)
            .join(Turno, Turno.id == TurnoEmpleado.turno_id)
            .filter(
                TurnoEmpleado.activo.is_(True),
                Turno.activo.is_(True),
                TurnoEmpleado.fecha_desde <= hoy,
                or_(TurnoEmpleado.fecha_hasta.is_(None), TurnoEmpleado.fecha_hasta >= hoy),
            )
            .all()
        )
        turno_por_emp: dict = {}
        for te, turno in asignaciones:
            turno_por_emp.setdefault(te.empleado_id, turno)

        # Empleados que ya marcaron entrada hoy → no se les recuerda.
        con_entrada = {
            r.empleado_id
            for r in db.query(RegistroAsistencia.empleado_id).filter(
                RegistroAsistencia.tipo == "entrada",
                cast(RegistroAsistencia.fecha_hora, SaDate) == hoy,
            ).all()
        }

        emitidos = 0
        for emp in empleados:
            if emp.id in con_entrada or not emp.usuario_id:
                continue
            turno = turno_por_emp.get(emp.id)
            hora_entrada = turno.hora_entrada if turno else DEF_ENTRADA
            inicio   = datetime.combine(hoy, hora_entrada)
            objetivo = inicio - timedelta(minutes=ANTICIPACION_MIN)
            # Ventana: desde 15 min antes hasta la hora de entrada (un solo aviso).
            if not (objetivo <= ahora < inicio):
                continue

            hora_txt = hora_entrada.strftime("%H:%M")
            titulo  = "Tu jornada está por empezar"
            mensaje = (f"En {ANTICIPACION_MIN} minutos comienza tu horario ({hora_txt}). "
                       "Prepárate para marcar tu entrada.")
            ref_key = f"pre_horario:{emp.id}:{hoy.isoformat()}"
            if _emitir(db, empresa_id=emp.empresa_id, usuarios=[emp.usuario_id],
                       tipo="recordatorio", categoria="asistencia",
                       titulo=titulo, mensaje=mensaje, ref_key=ref_key):
                emitidos += 1

        db.commit()
        if emitidos:
            print(f"[Scheduler] Avisos pre-horario enviados: {emitidos}")
    except Exception as e:
        print(f"[Scheduler] Error en aviso pre-horario: {e}")
        db.rollback()
    finally:
        db.close()


def _depreciacion_mensual_automatica():
    """Día 1 de cada mes (01:00 Lima): deprecia el MES ANTERIOR para todas las
    empresas. Por cada empresa: asegura un periodo contable abierto para ese mes
    (lo crea si no existe; si está cerrado, lo respeta y omite) y procesa la
    depreciación de línea recta (Db 6814 / Cr 391).

    Idempotente: `procesar_depreciacion_periodo` no duplica asientos por
    (activo, periodo), así que correrlo de nuevo —o haberlo corrido a mano— es
    inofensivo."""
    from app.models.empresa import Empresa
    from app.models.contabilidad import PeriodoContable
    from app.services import activos_fijos_service as af

    db: Session = SessionLocal()
    try:
        hoy = date.today()
        # Mes anterior: último día del mes pasado = día 0 del mes actual.
        ultimo_mes = hoy.replace(day=1) - timedelta(days=1)
        anio, mes = ultimo_mes.year, ultimo_mes.month

        empresas = db.query(Empresa.id).all()
        total_emp = 0
        total_dep = 0
        for (eid,) in empresas:
            eid = str(eid)
            p = db.query(PeriodoContable).filter(
                PeriodoContable.empresa_id == eid,
                PeriodoContable.anio == anio,
                PeriodoContable.mes == mes,
            ).first()
            if p is None:
                p = PeriodoContable(empresa_id=eid, anio=anio, mes=mes, estado="abierto")
                db.add(p)
                db.commit()
                db.refresh(p)
            elif p.estado != "abierto":
                continue  # periodo cerrado por contabilidad: no se toca
            try:
                res = af.procesar_depreciacion_periodo(db, eid, str(p.id), None)
                if res.get("procesados"):
                    total_emp += 1
                    total_dep += res["procesados"]
            except Exception as exc:
                db.rollback()
                print(f"[Scheduler] ⚠️ Depreciación {anio}-{mes:02d} empresa {eid}: {exc}")
                continue

        print(f"[Scheduler] 🏭 Depreciación {anio}-{mes:02d}: "
              f"{total_dep} activo(s) en {total_emp} empresa(s)")
    except Exception as e:
        print(f"[Scheduler] ❌ Error en depreciación mensual: {e}")
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
    # Vencimientos (contratos, calibraciones, CXP, CXC) — 08:30 AM
    scheduler.add_job(
        func=_alertas_vencimientos,
        trigger=CronTrigger(hour=8, minute=30),
        id="alertas_vencimientos",
        replace_existing=True
    )
    # Préstamos sin devolver — 08:45 AM
    scheduler.add_job(
        func=_alertas_prestamos_sin_devolver,
        trigger=CronTrigger(hour=8, minute=45),
        id="alertas_prestamos_devol",
        replace_existing=True
    )
    # Tardanza / entrada no registrada — cada 15 min de 6 a 11 AM
    scheduler.add_job(
        func=_alertas_tardanza,
        trigger=CronTrigger(hour="6-11", minute="*/15"),
        id="alertas_tardanza",
        replace_existing=True
    )
    # Recordatorio 15 min antes del horario de entrada — cada 5 min de 4 a 21 h
    scheduler.add_job(
        func=_aviso_pre_horario,
        trigger=CronTrigger(hour="4-21", minute="*/5"),
        id="aviso_pre_horario",
        replace_existing=True
    )
    # Depreciación mensual de activos fijos — día 1 de cada mes, 01:00 (mes anterior)
    scheduler.add_job(
        func=_depreciacion_mensual_automatica,
        trigger=CronTrigger(day=1, hour=1, minute=0),
        id="depreciacion_mensual",
        replace_existing=True
    )
    scheduler.start()
    print("⏰ Scheduler iniciado → calendario 08:00 + mantenimiento 08:15 + "
          "vencimientos 08:30 + préstamos 08:45 + pre-horario cada 5 min (4-21h) + "
          "pre-almuerzo 11:45 + fin almuerzo cada 5 min + depreciación día 1 01:00")
def detener_scheduler():
    """Detiene el scheduler al cerrar la app."""
    if scheduler.running:
        scheduler.shutdown()
        print("⏰ Scheduler detenido.")