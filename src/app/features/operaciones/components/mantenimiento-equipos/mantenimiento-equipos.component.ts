import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { EquipoIntervenidoService } from '../../../../core/services/equipo-intervenido.service';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

const ESTADOS = ['operativo', 'inoperativo', 'mantenimiento', 'en_revision'] as const;

interface GrupoZona {
  zona: string;
  equipos: any[];
  semaforo: 'vencido' | 'proximo' | 'ok';
}
interface GrupoUbicacion {
  ubicacion: string;
  zonas: GrupoZona[];
  total: number;
  semaforo: 'vencido' | 'proximo' | 'ok';
  expandido: boolean;
}

@Component({
  selector: 'app-mantenimiento-equipos',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './mantenimiento-equipos.component.html',
  styleUrls: ['./mantenimiento-equipos.component.css'],
})
export class MantenimientoEquiposComponent implements OnInit {
  private svc = inject(EquipoIntervenidoService);
  private opsSvc = inject(OperacionesService);
  private toast = inject(ToastService);
  private router = inject(Router);

  equipos: any[] = [];
  isLoading = true;
  errorMessage: string | null = null;

  busqueda = '';
  filtroEstado = '';
  vistaParque = false;

  // ── Modal de alta/edición ──────────────────────────────────────────────
  mostrarModal = false;
  guardando = false;
  editando: any = null;
  clientes: any[] = [];
  ubicaciones: any[] = [];
  zonas: any[] = [];
  tiposEquipo: any[] = [];
  form: any = this.formVacio();

