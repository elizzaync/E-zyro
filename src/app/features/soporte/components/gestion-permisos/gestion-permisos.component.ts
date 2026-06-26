import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { PrivilegiosService, UsuarioPrivilegio, PermisoDetalle } from '../../../../core/services/privilegios.service';
import { ToastService } from '../../../../core/services/toast.service';

interface ModuloGroup {
  modulo: string;
  permisos: PermisoDetalle[];
}

@Component({
  selector: 'app-gestion-permisos',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './gestion-permisos.component.html',
  styleUrls: ['./gestion-permisos.component.css'],
})
export class GestionPermisosComponent implements OnInit {
  usuarios: UsuarioPrivilegio[] = [];
  usuariosFiltrados: UsuarioPrivilegio[] = [];
  busqueda = '';
  cargandoUsuarios = false;

  usuarioSeleccionado: UsuarioPrivilegio | null = null;
  permisos: PermisoDetalle[] = [];
  grupos: ModuloGroup[] = [];
  cargandoPermisos = false;

  procesando: Set<string> = new Set();
  guardandoTodo = false;

  readonly MODULO_LABELS: Record<string, string> = {
    activos_fijos:          'Activos Fijos',
    asistencia:             'Asistencia',
    auditoria:              'Auditoría',
    caja_chica:             'Caja Chica',
    calibracion:            'Calibración',
    catalogos:              'Catálogos',
    comunicados:            'Comunicados',
    conciliacion_bancaria:  'Conciliación Bancaria',
    contabilidad:           'Contabilidad',
    controlling:            'Controlling',
    correctivo:             'Correctivo',
    cxc:                    'Cuentas por Cobrar',
    cxp:                    'Cuentas por Pagar',
    dashboard:              'Dashboard',
    documentos_sst:         'Documentos SST',
    empleados:              'Personal / Empleados',
    epp:                    'EPP',
    equipo:                 'Equipo',
    equipo_intervenido:     'Equipos Intervenidos',
    evaluacion:             'Evaluaciones',
    eventos_contables:      'Eventos Contables',
    galeria:                'Galería',
    informe_servicio:       'Informe de Servicio',
    inventario:             'Inventario',
    inventario_valorizado:  'Inventario Valorizado',
    itse:                   'ITSE',
    observacion:            'Observaciones',
    planilla:               'Planilla',
    privilegios:            'Gestión de Permisos',
    proyectos:              'Proyectos',
    reportes:               'Reportes',
    requerimientos:         'Requerimientos',
    soporte:                'Soporte TIC',
    tributario:             'Tributario',
    usuarios:               'Usuarios',
    vacaciones:             'Vacaciones',
  };

  constructor(
    private svc: PrivilegiosService,
    private toast: ToastService,
  ) {}

  ngOnInit(): void {
    this.cargarUsuarios();
  }

  cargarUsuarios(): void {
    this.cargandoUsuarios = true;
    this.svc.listarUsuarios().subscribe({
      next: (u) => {
        this.usuarios = u;
        this.filtrarUsuarios();
        this.cargandoUsuarios = false;
      },
      error: () => {
        this.toast.mostrar('Error al cargar usuarios', 'error');
        this.cargandoUsuarios = false;
      },
    });
  }

  filtrarUsuarios(): void {
    const q = this.busqueda.toLowerCase().trim();
    this.usuariosFiltrados = q
      ? this.usuarios.filter(u =>
          `${u.nombre} ${u.apellido}`.toLowerCase().includes(q) ||
          (u.rol || '').toLowerCase().includes(q) ||
          u.username.toLowerCase().includes(q)
        )
      : [...this.usuarios];
  }

  seleccionar(u: UsuarioPrivilegio): void {
    if (this.usuarioSeleccionado?.id === u.id) return;
    this.usuarioSeleccionado = u;
    this.permisos = [];
    this.grupos = [];
    this.cargandoPermisos = true;
    this.svc.permisosUsuario(u.id).subscribe({
      next: (p) => {
        this.permisos = p;
        this.grupos = this.agrupar(p);
        this.cargandoPermisos = false;
      },
      error: () => {
        this.toast.mostrar('Error al cargar permisos', 'error');
        this.cargandoPermisos = false;
      },
    });
  }

  private agrupar(permisos: PermisoDetalle[]): ModuloGroup[] {
    const map = new Map<string, PermisoDetalle[]>();
    for (const p of permisos) {
      if (!map.has(p.modulo)) map.set(p.modulo, []);
      map.get(p.modulo)!.push(p);
    }
    return [...map.entries()].map(([m, ps]) => ({ modulo: m, permisos: ps }));
  }

  moduloLabel(modulo: string): string {
    return this.MODULO_LABELS[modulo] ?? modulo;
  }

  tieneAlgo(grupo: ModuloGroup): boolean {
    return grupo.permisos.some(p => p.via_rol || p.directo);
  }

  togglePermiso(p: PermisoDetalle): void {
    if (!this.usuarioSeleccionado || p.via_rol || this.procesando.has(p.id)) return;
    this.procesando.add(p.id);
    const accion$ = p.directo
      ? this.svc.revocarPermiso(this.usuarioSeleccionado.id, p.id)
      : this.svc.otorgarPermiso(this.usuarioSeleccionado.id, p.id);

    accion$.subscribe({
      next: () => {
        p.directo = !p.directo;
        // Actualizar contador en la lista de usuarios
        const u = this.usuarios.find(x => x.id === this.usuarioSeleccionado!.id);
        if (u) u.permisos_directos += p.directo ? 1 : -1;
        this.procesando.delete(p.id);
      },
      error: () => {
        this.toast.mostrar('Error al actualizar permiso', 'error');
        this.procesando.delete(p.id);
      },
    });
  }

  revocarTodos(): void {
    if (!this.usuarioSeleccionado || this.guardandoTodo) return;
    this.guardandoTodo = true;
    this.svc.revocarTodos(this.usuarioSeleccionado.id).subscribe({
      next: () => {
        this.permisos.forEach(p => { p.directo = false; });
        const u = this.usuarios.find(x => x.id === this.usuarioSeleccionado!.id);
        if (u) u.permisos_directos = 0;
        this.toast.mostrar('Permisos directos eliminados', 'success');
        this.guardandoTodo = false;
      },
      error: () => {
        this.toast.mostrar('Error al revocar permisos', 'error');
        this.guardandoTodo = false;
      },
    });
  }

  get directosActivos(): number {
    return this.permisos.filter(p => p.directo).length;
  }

  iniciales(nombre: string, apellido: string): string {
    return ((nombre?.[0] ?? '') + (apellido?.[0] ?? '')).toUpperCase() || 'U';
  }

  rolColor(rol: string | null): string {
    const map: Record<string, string> = {
      'Técnico':           '#3b82f6',
      'Jefe de Operaciones': '#8b5cf6',
      'Logística':         '#10b981',
      'Recursos Humanos':  '#f59e0b',
      'Administración':    '#ef4444',
      'Soporte':           '#64748b',
      'TI':                '#6366f1',
    };
    return map[rol ?? ''] ?? '#94a3b8';
  }
}
