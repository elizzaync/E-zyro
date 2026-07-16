import { Injectable, inject, NgZone, isDevMode } from '@angular/core';
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
        if (isDevMode()) console.log('🔥 Mensaje recibido en primer plano: ', payload);

        const titulo = payload.notification?.title || 'Nueva Alerta';
        const cuerpo = payload.notification?.body || '';

        // Solo el toast in-app: con la pestaña en primer plano ya es visible.
        // NO se llama también a registration.showNotification() aquí — eso
        // duplicaba la alerta (toast + notificación nativa del navegador para
        // el mismo mensaje). La notificación nativa queda exclusivamente a
        // cargo de firebase-messaging-sw.js (onBackgroundMessage), que solo
        // se dispara cuando la pestaña NO está en foco.
        this.toastService.mostrar(`${titulo}: ${cuerpo}`, 'info');

        this.dashboardService.refreshWidgets$.next(true);
      });
    });
  }
}