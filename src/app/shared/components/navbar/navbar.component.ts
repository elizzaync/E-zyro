import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { AuthService } from '../../../core/services/auth.service';
import { DashboardService } from '../../../core/services/dashboard.service';
import { ToastService } from '../../../core/services/toast.service';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';
import { ThemeService } from '../../../core/services/theme.service';
import { EvaluacionesService, Evaluacion, EmpleadoEval, CriterioEval } from '../../../core/services/evaluaciones.service';

@Component({
  selector: 'app-navbar',
  standalone: true,
  imports: [CommonModule, RouterModule, FormsModule],
  templateUrl: './navbar.component.html',
  styleUrls: ['./navbar.component.css']
})
export class NavbarComponent implements OnInit, OnDestroy {
  usuarioActual = { nombre: 'Cargando...', rol: '...', iniciales: '', id: 'EMP-0000', foto: '' };
  /** Nombre real del rol (del JWT), distinto del cargo de display en usuarioActual.rol */
  private rolNombre = '';

  /**
   * Subtitulo del navbar: "Panel de Gestion" + rol del usuario.
   * Mientras carga ("..." / "Cargando...") muestra solo "Panel de Gestion".
   */
  get isClienteExterno(): boolean {
    return this.rolNombre.toLowerCase().replace(/\s+/g, '') === 'clienteexterno';
  }

  get isTecnico(): boolean {
    return this.rolNombre.trim() === 'Técnico';
  }

  get isJefeOperaciones(): boolean {
    return this.rolNombre.trim() === 'Jefe de Operaciones';
  }

  get isLogistica(): boolean {
    return this.rolNombre.trim() === 'Logística';
  }

  get isAdministracion(): boolean {
    return this.rolNombre.trim() === 'Administración';
  }

  get isAdmin(): boolean {
    return this.rolNombre.trim() === 'Admin';
  }

  get isSoporte(): boolean {
    return this.rolNombre.trim() === 'Soporte';
  }

  /** Puede ver la sección Nube de Planos */
  get puedeVerPlanos(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones && !this.isLogistica && !this.isClienteExterno;
  }

  /** Puede ver Requerimientos y Compras en logística */
  get puedeVerLogisticaAvanzada(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones && !this.isClienteExterno;
  }

  /** Puede ver Salidas en logística */
  get puedeVerSalidas(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones && !this.isClienteExterno;
  }

  get panelSubtitulo(): string {
    if (this.isClienteExterno) return 'Portal Cliente';
    const rol = (this.usuarioActual.rol || '').trim();
    if (!rol || rol === '...' || rol.toLowerCase().startsWith('cargando')) {
      return 'Panel de Gestión';
    }
    return `Panel de Gestión · ${rol}`;
  }

  /** Rol formateado para mostrar: "ClienteExterno" → "Cliente Externo" */
  get rolDisplay(): string {
    const r = (this.usuarioActual.rol || '').trim();
    if (!r || r === '...') return r;
    return r.replace(/([a-z])([A-Z])/g, '$1 $2');
  }
get puedeAdministrarRRHH(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones && !this.isLogistica && !this.isClienteExterno && !this.isAdministracion;
  }

  get puedeSoporte(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones && !this.isLogistica && !this.isClienteExterno && !this.isAdministracion && !this.isAdmin;
  }

  /** Solo el rol que tenga privilegios:gestionar puede ver Gestión de Permisos */
  get puedeGestionarPermisos(): boolean {
    return this.permisosUsuario.map(p => p.toUpperCase()).includes('PRIVILEGIOS');
  }

  get enSoporte(): boolean {
    return this.router.url.startsWith('/soporte');
  }

  get enAdministracion(): boolean {
    return this.router.url.startsWith('/administracion');
  }

  get puedeAdministracion(): boolean {
    return this.isAdministracion || this.isAdmin || this.isSoporte;
  }

get enRRHH(): boolean {
    return this.router.url.startsWith('/rrhh');
  }
  isMenuOpen = false;
  operacionesOpen = false;
  logisticaOpen = false;
  rrhhOpen = false;
  soporteOpen = false;
  administracionOpen = false;
  /** Drawer de navegación en móvil/tablet (hamburguesa) */
  mobileNavOpen = false;
  showProfileModal = false;
  isEditingProfile = false;
  permisosUsuario: string[] = [];

  showNotifPanel = false;
  notificaciones: any[] = [];
  private notiSub!: Subscription;

