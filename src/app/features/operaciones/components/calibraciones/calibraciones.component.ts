import { Component, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  CalibracionesService, CalibracionOut, EventoOut, EventoIn,
} from '../../../../core/services/calibraciones.service';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { EquipoHerramienta } from '../../../logistica/logistica.models';

type EstadoCal = 'ok' | 'por_vencer' | 'vencida' | 'sin_fecha';

@Component({
  selector: 'app-calibraciones',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './calibraciones.component.html',
  styleUrls: ['./calibraciones.component.css'],
})
export class CalibracionesComponent implements OnInit {
  private svc     = inject(CalibracionesService);
  private logSvc  = inject(LogisticaService);

  // Lista principal
  calibraciones: CalibracionOut[] = [];
  cargando = true;
  busqueda = '';
  soloPorVencer = false;

  // Modal historial
  showModal = false;
  modalCal: CalibracionOut | null = null;
  eventos: EventoOut[] = [];
  cargandoEventos = false;
  eliminandoEvento: string | null = null;

  // Formulario nuevo evento
  addOpen = false;
  form: EventoIn = this.formVacio();
  guardando = false;
  archivoCert: string | null = null;
  archivoCertExt = 'pdf';

  // Selección de equipo
  showNuevoEquipo = false;
  busqEquipo = '';
  todosEquipos: EquipoHerramienta[] = [];
  cargandoEquipos = false;

  get equiposFiltrados(): EquipoHerramienta[] {
    const q = this.busqEquipo.toLowerCase().trim();
    return this.todosEquipos
      .filter(e => !q ||
        e.nombre.toLowerCase().includes(q) ||
        (e.codigo ?? '').toLowerCase().includes(q) ||
        (e.tipo   ?? '').toLowerCase().includes(q)
      );
  }

  ngOnInit(): void {
    this.cargar();
  }

  cargar(): void {
    this.cargando = true;
    this.svc.listar(this.soloPorVencer).subscribe({
      next: (r) => { this.calibraciones = r; this.cargando = false; },
      error: () => { this.cargando = false; },
    });
  }

  get filtradas(): CalibracionOut[] {
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return this.calibraciones;
    return this.calibraciones.filter(c =>
      (c.equipo_nombre ?? '').toLowerCase().includes(q)
    );
  }

  estado(c: CalibracionOut): EstadoCal {
    if (!c.fecha_proxima) return 'sin_fecha';
    const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    const prox = new Date(c.fecha_proxima + 'T00:00:00');
    const diff = (prox.getTime() - hoy.getTime()) / 86400000;
    if (diff < 0)   return 'vencida';
    if (diff <= 30) return 'por_vencer';
    return 'ok';
  }

  estadoLabel(e: EstadoCal): string {
    return { ok: 'Al día', por_vencer: 'Por vencer', vencida: 'Vencida', sin_fecha: 'Sin fecha' }[e];
  }

  diasRestantes(c: CalibracionOut): number | null {
    if (!c.fecha_proxima) return null;
    const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    const prox = new Date(c.fecha_proxima + 'T00:00:00');
    return Math.round((prox.getTime() - hoy.getTime()) / 86400000);
  }

