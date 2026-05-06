import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute } from '@angular/router';
import { Subscription } from 'rxjs';
// Ajusta esta ruta según dónde esté tu servicio
import { DashboardService } from '../../core/services/dashboard.service';
// 👇 1. IMPORTAMOS AMBAS TARJETAS
import { ProfileBannerComponent } from './components/profile-banner/profile-banner.component';
import { ProfileCardsComponent } from './components/profile-cards/profile-cards.component';
import { ProfileContactComponent } from './components/profile-contact/profile-contact.component';
import { ProfileCertificationsComponent } from './components/profile-certifications/profile-certifications.component';
@Component({
  selector: 'app-personal',
  standalone: true,
  // 👇 2. EL SECRETO ESTÁ AQUÍ: Agregamos ProfileCardsComponent al arreglo
  imports: [CommonModule, ProfileBannerComponent, ProfileCardsComponent, ProfileContactComponent, ProfileCertificationsComponent],
  templateUrl: './personal.component.html',
  styleUrls: ['./personal.component.css']
})
export class PersonalComponent implements OnInit, OnDestroy {
  private dashboardService = inject(DashboardService);
  private route = inject(ActivatedRoute);
  private perfilSub!: Subscription;

  tabActiva = 'perfil';

  // Objeto para el Banner
  perfilReal: any = {
    nombreCompleto: 'Cargando...', rol: '...', ubicacion: '...',
    fechaIngreso: '...', telefono: '...', correo: '...',
    fotoUrl: '', iniciales: ''
  };

  ngOnInit() {
    // Escucha si venimos de otra pantalla a una pestaña específica
    this.route.queryParams.subscribe(params => {
      if (params['tab']) this.tabActiva = params['tab'];
    });

    this.cargarDatosBackend();

    // Escucha cambios en tiempo real
    if (this.dashboardService.perfilActualizado$) {
      this.perfilSub = this.dashboardService.perfilActualizado$.subscribe(() => {
        this.cargarDatosBackend();
      });
    }
  }

  ngOnDestroy() {
    if (this.perfilSub) this.perfilSub.unsubscribe();
  }

  cargarDatosBackend() {
    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          const p = res.data.personal;
          const e = res.data.empresa;
          this.perfilReal = {
            nombreCompleto: `${p.nombre} ${p.apellido}`,
            rol: p.rol,
            ubicacion: e.ubicacion || 'Sede Principal',
            fechaIngreso: p.fechaCreacion,
            telefono: p.telefono || 'No registrado',
            correo: p.correo,
            fotoUrl: p.fotoUrl,
            iniciales: p.nombre.charAt(0).toUpperCase() + p.apellido.charAt(0).toUpperCase()
          };
        }
      }
    });
  }
}