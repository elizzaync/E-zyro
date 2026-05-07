import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DashboardService } from '../../../../core/services/dashboard.service';

@Component({
  selector: 'app-profile-certifications',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-certifications.component.html',
  styleUrls: ['./profile-certifications.component.css']
})
export class ProfileCertificationsComponent implements OnInit {
  private dashboardService = inject(DashboardService);

  capacitaciones: any[] = [];
  cargando = true;

  ngOnInit() {
    this.dashboardService.getCapacitaciones().subscribe({
      next: (res: any) => {
        if (res.status === 'success') this.capacitaciones = res.data;
        this.cargando = false;
      },
      error: () => { this.cargando = false; }
    });
  }

  nivelClase(nivelRaw: string): string {
    const mapa: Record<string, string> = {
      basico: 'nivel-basico',
      intermedio: 'nivel-intermedio',
      avanzado: 'nivel-avanzado',
      experto: 'nivel-experto'
    };
    return mapa[nivelRaw] ?? '';
  }
}
