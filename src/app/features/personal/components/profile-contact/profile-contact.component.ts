import { Component, Input, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute } from '@angular/router';
import { DashboardService } from '../../../../core/services/dashboard.service';
import { ProfileDocumentsComponent } from '../profile-documents/profile-documents.component';
import { ProfileAttendanceListComponent } from '../profile-attendance-list/profile-attendance-list.component';

@Component({
  selector: 'app-profile-contact',
  standalone: true,
  // 👇 2. LO DECLARAMOS AQUÍ PARA QUE EL HTML LO RECONOZCA
  imports: [CommonModule, ProfileDocumentsComponent, ProfileAttendanceListComponent],
  templateUrl: './profile-contact.component.html',
  styleUrls: ['./profile-contact.component.css']
})
export class ProfileContactComponent implements OnInit {
  @Input() perfil: any = {};

  tabActiva: string = 'perfil';
  asistencia: any = null;
  cargandoAsistencia = false;

  private route           = inject(ActivatedRoute);
  private dashboardService = inject(DashboardService);

  ngOnInit() {
    this.route.queryParams.subscribe(params => {
      if (params['tab']) {
        this.tabActiva = params['tab'];
        if (params['tab'] === 'asistencia') this.cargarAsistencia();
      }
    });
  }

  cambiarTab(tab: string) {
    this.tabActiva = tab;
    if (tab === 'asistencia' && !this.asistencia && !this.cargandoAsistencia) {
      this.cargarAsistencia();
    }
  }

  cargarAsistencia() {
    this.cargandoAsistencia = true;
    this.dashboardService.getAsistencia().subscribe({
      next: (res: any) => {
        if (res.status === 'success') this.asistencia = res.data;
        this.cargandoAsistencia = false;
      },
      error: () => { this.cargandoAsistencia = false; }
    });
  }
}