  private formVacio() {
    return {
      nombre: '', cliente_id: '', ubicacion_id: '', zona_id: '',
      area_descripcion: '', tipo_equipo_id: '', marca: '', modelo: '',
      numero_serie: '', frecuencia_meses: 6, estado: 'operativo', observaciones: '',
    };
  }

  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.isLoading = true;
    this.errorMessage = null;
    this.svc.listar().subscribe({
      next: (data) => { this.equipos = data || []; this.isLoading = false; },
      error: () => {
        this.errorMessage = 'Error de conexión con el servidor.';
        this.isLoading = false;
      },
    });
  }

  irAMapa(): void { this.router.navigate(['/operaciones/mantenimiento/mapa']); }
  irADetalle(id: string): void { this.router.navigate(['/operaciones/mantenimiento', id]); }

  // ── Filtro / orden (cliente-side, sobre la lista ya cargada) ────────────
  get filtrados(): any[] {
    const term = this.busqueda.toLowerCase().trim();
    const lista = this.equipos.filter(e => {
      const matchTerm = !term ||
        (e.nombre || '').toLowerCase().includes(term) ||
        (e.cliente_nombre || '').toLowerCase().includes(term) ||
        (e.ubicacion_nombre || '').toLowerCase().includes(term) ||
        (e.zona_nombre || '').toLowerCase().includes(term) ||
        (e.codigo || '').toLowerCase().includes(term);
      const matchEstado = !this.filtroEstado || e.estado === this.filtroEstado;
      return matchTerm && matchEstado;
    });
    return lista.sort((a, b) => {
      const da = this.diasParaMantenimiento(a);
      const db = this.diasParaMantenimiento(b);
      if (da === null && db === null) return (a.nombre || '').localeCompare(b.nombre || '');
      if (da === null) return 1;
      if (db === null) return -1;
      return da - db;
    });
  }

  get hayFiltros(): boolean { return !!(this.busqueda || this.filtroEstado); }
  limpiarFiltros(): void { this.busqueda = ''; this.filtroEstado = ''; }

  // ── Semáforo de mantenimiento ────────────────────────────────────────────
  diasParaMantenimiento(e: any): number | null {
    if (!e.proximo_mantenimiento) return null;
    const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    const prox = new Date(e.proximo_mantenimiento + 'T00:00:00');
    return Math.round((prox.getTime() - hoy.getTime()) / 86400000);
  }

  estadoSemaforo(e: any): 'vencido' | 'proximo' | 'ok' | 'sin_plan' {
    const d = this.diasParaMantenimiento(e);
    if (d === null) return 'sin_plan';
    if (d < 0) return 'vencido';
    if (d <= 30) return 'proximo';
    return 'ok';
  }

  textoSemaforo(e: any): string {
    const d = this.diasParaMantenimiento(e);
    if (d === null) return 'Sin plan';
    if (d < 0) return `Mant. vencido hace ${Math.abs(d)} d`;
    if (d === 0) return 'Mant. hoy';
    return `Mant. en ${d} d`;
  }

  estadoClass(estado: string): string {
    const map: Record<string, string> = {
      operativo: 'estado-operativo', mantenimiento: 'estado-mtto',
      inoperativo: 'estado-inoperativo', en_revision: 'estado-revision',
    };
    return map[estado] ?? 'estado-operativo';
  }

  estadoLabel(estado: string): string {
    const map: Record<string, string> = {
      operativo: 'Operativo', mantenimiento: 'Mantenimiento',
      inoperativo: 'Inoperativo', en_revision: 'En Revisión',
    };
    return map[estado] ?? estado;
  }

  ubicacionCompleta(e: any): string {
    return [e.cliente_nombre, e.ubicacion_nombre, e.zona_nombre, e.area_nombre]
      .filter(Boolean).join(' › ') || '—';
  }

  get kpis() {
    const total = this.equipos.length;
    const vencidos = this.equipos.filter(e => this.estadoSemaforo(e) === 'vencido').length;
    const proximos = this.equipos.filter(e => this.estadoSemaforo(e) === 'proximo').length;
    const operativos = this.equipos.filter(e => e.estado === 'operativo').length;
    return { total, vencidos, proximos, operativos };
  }

  // ── Vista Parque: agrupado por ubicación → zona ──────────────────────────
  get gruposParque(): GrupoUbicacion[] {
    const porUbicacion = new Map<string, Map<string, any[]>>();
    for (const e of this.filtrados) {
      const ubi = e.ubicacion_nombre || 'Sin ubicación';
      const zona = e.zona_nombre || 'Sin zona';
      if (!porUbicacion.has(ubi)) porUbicacion.set(ubi, new Map());
      const porZona = porUbicacion.get(ubi)!;
      if (!porZona.has(zona)) porZona.set(zona, []);
      porZona.get(zona)!.push(e);
    }
    const semaforoDe = (equipos: any[]): 'vencido' | 'proximo' | 'ok' => {
      if (equipos.some(e => this.estadoSemaforo(e) === 'vencido')) return 'vencido';
      if (equipos.some(e => this.estadoSemaforo(e) === 'proximo')) return 'proximo';
      return 'ok';
    };
    const grupos: GrupoUbicacion[] = [];
    for (const [ubicacion, porZona] of porUbicacion) {
      const zonas: GrupoZona[] = [];
      const todosDeUbicacion: any[] = [];
      for (const [zona, equipos] of porZona) {
        zonas.push({ zona, equipos, semaforo: semaforoDe(equipos) });
        todosDeUbicacion.push(...equipos);
      }
      grupos.push({
        ubicacion, zonas, total: todosDeUbicacion.length,
        semaforo: semaforoDe(todosDeUbicacion), expandido: false,
      });
    }
    return grupos.sort((a, b) => a.ubicacion.localeCompare(b.ubicacion));
  }

  toggleGrupo(g: GrupoUbicacion): void { g.expandido = !g.expandido; }

  // ── Modal alta/edición ────────────────────────────────────────────────
  abrirCrear(): void {
    this.editando = null;
    this.form = this.formVacio();
    this.cargarCatalogos();
    this.mostrarModal = true;
  }

  abrirEditar(e: any): void {
    this.editando = e;
    this.form = {
      nombre: e.nombre || '', cliente_id: e.cliente_id || '', ubicacion_id: e.ubicacion_id || '',
      zona_id: e.zona_id || '', area_descripcion: e.area_descripcion || '',
      tipo_equipo_id: e.tipo_equipo_id || '', marca: e.marca || '', modelo: e.modelo || '',
      numero_serie: e.numero_serie || '', frecuencia_meses: e.frecuencia_meses || 6,
      estado: e.estado || 'operativo', observaciones: e.observaciones || '',
    };
    this.cargarCatalogos();
    if (e.ubicacion_id) this.onUbicacionChange(e.ubicacion_id);
    this.mostrarModal = true;
  }

  cerrarModal(): void { this.mostrarModal = false; this.editando = null; }

  private cargarCatalogos(): void {
    this.opsSvc.getClientes().subscribe({ next: (r: any) => this.clientes = r || [] });
    this.opsSvc.getUbicaciones().subscribe({ next: (r: any) => this.ubicaciones = r || [] });
    this.opsSvc.getTiposEquipo().subscribe({ next: (r: any) => this.tiposEquipo = r || [] });
  }

  onUbicacionChange(ubicacionId: string): void {
    this.form.zona_id = '';
    this.zonas = [];
    if (!ubicacionId) return;
    this.opsSvc.getZonas(ubicacionId).subscribe({ next: (r: any) => this.zonas = r || [] });
  }

  guardar(): void {
    if (!this.form.nombre?.trim()) {
      this.toast.mostrar('El nombre es obligatorio.', 'error');
      return;
    }
    this.guardando = true;
    const body = { ...this.form };
    const obs = this.editando
      ? this.svc.actualizar(this.editando.id, body)
      : this.svc.crear(body);
    obs.subscribe({
      next: () => {
        this.guardando = false;
        this.mostrarModal = false;
        this.toast.mostrar(this.editando ? 'Equipo actualizado.' : 'Equipo creado.', 'success');
        this.cargar();
      },
      error: (err) => {
        this.guardando = false;
        const detalle = err?.error?.detail || 'No se pudo guardar el equipo.';
        this.toast.mostrar(detalle, 'error');
      },
    });
  }

  readonly ESTADOS = ESTADOS;
}