  formatFecha(f: string | null): string {
    if (!f) return '—';
    const [y, m, d] = f.split('-');
    const meses = ['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return `${d} ${meses[+m]} ${y}`;
  }

  // ── Modal historial ────────────────────────────────────────────────────────
  abrirModal(c: CalibracionOut): void {
    this.modalCal = c;
    this.showModal = true;
    this.addOpen = false;
    this.form = this.formVacio();
    this.archivoCert = null;
    document.body.style.overflow = 'hidden';
    this.cargarEventos(c.equipo_id);
  }

  cerrarModal(): void {
    this.showModal = false;
    this.modalCal = null;
    this.eventos = [];
    document.body.style.overflow = '';
  }

  cargarEventos(equipoId: string): void {
    this.cargandoEventos = true;
    this.svc.listarEventos(equipoId).subscribe({
      next: (r) => { this.eventos = r; this.cargandoEventos = false; },
      error: () => { this.cargandoEventos = false; },
    });
  }

  eliminarEvento(id: string): void {
    if (this.eliminandoEvento) return;
    this.eliminandoEvento = id;
    this.svc.eliminarEvento(id).subscribe({
      next: () => {
        this.eventos = this.eventos.filter(e => e.id !== id);
        this.eliminandoEvento = null;
        const idx = this.calibraciones.findIndex(c => c.equipo_id === this.modalCal?.equipo_id);
        if (idx >= 0) this.calibraciones[idx].total_eventos = Math.max(0, this.calibraciones[idx].total_eventos - 1);
      },
      error: () => { this.eliminandoEvento = null; },
    });
  }

  // ── Formulario nuevo evento ───────────────────────────────────────────────
  formVacio(): EventoIn {
    return {
      equipo_id: '',
      fecha_realizada: new Date().toISOString().slice(0, 10),
      periodicidad_meses: 12,
      fecha_proxima: null,
      realizada_por: '',
      empresa_responsable: '',
      numero_certificado: '',
      resultado: '',
      observacion: '',
    };
  }

  onArchivo(e: Event): void {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    this.archivoCertExt = file.name.split('.').pop() ?? 'pdf';
    const reader = new FileReader();
    reader.onload = () => { this.archivoCert = (reader.result as string).split(',')[1]; };
    reader.readAsDataURL(file);
  }

  guardarEvento(): void {
    if (!this.form.fecha_realizada || this.guardando) return;
    this.guardando = true;
    const body: EventoIn = {
      ...this.form,
      equipo_id: this.modalCal!.equipo_id,
    };
    this.svc.crearEvento(body).subscribe({
      next: (ev) => {
        if (this.archivoCert) {
          this.svc.subirCertificado(ev.id, this.archivoCert, this.archivoCertExt).subscribe({
            next: (evActual) => {
              this.eventos = [evActual, ...this.eventos];
              this.finalizarGuardado();
            },
            error: () => {
              this.eventos = [ev, ...this.eventos];
              this.finalizarGuardado();
            },
          });
        } else {
          this.eventos = [ev, ...this.eventos];
          this.finalizarGuardado();
        }
        const idx = this.calibraciones.findIndex(c => c.equipo_id === this.modalCal?.equipo_id);
        if (idx >= 0) {
          this.calibraciones[idx].total_eventos++;
          if (ev.fecha_proxima) this.calibraciones[idx].fecha_proxima = ev.fecha_proxima;
          if (ev.fecha_realizada) this.calibraciones[idx].fecha_ultima = ev.fecha_realizada;
        }
      },
      error: () => { this.guardando = false; },
    });
  }

  private finalizarGuardado(): void {
    this.guardando = false;
    this.addOpen = false;
    this.form = this.formVacio();
    this.archivoCert = null;
  }

  // ── Agregar equipo nuevo ──────────────────────────────────────────────────
  abrirNuevoEquipo(): void {
    this.showNuevoEquipo = true;
    this.busqEquipo = '';
    document.body.style.overflow = 'hidden';
    if (this.todosEquipos.length === 0) {
      this.cargandoEquipos = true;
      this.logSvc.getEquipos({ pageSize: 200 }).subscribe({
        next: (items) => { this.todosEquipos = items; this.cargandoEquipos = false; },
        error: ()      => { this.cargandoEquipos = false; },
      });
    }
  }

  cerrarNuevoEquipo(): void {
    this.showNuevoEquipo = false;
    document.body.style.overflow = '';
  }

  seleccionarEquipoNuevo(eq: EquipoHerramienta): void {
    const yaExiste = this.calibraciones.find(c => c.equipo_id === eq.id);
    if (yaExiste) {
      this.cerrarNuevoEquipo();
      this.abrirModal(yaExiste);
      return;
    }
    const nueva: CalibracionOut = {
      id: '', equipo_id: eq.id, equipo_nombre: eq.nombre,
      fecha_ultima: null, fecha_proxima: null,
      empresa_responsable: null, certificado_url: null,
      observacion: null, total_eventos: 0,
    };
    this.calibraciones = [nueva, ...this.calibraciones];
    this.cerrarNuevoEquipo();
    this.abrirModal(nueva);
  }
}
