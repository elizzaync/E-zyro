import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { forkJoin } from 'rxjs';
import { DashboardService } from '../../../../core/services/dashboard.service';

interface Documento {
  id: string;
  titulo: string;
  categoria: 'Boletas' | 'Contratos' | 'Permisos';
  subtipo: string;
  estado?: string;
  fecha: string;
  fechaFin?: string | null;
  url?: string | null;
}

@Component({
  selector: 'app-profile-documents',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-documents.component.html',
  styleUrls: ['./profile-documents.component.css']
})
export class ProfileDocumentsComponent implements OnInit {
  private dashboardService = inject(DashboardService);

  filtroActivo = 'Todos';
  categorias = ['Todos', 'Boletas', 'Contratos', 'Permisos'];

  documentos: Documento[] = [];
  cargando = true;
  error = false;

  ngOnInit() {
    this.cargarDocumentos();
  }

  cargarDocumentos() {
    this.cargando = true;
    this.error = false;

    forkJoin({
      boletas:   this.dashboardService.getBoletas(),
      contratos: this.dashboardService.getContratos(),
      permisos:  this.dashboardService.getPermisos(),
    }).subscribe({
      next: ({ boletas, contratos, permisos }) => {
        const docs: Documento[] = [];

        if (boletas.status === 'success') {
          for (const b of boletas.data) {
            docs.push({ id: b.id, titulo: b.titulo, categoria: 'Boletas', subtipo: b.tipo, fecha: b.fecha, url: b.url });
          }
        }

        if (contratos.status === 'success') {
          for (const c of contratos.data) {
            docs.push({ id: c.id, titulo: c.titulo, categoria: 'Contratos', subtipo: c.tipo, estado: c.estado, fecha: c.fecha_inicio, fechaFin: c.fecha_fin, url: c.url });
          }
        }

        if (permisos.status === 'success') {
          for (const p of permisos.data) {
            // Las justificaciones (falta/tardanza) pertenecen a Asistencia,
            // no son permisos ni documentos del personal.
            if ((p.tipo || '').startsWith('justificacion')) continue;
            docs.push({ id: p.id, titulo: p.titulo, categoria: 'Permisos', subtipo: p.tipo, estado: p.estado, fecha: p.fecha, url: p.url ?? null });
          }
        }

        this.documentos = docs;
        this.cargando = false;
      },
      error: () => {
        this.error = true;
        this.cargando = false;
      }
    });
  }

  cambiarFiltro(cat: string) {
    this.filtroActivo = cat;
  }

  get documentosFiltrados(): Documento[] {
    if (this.filtroActivo === 'Todos') return this.documentos;
    return this.documentos.filter(d => d.categoria === this.filtroActivo);
  }

  getCantidad(cat: string): number {
    if (cat === 'Todos') return this.documentos.length;
    return this.documentos.filter(d => d.categoria === cat).length;
  }

  abrirDocumento(url?: string | null) {
    if (url) window.open(url, '_blank');
  }

  getEstadoClass(estado?: string): string {
    const map: Record<string, string> = {
      'Vigente': 'estado-vigente', 'Renovado': 'estado-vigente', 'Aprobada': 'estado-aprobada',
      'Pendiente': 'estado-pendiente',
      'Vencido': 'estado-vencido', 'Anulada': 'estado-vencido',
      'Rechazada': 'estado-rechazada', 'Rescindido': 'estado-rechazada',
    };
    return map[estado || ''] || '';
  }
}
