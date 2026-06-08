import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { AuthService } from '../../../core/services/auth.service';
import { DashboardService } from '../../../core/services/dashboard.service';
import { ToastService } from '../../../core/services/toast.service';
import { PortalClienteService } from '../../../core/services/portal-cliente.service';

@Component({
  selector: 'app-navbar',
  standalone: true,
  imports: [CommonModule, RouterModule, FormsModule],
  templateUrl: './navbar.component.html',
  styleUrls: ['./navbar.component.css']
})
export class NavbarComponent implements OnInit, OnDestroy {
  usuarioActual = { nombre: 'Cargando...', rol: '...', iniciales: '', id: 'EMP-0000', foto: '' };

  /**
   * Subtitulo del navbar: "Panel de Gestion" + rol del usuario.
   * Mientras carga ("..." / "Cargando...") muestra solo "Panel de Gestion".
   */
  get isClienteExterno(): boolean {
    return (this.usuarioActual.rol || '').toLowerCase().replace(/\s+/g, '') === 'clienteexterno';
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

  isMenuOpen = false;
  logisticaOpen = false;
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
    fotoUrl: ''
  };

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
  constructor(
    private authService: AuthService,
    private dashboardService: DashboardService,
    private toastService: ToastService,
    private router: Router,
    private portalService: PortalClienteService,
  ) {}

  /** True cuando la ruta actual pertenece al módulo de Logística. */
  get enLogistica(): boolean {
    return this.router.url.startsWith('/logistica');
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
            fotoUrl: personal.fotoUrl
          };
        }
      },
      error: (err) => {
        // El portal cliente no tiene acceso al perfil interno — suprimir el toast
        if (!this.isClienteExterno) {
          console.error(err);
          this.toastService.mostrar('Error al conectar con el servidor', 'error');
        }
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

  inicializarTema() {
    const t = localStorage.getItem('ezyro_tema');
    if (t) document.documentElement.setAttribute('data-theme', t);
  }

  alternarTema() {
    const html = document.documentElement;
    const nuevo = html.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    html.setAttribute('data-theme', nuevo);
    localStorage.setItem('ezyro_tema', nuevo);
  }

}