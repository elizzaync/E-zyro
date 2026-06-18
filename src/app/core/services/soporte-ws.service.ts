import { Injectable } from '@angular/core';
import { Subject } from 'rxjs';
import { environment } from '../../../environments/environment';

export type SoporteWsEvent =
  | { tipo: 'ticket_nuevo';       ticket: { id: string; codigo: string; titulo: string; estado: string; prioridad: string } }
  | { tipo: 'ticket_actualizado'; ticket: { id: string; codigo: string; estado: string } }
  | { tipo: 'sesion_nueva';       usuario: string; dispositivo: string; ip: string }
  | { tipo: 'sesion_cerrada' }
  | { tipo: 'ip_bloqueada';       ip: string }
  | { tipo: 'ip_desbloqueada';    ip: string }
  | { tipo: 'auditoria_nueva' }
  | { tipo: 'dispositivos_cambio' };

@Injectable({ providedIn: 'root' })
export class SoporteWsService {
  private ws: WebSocket | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private shouldReconnect = false;
  private currentToken: string | null = null;

  /** Flujo de eventos emitidos por el backend. Suscríbete en los componentes. */
  readonly evento$ = new Subject<SoporteWsEvent>();

  /** Conecta al WebSocket de soporte. Idempotente: si ya hay conexión activa no hace nada. */
  connect(token: string): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN && this.currentToken === token) {
      return; // ya conectado con el mismo token
    }
    this.disconnect();
    this.shouldReconnect = true;
    this.currentToken = token;
    this._open(token);
  }

  private _open(token: string): void {
    const wsBase = environment.apiUrl
      .replace(/^https:\/\//i, 'wss://')
      .replace(/^http:\/\//i, 'ws://');

    let socket: WebSocket;
    try {
      socket = new WebSocket(`${wsBase}/ws/soporte?token=${token}`);
    } catch {
      this._scheduleReconnect(token);
      return;
    }
    this.ws = socket;

    socket.onmessage = (e: MessageEvent) => {
      try {
        const data = JSON.parse(e.data);
        if (data?.tipo) this.evento$.next(data as SoporteWsEvent);
      } catch { /* ignorar mensajes malformados */ }
    };

    socket.onclose = (ev: CloseEvent) => {
      this.ws = null;
      // 4001 = token inválido o sin permiso → no reconectar
      if (this.shouldReconnect && ev.code !== 4001) {
        this._scheduleReconnect(token);
      }
    };

    socket.onerror = () => {
      // onclose se encarga de reconectar
      try { socket.close(); } catch { /* noop */ }
    };
  }

  private _scheduleReconnect(token: string): void {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (this.shouldReconnect) this._open(token);
    }, 5000);
  }

  disconnect(): void {
    this.shouldReconnect = false;
    this.currentToken = null;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      try { this.ws.close(); } catch { /* noop */ }
      this.ws = null;
    }
  }
}