  perfilData = {
    nombre: '',
    apellido: '',
    correo: '',
    telefono: '',
    rol: '',
    empresa: '',
    empresaId: '',
    ruc: '',
    ubicacion: 'Cargando...',
    fechaCreacion: '',
    fotoUrl: '',
    // Datos no editables del trabajador.
    dni: '',
    tipoDocumento: 'DNI',
    sexo: ''
  };

  /** Etiqueta legible del sexo (campo de solo lectura). */
  get sexoLabel(): string {
    const s = (this.perfilData.sexo || '').toUpperCase();
    if (s === 'M') return 'Masculino';
    if (s === 'F') return 'Femenino';
    return '—';
  }

  perfilDataBackup: any = null; // Variable para guardar los datos originales

  iniciarEdicion() {
    this.isEditingProfile = true;
    // Hacemos una copia exacta de los datos antes de editar
    this.perfilDataBackup = { ...this.perfilData };
  }

  cancelarEdicion() {
    this.isEditingProfile = false;
    // Si cancela, restauramos la copia original
    if (this.perfilDataBackup) {
      this.perfilData = { ...this.perfilDataBackup };
    }
  }

  // ... resto de tu código (cargarDatosDeUsuario, etc.) ...
  // ── Ver mis evaluaciones ──────────────────────────────────────────────────
  showEvalModal   = false;
  misEvaluaciones: Evaluacion[] = [];
  cargandoEvals   = false;
  evalDetalle: Evaluacion | null = null;
  cargandoDetalle = false;

  // ── Crear evaluación ──────────────────────────────────────────────────────
  showCrearEvalModal = false;
  crearPaso: 1 | 2 | 3 = 1;
  crearTipo = '';
  crearPeriodo = '';
  crearFecha = '';
  crearDestinatarios: 'todos' | 'seleccion' = 'todos';
  crearBusquedaEmp = '';
  crearEmpleadosSeleccionados: string[] = [];
  crearCriteriosSeleccionados: string[] = [];
  cev3AddOpen = false;
  cev3Nombre = '';
  cev3Peso = 1;
  cev3Guardando = false;
  creandoEval = false;
  crearResultado: { creadas: number } | null = null;

  personal: EmpleadoEval[] = [];
  cargandoPersonal = false;
  criteriosDisponibles: CriterioEval[] = [];
  cargandoCriterios = false;

  readonly tiposEval = [
    { key: 'companero',   label: 'Compañerismo',  desc: 'Evalúa trabajo en equipo y relaciones interpersonales', emoji: '🤝' },
    { key: 'rrhh',        label: 'Conocimiento',  desc: 'Evalúa competencias técnicas y desempeño laboral',       emoji: '📚' },
    { key: 'psicologico', label: 'Psicológica',   desc: 'Evalúa bienestar emocional y aptitudes psicológicas',    emoji: '🧠' },
  ];

  get personalFiltrado(): EmpleadoEval[] {
    const q = this.crearBusquedaEmp.toLowerCase().trim();
    if (!q) return this.personal;
    return this.personal.filter(e =>
      (e.nombre ?? '').toLowerCase().includes(q) ||
      (e.cargo  ?? '').toLowerCase().includes(q)
    );
  }

  abrirCrearEval(): void {
    this.isMenuOpen = false;
    this.showCrearEvalModal = true;
    this.crearPaso = 1;
    this.crearTipo = '';
    const hoy = new Date();
    const meses = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
                   'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    this.crearPeriodo = `${meses[hoy.getMonth()]} ${hoy.getFullYear()}`;
    this.crearFecha   = hoy.toISOString().slice(0, 10);
    this.crearDestinatarios = 'todos';
    this.crearBusquedaEmp = '';
    this.crearEmpleadosSeleccionados = [];
    this.crearCriteriosSeleccionados = [];
    this.crearResultado = null;
    document.body.style.overflow = 'hidden';

    if (this.personal.length === 0) {
      this.cargandoPersonal = true;
      this.evalSvc.getPersonal().subscribe({
        next: (r) => { this.personal = r; this.cargandoPersonal = false; },
        error: ()  => { this.cargandoPersonal = false; },
      });
    }
  }

  cerrarCrearEval(): void {
    this.showCrearEvalModal = false;
    document.body.style.overflow = '';
  }

