import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ActivatedRoute } from '@angular/router';
import { OperacionesService } from '../../../../core/services/operaciones.service';

@Component({
  selector: 'app-intervencion-equipo',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './intervencion-equipo.component.html',
  styleUrls: ['./intervencion-equipo.component.css'],
})
export class IntervencionEquipoComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private location = inject(Location);
  private svc      = inject(OperacionesService);

  servicioId = '';
  eiId       = '';
  cargando   = true;
  equipo: any = null;

  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id')    ?? '';
    this.eiId       = this.route.snapshot.paramMap.get('eiId')  ?? '';
    this.cargar();
  }

  cargar(): void {
    this.svc.getEquiposIntervenidos(this.servicioId).subscribe({
      next: (lista) => {
        this.equipo  = lista.find((e: any) => e.id === this.eiId) ?? null;
        this.cargando = false;
      },
      error: () => { this.cargando = false; }
    });
  }

  completar(): void {
    this.svc.actualizarEstadoIntervencion(this.servicioId, this.eiId, 'completado').subscribe({
      next: () => {
        if (this.equipo) this.equipo.estado_intervencion = 'completado';
      }
    });
  }

  volver(): void { this.location.back(); }
}
