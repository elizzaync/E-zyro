import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { AsistenciaService, EstadoHoyDto } from '../../core/services/asistencia.service';

type Paso = 'cargando' | 'listo' | 'marcando' | 'exito' | 'error_empleado' | 'error';

@Component({
  selector: 'app-asistencia',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './asistencia.component.html',
  styleUrls: ['./asistencia.component.css']
})
export class AsistenciaComponent implements OnInit, OnDestroy {

  paso: Paso = 'cargando';
  estado: EstadoHoyDto | null = null;
  ultimaMarca: string | null = null;
  ultimoTipo: string | null = null;
  errorMsg = '';

  horaActual = '';
  fechaActual = '';

  private relojInterval: ReturnType<typeof setInterval> | null = null;

  constructor(
    private svc: AsistenciaService,
    private router: Router,
  ) {}

  ngOnInit(): void {
    this.actualizarReloj();
    this.relojInterval = setInterval(() => this.actualizarReloj(), 1000);
    this.cargarEstado();
  }

  ngOnDestroy(): void {
    if (this.relojInterval) clearInterval(this.relojInterval);
  }

  private actualizarReloj(): void {
    const now = new Date();
    this.horaActual = now.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
    const opts: Intl.DateTimeFormatOptions = { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' };
    const raw = now.toLocaleDateString('es-PE', opts);
    this.fechaActual = raw.charAt(0).toUpperCase() + raw.slice(1);
  }

  private cargarEstado(): void {
    this.paso = 'cargando';
    this.svc.getEstadoHoy().subscribe({
      next: (est) => {
        this.estado = est;
        this.paso = 'listo';
      },
      error: (err) => {
        const detail = err?.error?.detail ?? '';
        if (err.status === 404 || detail.includes('Empleado')) {
          this.paso = 'error_empleado';
        } else {
          this.errorMsg = 'No se pudo conectar al servidor.';
          this.paso = 'error';
        }
      },
    });
  }

  get accionPendiente(): 'entrada' | 'salida' | null {
    if (!this.estado) return null;
    if (!this.estado.tiene_entrada) return 'entrada';
    if (!this.estado.tiene_salida) return 'salida';
    return null;
  }

  marcar(): void {
    const tipo = this.accionPendiente;
    if (!tipo) return;

    this.paso = 'marcando';
    this.svc.marcar(tipo).subscribe({
      next: (res) => {
        const hora = new Date(res.timestamp).toLocaleTimeString('es-PE', {
          hour: '2-digit', minute: '2-digit', hour12: false,
        });
        this.ultimaMarca = hora;
        this.ultimoTipo  = tipo;
        this.paso = 'exito';
        setTimeout(() => this.cargarEstado(), 2000);
      },
      error: (err) => {
        this.errorMsg = err?.error?.detail ?? 'Ocurrió un error al marcar. Intenta de nuevo.';
        this.paso = 'error';
      },
    });
  }

  reintentar(): void {
    this.cargarEstado();
  }

  volver(): void {
    this.router.navigate(['/home']);
  }
}