  seleccionarTipoEval(key: string): void {
    this.crearTipo = key;
    this.criteriosDisponibles = [];
    this.crearCriteriosSeleccionados = [];
    this.cev3AddOpen = false;
    this.cev3Nombre = '';
    this.cev3Peso = 1;
    this.cargandoCriterios = true;
    this.evalSvc.getCriterios(key).subscribe({
      next: (r) => { this.criteriosDisponibles = r; this.cargandoCriterios = false; },
      error: ()  => { this.cargandoCriterios = false; },
    });
  }

  agregarCev3Criterio(): void {
    if (!this.cev3Nombre.trim() || this.cev3Peso <= 0 || this.cev3Guardando || !this.crearTipo) return;
    this.cev3Guardando = true;
    this.evalSvc.crearCriterio({ nombre: this.cev3Nombre.trim(), peso: this.cev3Peso, tipo: this.crearTipo }).subscribe({
      next: (c) => {
        this.criteriosDisponibles = [...this.criteriosDisponibles, c];
        this.crearCriteriosSeleccionados = [...this.crearCriteriosSeleccionados, c.id];
        if (this.gcTab === this.crearTipo) this.gcCriterios = [...this.gcCriterios, c];
        this.cev3Nombre = '';
        this.cev3Peso = 1;
        this.cev3AddOpen = false;
        this.cev3Guardando = false;
      },
      error: () => { this.cev3Guardando = false; },
    });
  }

  eliminarCev3Criterio(id: string): void {
    if (this.gcEliminando) return;
    this.gcEliminando = id;
    this.evalSvc.eliminarCriterio(id).subscribe({
      next: () => {
        this.criteriosDisponibles = this.criteriosDisponibles.filter(c => c.id !== id);
        this.crearCriteriosSeleccionados = this.crearCriteriosSeleccionados.filter(x => x !== id);
        this.gcCriterios = this.gcCriterios.filter(c => c.id !== id);
        this.gcEliminando = null;
      },
      error: () => { this.gcEliminando = null; },
    });
  }

  siguientePaso(): void {
    if (this.crearPaso === 1 && !this.crearTipo) return;
    if (this.crearPaso === 1 && !this.crearPeriodo.trim()) return;
    if (this.crearPaso < 3) this.crearPaso = (this.crearPaso + 1) as 1 | 2 | 3;
  }

  anteriorPaso(): void {
    if (this.crearPaso > 1) this.crearPaso = (this.crearPaso - 1) as 1 | 2 | 3;
  }

  toggleEmpleado(id: string): void {
    const idx = this.crearEmpleadosSeleccionados.indexOf(id);
    if (idx >= 0) this.crearEmpleadosSeleccionados.splice(idx, 1);
    else this.crearEmpleadosSeleccionados.push(id);
  }

  toggleCriterio(id: string): void {
    const idx = this.crearCriteriosSeleccionados.indexOf(id);
    if (idx >= 0) this.crearCriteriosSeleccionados.splice(idx, 1);
    else this.crearCriteriosSeleccionados.push(id);
  }

  enviarEvaluaciones(): void {
    if (!this.crearTipo || !this.crearPeriodo.trim()) return;
    if (this.crearDestinatarios === 'seleccion' && this.crearEmpleadosSeleccionados.length === 0) return;

    this.creandoEval = true;
    this.evalSvc.crearLote({
      tipo:         this.crearTipo,
      periodo:      this.crearPeriodo.trim(),
      fecha:        this.crearFecha || null,
      todos:        this.crearDestinatarios === 'todos',
      empleado_ids: this.crearDestinatarios === 'seleccion' ? this.crearEmpleadosSeleccionados : [],
      criterio_ids: this.crearCriteriosSeleccionados,
    }).subscribe({
      next: (r) => {
        this.creandoEval = false;
        this.crearResultado = { creadas: r.creadas };
        this.misEvaluaciones = [];
        this.toastService.mostrar(`✓ ${r.creadas} evaluación(es) enviadas correctamente.`, 'success');
      },
      error: () => {
        this.creandoEval = false;
        this.toastService.mostrar('Error al crear las evaluaciones.', 'error');
      },
    });
  }

  // ── Gestionar criterios ───────────────────────────────────────────────────
  showGcModal = false;
  gcTab: 'companero' | 'rrhh' | 'psicologico' = 'companero';
  gcCriterios: CriterioEval[] = [];
  gcCargando = false;
  gcNombre = '';
  gcPeso = 1;
  gcGuardando = false;
  gcEliminando: string | null = null;

  abrirGcModal(): void {
    this.isMenuOpen = false;
    this.showGcModal = true;
    document.body.style.overflow = 'hidden';
    this.gcTab = 'companero';
    this.cargarGcCriterios();
  }

