import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { EppFormModalComponent } from '../epp-form-modal/epp-form-modal.component';
import { EppEntregaModalComponent } from '../epp-entrega-modal/epp-entrega-modal.component';
import { Epp, EppIn, EppEntrega } from '../../logistica.models';

type SubTabEpp = 'catalogo' | 'entregas';

@Component({
  selector: 'app-epp-tabla',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent, EppFormModalComponent, EppEntregaModalComponent],
  templateUrl: './epp-tabla.component.html',
  styleUrls: ['./epp-tabla.component.css'],
})
export class EppTablaComponent implements OnInit {
  private svc   = inject(LogisticaService);
  private toast = inject(ToastService);

  subTab: SubTabEpp = 'catalogo';

  cargandoCatalogo = true;
  epps: Epp[] = [];
  busquedaCatalogo = '';
  soloStockBajo = false;

  cargandoEntregas = true;
  entregas: EppEntrega[] = [];

  showFormModal = false;
  eppEditar: Epp | null = null;
  guardandoEpp = false;

  showEntregaModal = false;
  generandoConstancia: string | null = null;

  entregaDetalle: EppEntrega | null = null;

  ngOnInit(): void {
    this.cargarCatalogo();
    this.cargarEntregas();
  }

  setSubTab(t: SubTabEpp): void {
    this.subTab = t;
    if (t === 'entregas' && this.entregas.length === 0) this.cargarEntregas();
  }

  cargarCatalogo(): void {
    this.cargandoCatalogo = true;
    this.svc.getEpps({ q: this.busquedaCatalogo || undefined, stockBajo: this.soloStockBajo }).subscribe({
      next:  r => { this.epps = r; this.cargandoCatalogo = false; },
      error: () => { this.cargandoCatalogo = false; this.toast.mostrar('Error al cargar el catálogo de EPPs.', 'error'); },
    });
  }

  buscarCatalogo(): void { this.cargarCatalogo(); }

  cargarEntregas(): void {
    this.cargandoEntregas = true;
    this.svc.getEntregasEpp().subscribe({
      next:  r => { this.entregas = r; this.cargandoEntregas = false; },
      error: () => { this.cargandoEntregas = false; this.toast.mostrar('Error al cargar las entregas de EPP.', 'error'); },
    });
  }

  abrirNuevoEpp(): void { this.eppEditar = null; this.showFormModal = true; }
  editarEpp(e: Epp): void { this.eppEditar = e; this.showFormModal = true; }
  cerrarFormModal(): void { this.showFormModal = false; this.eppEditar = null; }

  guardarEpp(body: EppIn): void {
    this.guardandoEpp = true;
    const obs = this.eppEditar
      ? this.svc.actualizarEpp(this.eppEditar.id, body)
      : this.svc.crearEpp(body);
    obs.subscribe({
      next: () => {
        this.guardandoEpp = false;
        this.toast.mostrar(this.eppEditar ? 'EPP actualizado.' : 'EPP creado.', 'success');
        this.cerrarFormModal();
        this.cargarCatalogo();
      },
      error: (err) => {
        this.guardandoEpp = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al guardar el EPP.', 'error');
      },
    });
  }

  eliminarEpp(e: Epp): void {
    if (!confirm(`¿Dar de baja "${e.nombre}"? Se conserva su historial de entregas.`)) return;
    this.svc.eliminarEpp(e.id).subscribe({
      next: () => { this.toast.mostrar('EPP dado de baja.', 'success'); this.cargarCatalogo(); },
      error: (err) => this.toast.mostrar(err?.error?.detail ?? 'Error al eliminar el EPP.', 'error'),
    });
  }

  abrirNuevaEntrega(): void { this.showEntregaModal = true; }
  cerrarEntregaModal(): void { this.showEntregaModal = false; }
  onEntregaRegistrada(): void {
    this.showEntregaModal = false;
    this.cargarCatalogo();
    this.cargarEntregas();
  }

  abrirDetalleEntrega(en: EppEntrega): void { this.entregaDetalle = en; document.body.style.overflow = 'hidden'; }
  cerrarDetalleEntrega(): void { this.entregaDetalle = null; document.body.style.overflow = ''; }

  generarConstancia(en: EppEntrega, ev?: Event): void {
    ev?.stopPropagation();
    this.generandoConstancia = en.id;
    this.svc.generarConstanciaEpp(en.id).subscribe({
      next: (r) => {
        this.generandoConstancia = null;
        if (this.entregaDetalle?.id === en.id) this.entregaDetalle = r;
        const idx = this.entregas.findIndex(e => e.id === en.id);
        if (idx >= 0) this.entregas[idx] = r;
        if (r.pdf_url) window.open(r.pdf_url, '_blank');
        this.toast.mostrar('Constancia generada.', 'success');
      },
      error: () => {
        this.generandoConstancia = null;
        this.toast.mostrar('Error al generar la constancia.', 'error');
      },
    });
  }

  anularEntrega(en: EppEntrega, ev?: Event): void {
    ev?.stopPropagation();
    if (!confirm('¿Anular esta entrega? El stock devuelto vuelve al catálogo.')) return;
    this.svc.anularEntregaEpp(en.id).subscribe({
      next: () => {
        this.toast.mostrar('Entrega anulada.', 'success');
        this.cargarEntregas();
        this.cargarCatalogo();
        if (this.entregaDetalle?.id === en.id) this.cerrarDetalleEntrega();
      },
      error: (err) => this.toast.mostrar(err?.error?.detail ?? 'Error al anular la entrega.', 'error'),
    });
  }

  fechaCorta(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  resumenItems(items: { nombre: string }[]): string {
    if (!items.length) return '—';
    const primeros = items.slice(0, 2).map(i => i.nombre).join(', ');
    return items.length > 2 ? `${primeros} +${items.length - 2} más` : primeros;
  }
}
