import { Injectable, inject, NgZone } from '@angular/core';
import { initializeApp } from 'firebase/app';
import { getMessaging, getToken, onMessage } from 'firebase/messaging';
import { environment } from '../../../environments/environment';
import { ToastService } from './toast.service';
import { DashboardService } from './dashboard.service';

@Injectable({
  providedIn: 'root'
})
export class FcmService {
  private toastService = inject(ToastService);
  private dashboardService = inject(DashboardService);
  private ngZone = inject(NgZone);

  constructor() {
    this.iniciarFirebase();
  }

  private iniciarFirebase() {
    const app = initializeApp(environment.firebaseConfig);
    const messaging = getMessaging(app);

    Notification.requestPermission().then((permission) => {
      if (permission === 'granted') {
        getToken(messaging, { vapidKey: environment.vapidKey }).then((currentToken) => {
          if (currentToken) {
            this.dashboardService.guardarTokenPush(currentToken).subscribe({
              error: (err) => console.error('Error sincronizando con el servidor', err)
            });
          }
        }).catch((err) => console.error('Error al obtener el token de Firebase.', err));
      } else {
        console.warn('Permiso para notificaciones denegado por el usuario.');
      }
    });

    onMessage(messaging, (payload) => {
      this.ngZone.run(() => {
        console.log('🔥 Mensaje recibido en primer plano: ', payload);

        const titulo = payload.notification?.title || 'Nueva Alerta';
        const cuerpo = payload.notification?.body || '';

        this.toastService.mostrar(`${titulo}: ${cuerpo}`, 'info');

        // Chrome bloquea new Notification() cuando hay SW activo;
        // usamos el SW directamente para mostrar la notificación nativa.
        if (Notification.permission === 'granted' && 'serviceWorker' in navigator) {
          navigator.serviceWorker.ready.then(registration => {
            registration.showNotification(titulo, {
              body: cuerpo,
              icon: '/logo.ico'
            });
          }).catch(() => {});
        }

        this.dashboardService.refreshWidgets$.next(true);
      });
    });
  }
}