  cerrarGcModal(): void {
    this.showGcModal = false;
    document.body.style.overflow = '';
    this.gcNombre = '';
    this.gcPeso = 1;
  }

  cambiarGcTab(tab: 'companero' | 'rrhh' | 'psicologico'): void {
    this.gcTab = tab;
    this.gcNombre = '';
    this.gcPeso = 1;
    this.cargarGcCriterios();
  }

  cargarGcCriterios(): void {
    this.gcCargando = true;
    this.evalSvc.getCriterios(this.gcTab).subscribe({
      next: (r) => { this.gcCriterios = r; this.gcCargando = false; },
      error: ()  => { this.gcCargando = false; },
    });
  }

  agregarGcCriterio(): void {
    if (!this.gcNombre.trim() || this.gcPeso <= 0 || this.gcGuardando) return;
    this.gcGuardando = true;
    this.evalSvc.crearCriterio({ nombre: this.gcNombre.trim(), peso: this.gcPeso, tipo: this.gcTab }).subscribe({
      next: (c) => {
        this.gcCriterios = [...this.gcCriterios, c];
        this.gcNombre = '';
        this.gcPeso = 1;
        this.gcGuardando = false;
        if (this.gcTab === this.crearTipo) {
          this.criteriosDisponibles = [...this.criteriosDisponibles, c];
        }
      },
      error: () => { this.gcGuardando = false; },
    });
  }

  eliminarGcCriterio(id: string): void {
    if (this.gcEliminando) return;
    this.gcEliminando = id;
    this.evalSvc.eliminarCriterio(id).subscribe({
      next: () => {
        this.gcCriterios = this.gcCriterios.filter(c => c.id !== id);
        this.criteriosDisponibles = this.criteriosDisponibles.filter(c => c.id !== id);
        this.crearCriteriosSeleccionados = this.crearCriteriosSeleccionados.filter(x => x !== id);
        this.gcEliminando = null;
      },
      error: () => { this.gcEliminando = null; },
    });
  }

  tipoEvalLabel(t: string): string {
    return { rrhh: 'RRHH', jefe_directo: 'Jefe Directo', companero: 'Compañero' }[t] ?? t;
  }

  estadoEvalLabel(e: string): string {
    return { borrador: 'Borrador', enviada: 'Enviada', completada: 'Completada' }[e] ?? e;
  }

  promedioColor(p: number | null): string {
    if (p === null) return '#9ca3af';
    if (p >= 8)  return '#10b981';
    if (p >= 6)  return '#f59e0b';
    return '#ef4444';
  }

  abrirModalEvaluaciones(): void {
    this.isMenuOpen = false;
    this.showEvalModal = true;
    this.evalDetalle = null;
    document.body.style.overflow = 'hidden';
    if (this.misEvaluaciones.length === 0) {
      this.cargandoEvals = true;
      this.evalSvc.getMisEvaluaciones().subscribe({
        next: (r) => { this.misEvaluaciones = r; this.cargandoEvals = false; },
        error: ()  => { this.cargandoEvals = false; },
      });
    }
  }

  cerrarModalEvaluaciones(): void {
    this.showEvalModal = false;
    this.evalDetalle   = null;
    document.body.style.overflow = '';
  }

  abrirDetalleEval(ev: Evaluacion): void {
    if (this.evalDetalle?.id === ev.id) { this.evalDetalle = null; return; }
    this.cargandoDetalle = true;
    this.evalSvc.getDetalle(ev.id).subscribe({
      next: (r) => { this.evalDetalle = r; this.cargandoDetalle = false; },
      error: ()  => { this.cargandoDetalle = false; },
    });
  }

  constructor(
    private authService: AuthService,
    private dashboardService: DashboardService,
    private toastService: ToastService,
    private router: Router,
    private portalService: PortalClienteService,
    private themeService: ThemeService,
    private evalSvc: EvaluacionesService,
  ) {}

  /** True cuando la ruta actual pertenece al módulo de Logística. */
  get enLogistica(): boolean {
    return this.router.url.startsWith('/logistica');
  }

  /** True cuando la ruta actual pertenece al módulo de Operaciones. */
  get enOperaciones(): boolean {
    return this.router.url.startsWith('/operaciones');
  }

  /** Admins ven la vista tabla completa de Operaciones (incluye Proyectos). */
  get esVistaTablaOperaciones(): boolean {
    return !this.isTecnico && !this.isJefeOperaciones && !this.isLogistica && !this.isClienteExterno && this.rolNombre !== '...';
  }

