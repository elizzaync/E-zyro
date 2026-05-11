import { Injectable } from '@angular/core';
import { Subject } from 'rxjs';

export interface ToastData {
  mensaje: string;
  tipo: 'success' | 'error' | 'info';
}

@Injectable({
  providedIn: 'root'
})
export class ToastService {
  // 1. El 'Source' privado que sí tiene el .next()
  private toastSource = new Subject<ToastData>();

  // 2. El 'Observable' público que los componentes escuchan
  toast$ = this.toastSource.asObservable();

  // 3. 🔥 EL MÉTODO NUEVO PARA LANZAR TOASTS
  mostrar(mensaje: string, tipo: 'success' | 'error' | 'info' = 'success') {
    this.toastSource.next({ mensaje, tipo });
  }
}