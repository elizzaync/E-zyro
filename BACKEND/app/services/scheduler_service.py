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
def iniciar_scheduler():
    """Registra las tareas y arranca el scheduler. Llamar desde main.py."""
    # Recordatorio diario a las 08:00 AM
    scheduler.add_job(
        func=_enviar_recordatorios_calendario,
        trigger=CronTrigger(hour=8, minute=0),
        id="recordatorio_calendario",
        replace_existing=True
    )
    scheduler.start()
    print("⏰ Scheduler iniciado → Recordatorios de calendario a las 08:00 AM")
def detener_scheduler():
    """Detiene el scheduler al cerrar la app."""
    if scheduler.running:
        scheduler.shutdown()
        print("⏰ Scheduler detenido.")