  private notiInitialized = false;

  ngOnInit(): void {
    this.cargarDatosDeUsuario();
    this.inicializarTema();
    this.notiSub = this.dashboardService.notificaciones$.subscribe(lista => {
      const prevCount = this.notificaciones.length;
      this.notificaciones = lista;

      if (!this.notiInitialized) {
        this.notiInitialized = true;
        return;
      }

      if (lista.length > prevCount) {
        const nueva = lista[0];
        if (nueva) {
          this.toastService.mostrar(`${nueva.titulo}: ${nueva.mensaje}`, 'info');
        }
      }
    });
  }

  ngOnDestroy(): void {
    this.notiSub?.unsubscribe();
  }

  toggleMenu() { this.isMenuOpen = !this.isMenuOpen; }
  cerrarMenu() { this.isMenuOpen = false; }

  /** Hamburguesa: abre/cierra el drawer de navegación en móvil. */
  toggleMobileNav() {
    this.mobileNavOpen = !this.mobileNavOpen;
    this.isMenuOpen = false;
    if (!this.mobileNavOpen) { this.operacionesOpen = false; this.logisticaOpen = false; this.rrhhOpen = false; this.soporteOpen = false; this.administracionOpen = false; }
  }
  /** Cierra el drawer móvil (al elegir una opción o tocar fuera). */
  cerrarMobileNav() {
    this.mobileNavOpen = false;
    this.operacionesOpen = false;
    this.logisticaOpen = false;
    this.rrhhOpen = false;
    this.soporteOpen = false;
    this.administracionOpen = false;
  }

  toggleNotifPanel() {
    this.showNotifPanel = !this.showNotifPanel;
    if (this.isMenuOpen) this.isMenuOpen = false;
  }

  cerrarNotifPanel() { this.showNotifPanel = false; }

  ignorarNotif(id: string, event: MouseEvent) {
    event.stopPropagation();
    this.dashboardService.ignorarNotificacion(id).subscribe({
      next: () => {
        this.notificaciones = this.notificaciones.filter(n => n.id !== id);
        this.dashboardService.notificaciones$.next(this.notificaciones);
      }
    });
  }

  cerrarSesion() {
    this.isMenuOpen = false;
    this.authService.solicitarCerrarSesion();
  }

