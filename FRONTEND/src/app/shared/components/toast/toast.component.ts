import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Subscription } from 'rxjs';
import { ToastService, ToastData } from '../../../core/services/toast.service';

@Component({
  selector: 'app-toast',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './toast.component.html',
  styleUrls: ['./toast.component.css']
})
export class ToastComponent implements OnInit, OnDestroy {
  visible = false;
  mensaje = '';
  tipo: 'success' | 'error' | 'info' = 'success';

  private timeout: any;
  private sub!: Subscription;

  constructor(private toastService: ToastService) {}

  ngOnInit(): void {
    this.sub = this.toastService.toast$.subscribe((data: ToastData) => {
      this.mensaje = data.mensaje;
      this.tipo = data.tipo;
      this.visible = true;

      if (this.timeout) clearTimeout(this.timeout);

      this.timeout = setTimeout(() => {
        this.visible = false;
      }, 3500);
    });
  }

  ngOnDestroy(): void {
    if (this.sub) this.sub.unsubscribe();
  }

  cerrar(): void {
    this.visible = false;
  }
}