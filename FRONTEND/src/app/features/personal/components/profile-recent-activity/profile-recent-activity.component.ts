import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DashboardService } from '../../../../core/services/dashboard.service';

type TipoIcono = 'success' | 'update' | 'danger' | 'ticket' | 'asistencia';

interface Actividad {
  id: string;
  titulo: string;
  modulo: string;
  tiempo: string;
  tipo: TipoIcono;
}

@Component({
  selector: 'app-profile-recent-activity',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-recent-activity.component.html',
  styleUrls: ['./profile-recent-activity.component.css']
})
export class ProfileRecentActivityComponent implements OnInit {
  private dashboardService = inject(DashboardService);

  actividades: Actividad[] = [];
  cargando = true;

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando = true;
    this.dashboardService.getActividadReciente().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.actividades = res.data.map((r: any) => ({
            id:     r.id,
            titulo: r.descripcion,
            modulo: r.modulo,
            tiempo: this.formatearTiempo(r.fecha),
            tipo:   this.mapTipo(r.accion)
          }));
        }
        this.cargando = false;
      },
      error: () => { this.cargando = false; }
    });
  }

  private mapTipo(accion: string): TipoIcono {
    const mapa: Record<string, TipoIcono> = {
      INSERT:          'success',
      UPDATE:          'update',
      DELETE:          'danger',
      EXPORT:          'asistencia',
      ACCESO_DENEGADO: 'ticket'
    };
    return mapa[accion] ?? 'update';
  }

  private formatearTiempo(fechaIso: string | null): string {
    if (!fechaIso) return '';
    const diff  = Date.now() - new Date(fechaIso).getTime();
    const mins  = Math.floor(diff / 60_000);
    const hours = Math.floor(diff / 3_600_000);
    const days  = Math.floor(diff / 86_400_000);
    if (mins  < 1)  return 'Hace un momento';
    if (mins  < 60) return `Hace ${mins} min`;
    if (hours < 24) return `Hace ${hours} h`;
    if (days  < 7)  return `Hace ${days} día${days > 1 ? 's' : ''}`;
    return new Date(fechaIso).toLocaleDateString('es-PE', { day: 'numeric', month: 'short', year: 'numeric' });
  }
}