  cargarDatosDeUsuario(): void {
    // Cargar rol inmediatamente desde localStorage para que isClienteExterno
    // sea correcto en el primer render, antes de que responda la API.
    const userDataString = localStorage.getItem('ezyro_user');
    if (userDataString) {
      const u = JSON.parse(userDataString);
      this.usuarioActual.nombre    = u.nombre_completo || 'Usuario';
      this.usuarioActual.rol       = u.rol             || '';
      this.usuarioActual.iniciales = this.usuarioActual.nombre.substring(0, 2).toUpperCase();
      // rolNombre siempre viene del token JWT (login), nunca del cargo de display
      this.rolNombre = (u.rol || '').trim();
    }

    // ClienteExterno: cargar datos de empresa/usuario desde el endpoint de portal
    if (this.isClienteExterno) {
      this.portalService.getPortalPerfil().subscribe({
        next: (p: any) => {
          this.usuarioActual.nombre    = `${p.nombre} ${p.apellido}`.trim() || this.usuarioActual.nombre;
          this.usuarioActual.iniciales = this.generarIniciales(p.nombre, p.apellido);
          this.usuarioActual.foto      = p.fotoUrl || '';
          this.perfilData = {
            nombre:        p.nombre,
            apellido:      p.apellido,
            correo:        p.correo,
            telefono:      p.telefono,
            rol:           p.rol,
            empresa:       p.empresa,
            empresaId:     this.usuarioActual.id,
            ruc:           p.ruc,
            ubicacion:     p.empresaEmail || '—',
            fechaCreacion: p.fechaCreacion,
            fotoUrl:       p.fotoUrl,
            dni:           '',
            tipoDocumento: 'DNI',
            sexo:          '',
          };
        },
        error: () => { /* sin toast — datos básicos ya están en localStorage */ }
      });
      return;
    }

    this.dashboardService.getPerfilUsuario().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          const personal = res.data.personal;
          const empresa = res.data.empresa;
          this.permisosUsuario = personal.permisos_modulo || [];
          localStorage.setItem('ezyro_permisos', JSON.stringify(this.permisosUsuario));

          // rol_nombre = nombre del rol real (JWT), personal.rol = cargo de display
          if (personal.rol_nombre) {
            this.rolNombre = (personal.rol_nombre as string).trim();
          }
          this.usuarioActual = {
            nombre: `${personal.nombre} ${personal.apellido}`,
            rol: personal.rol,
            iniciales: this.generarIniciales(personal.nombre, personal.apellido),
            id: personal.id.split('-')[0].toUpperCase() + '-USR',
            foto: personal.fotoUrl
          };

          this.perfilData = {
            nombre: personal.nombre,
            apellido: personal.apellido,
            correo: personal.correo,
            telefono: personal.telefono || '',
            rol: personal.rol,
            empresa: empresa.nombre,
            // 👇 AQUÍ PROTEGEMOS A ANGULAR CONTRA ERRORES
            empresaId: empresa.id ? empresa.id.substring(0,8).toUpperCase() : 'SIN-ID',
            ruc: empresa.ruc,
            ubicacion: empresa.ubicacion,
            fechaCreacion: personal.fechaCreacion,
            fotoUrl: personal.fotoUrl,
            // Datos no editables del trabajador.
            dni: personal.dni || '',
            tipoDocumento: personal.tipoDocumento || 'DNI',
            sexo: personal.sexo || ''
          };
        }
      },
      error: (err) => {
        console.error(err);
        // El portal cliente no tiene acceso al perfil interno — suprimir el toast.
        if (this.isClienteExterno) return;

        // Error transitorio (status 0 = red/cold-start de Railway, ya reintentado
        // por el interceptor): el login SÍ tuvo éxito y los datos básicos ya están
        // en localStorage, así que no alarmamos. El perfil se recargará al navegar.
        if (!err || err.status === 0) return;

        // Solo mostramos la alerta ante un error real del servidor.
        this.toastService.mostrar('Error al conectar con el servidor', 'error');
      }
    });
  }

  abrirModalPerfil() {
    this.isMenuOpen = false;
    this.isEditingProfile = false;
    this.showProfileModal = true;
    document.body.style.overflow = 'hidden';
  }

  cerrarModalPerfil() {
    this.showProfileModal = false;
    this.isEditingProfile = false;
    document.body.style.overflow = '';
  }

  onFileSelected(event: any) {
    const file = event.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (e: any) => {
        this.perfilData.fotoUrl = e.target.result;
      };
      reader.readAsDataURL(file);
    }
  }

  guardarPerfil() {
    const datosParaEnviar = {
      nombre: this.perfilData.nombre || '',
      apellido: this.perfilData.apellido || '',
      telefono: this.perfilData.telefono || '',
      fotoBase64: this.perfilData.fotoUrl && this.perfilData.fotoUrl.startsWith('data:image')
                  ? this.perfilData.fotoUrl : null
    };

    this.dashboardService.actualizarPerfil(datosParaEnviar).subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.usuarioActual.nombre = `${this.perfilData.nombre} ${this.perfilData.apellido}`;
          this.usuarioActual.iniciales = this.generarIniciales(this.perfilData.nombre, this.perfilData.apellido);

          if (res.foto_url) {
            this.usuarioActual.foto = res.foto_url;
            this.perfilData.fotoUrl = res.foto_url;
          }

          // AVISAMOS AL HOME EN TIEMPO REAL DEL NUEVO NOMBRE
          this.dashboardService.notificarPerfilActualizado(this.perfilData.nombre);

          // ACTUALIZAMOS EL CACHÉ DEL NAVEGADOR
          const userDataString = localStorage.getItem('ezyro_user');
          if (userDataString) {
            const userData = JSON.parse(userDataString);
            userData.nombre_completo = this.usuarioActual.nombre;
            localStorage.setItem('ezyro_user', JSON.stringify(userData));
          }

          this.isEditingProfile = false;
          this.toastService.mostrar('¡Perfil actualizado con éxito!', 'success');
        }
      },
      error: (err) => {
        console.error(err);
        this.toastService.mostrar('Error al actualizar el perfil', 'error');
      }
    });
  }

  generarIniciales(nombre: string, apellido: string): string {
    const inicialNombre = nombre ? nombre.charAt(0).toUpperCase() : '';
    const inicialApellido = apellido ? apellido.charAt(0).toUpperCase() : '';
    return (inicialNombre + inicialApellido) || 'U';
  }

  inicializarTema() { this.themeService.init(); }

  alternarTema() { this.themeService.toggle(); }

}