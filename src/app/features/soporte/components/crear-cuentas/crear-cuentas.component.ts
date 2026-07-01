import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { UsuariosService, UsuarioOut, RolOut, CrearUsuarioIn } from '../../../../core/services/usuarios.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

@Component({
  selector: 'app-crear-cuentas',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './crear-cuentas.component.html',
  styleUrls: ['./crear-cuentas.component.css'],
})
export class CrearCuentasComponent implements OnInit, OnDestroy {
  private svc = inject(UsuariosService);
  private mainEl: HTMLElement | null = null;
  private modalCount = 0;

  // Lista
  usuarios: UsuarioOut[] = [];
  roles: RolOut[]        = [];
  cargando = true;

  // Filtro + paginación
  busqueda    = '';
  pagina      = 1;
  porPagina   = 8;

  // Modal crear
  showModal = false;
  guardando = false;
  errorMsg  = '';
  form: CrearUsuarioIn = this.formVacio();

  // Modal cambiar rol
  showRolModal  = false;
  rolTarget: UsuarioOut | null = null;
  nuevoRolId    = '';
  cambiandoRol  = false;

  // Modal toggle activo
  showToggleModal = false;
  toggleTarget: UsuarioOut | null = null;
  toggling = false;

  // Modal reset password
  showResetModal  = false;
  resetTarget: UsuarioOut | null = null;
  resetandoPass   = false;
  resetMsg        = '';
  resetPwd        = '';
  resetConfirm    = '';
  resetDni        = '';
  resetShowPwd    = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  get usuariosFiltrados(): UsuarioOut[] {
    const q = this.busqueda.toLowerCase().trim();
    if (!q) return this.usuarios;
    return this.usuarios.filter(u =>
      u.nombre.toLowerCase().includes(q) ||
      u.apellido.toLowerCase().includes(q) ||
      (u.email ?? '').toLowerCase().includes(q) ||
      (u.username ?? '').toLowerCase().includes(q) ||
      (u.rol ?? '').toLowerCase().includes(q)
    );
  }

  get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.usuariosFiltrados.length / this.porPagina));
  }

  get usuariosPagina(): UsuarioOut[] {
    const ini = (this.pagina - 1) * this.porPagina;
    return this.usuariosFiltrados.slice(ini, ini + this.porPagina);
  }

  get paginasArray(): number[] {
    return Array.from({ length: this.totalPaginas }, (_, i) => i + 1);
  }

  get passwordPreview(): string {
    const dni   = (this.form.numero_documento ?? '').trim();
    const letra = (this.form.nombre ?? '').trim()[0]?.toUpperCase() ?? '';
    const anio  = new Date().getFullYear();
    if (!dni || !letra) return '—';
    return `${dni}${letra}${anio}`;
  }

  get resetPwdSugerida(): string {
    const dni   = this.resetDni.trim();
    const letra = (this.resetTarget?.nombre ?? '')[0]?.toUpperCase() ?? '';
    const anio  = new Date().getFullYear();
    if (!dni || !letra) return '';
    return `${dni}${letra}${anio}`;
  }

  get resetPwdStrength(): 'debil' | 'media' | 'fuerte' {
    const p = this.resetPwd;
    if (!p || p.length < 6) return 'debil';
    if (p.length >= 10 && /[A-Z]/.test(p) && /[0-9]/.test(p)) return 'fuerte';
    if (p.length >= 8) return 'media';
    return 'debil';
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  ngOnInit(): void {
    this.mainEl = document.querySelector('main');
    this.cargar();
    this.svc.getRoles().subscribe({ next: r => (this.roles = r) });
  }

  ngOnDestroy(): void {
    this._releaseMain();
  }

  // ── Stacking context fix ──────────────────────────────────────────────────
  private _lockMain(): void {
    this.modalCount++;
    if (this.mainEl && this.modalCount === 1) {
      this.mainEl.style.setProperty('isolation', 'auto');
      this.mainEl.style.setProperty('z-index', '1001');
    }
    document.body.style.overflow = 'hidden';
  }

  private _releaseMain(): void {
    this.modalCount = Math.max(0, this.modalCount - 1);
    if (this.mainEl && this.modalCount === 0) {
      this.mainEl.style.removeProperty('isolation');
      this.mainEl.style.removeProperty('z-index');
    }
    if (this.modalCount === 0) document.body.style.overflow = '';
  }

  // ── Datos ─────────────────────────────────────────────────────────────────
  cargar(): void {
    this.cargando = true;
    this.svc.listar().subscribe({
      next:  r  => { this.usuarios = r; this.cargando = false; },
      error: () => { this.cargando = false; },
    });
  }

  onFiltro(): void { this.pagina = 1; }
  irPagina(p: number): void { this.pagina = Math.min(Math.max(1, p), this.totalPaginas); }

  formVacio(): CrearUsuarioIn {
    return {
      nombre: '', apellido: '', email: '', username: '', password: '',
      rol_id: '', telefono: '', crear_ficha: true,
      cargo: '', area: '', tipo: 'planilla', codigo: '',
      tipo_documento: 'DNI', numero_documento: '', sexo: '', fecha_ingreso: '',
    };
  }

  // ── Modal crear ───────────────────────────────────────────────────────────
  abrirModal(): void {
    this.form     = this.formVacio();
    this.errorMsg = '';
    this.showModal = true;
    this._lockMain();
  }

  cerrarModal(): void {
    this.showModal = false;
    this._releaseMain();
  }

  sugerirUsername(): void {
    if (this.form.username) return;
    const n = this.form.nombre.trim().toLowerCase().replace(/\s+/g, '');
    const a = this.form.apellido.trim().toLowerCase().split(' ')[0];
    if (n && a) this.form.username = `${n}.${a}`;
  }

  onDniChange(): void {
    const dni   = (this.form.numero_documento ?? '').trim();
    const letra = (this.form.nombre ?? '').trim()[0]?.toUpperCase() ?? '';
    const anio  = new Date().getFullYear();
    if (dni && letra) this.form.password = `${dni}${letra}${anio}`;
  }

  guardar(): void {
    this.errorMsg = '';
    if (!this.form.nombre.trim() || !this.form.apellido.trim()) {
      this.errorMsg = 'Nombre y apellido son obligatorios.'; return;
    }
    if (!this.form.email.trim()) { this.errorMsg = 'El correo es obligatorio.'; return; }
    if (!this.form.username.trim()) { this.errorMsg = 'El nombre de usuario es obligatorio.'; return; }
    if (!this.form.rol_id) { this.errorMsg = 'Debes asignar un rol.'; return; }
    if (this.form.crear_ficha && !this.form.numero_documento?.trim()) {
      this.errorMsg = 'El número de documento es necesario para crear la ficha.'; return;
    }
    if (!this.form.password) {
      this.errorMsg = 'No se pudo calcular la contraseña. Verifica el DNI y nombre.'; return;
    }
    this.guardando = true;
    const body: CrearUsuarioIn = {
      ...this.form,
      nombre:           this.form.nombre.trim(),
      apellido:         this.form.apellido.trim(),
      email:            this.form.email.trim(),
      username:         this.form.username.trim(),
      fecha_ingreso:    this.form.fecha_ingreso || undefined,
      telefono:         this.form.telefono      || undefined,
      cargo:            this.form.cargo         || undefined,
      area:             this.form.area          || undefined,
      codigo:           this.form.codigo        || undefined,
      numero_documento: this.form.numero_documento || undefined,
      sexo:             this.form.sexo           || undefined,
    };
    this.svc.crear(body).subscribe({
      next: (u) => {
        this.usuarios = [u, ...this.usuarios];
        this.guardando = false;
        this.cerrarModal();
      },
      error: (err) => {
        this.errorMsg = err?.error?.detail ?? 'No se pudo crear la cuenta.';
        this.guardando = false;
      },
    });
  }

  // ── Modal cambio de rol ───────────────────────────────────────────────────
  abrirRolModal(u: UsuarioOut): void {
    this.rolTarget    = u;
    this.nuevoRolId   = u.rol_id ?? '';
    this.showRolModal = true;
    this._lockMain();
  }
  cerrarRolModal(): void { this.showRolModal = false; this.rolTarget = null; this._releaseMain(); }

  confirmarRol(): void {
    if (!this.rolTarget || !this.nuevoRolId || this.cambiandoRol) return;
    this.cambiandoRol = true;
    this.svc.cambiarRol(this.rolTarget.id, this.nuevoRolId).subscribe({
      next: (u) => {
        this.usuarios     = this.usuarios.map(x => x.id === u.id ? u : x);
        this.cambiandoRol = false;
        this.cerrarRolModal();
      },
      error: () => { this.cambiandoRol = false; },
    });
  }

  // ── Modal activar / desactivar ────────────────────────────────────────────
  abrirToggleModal(u: UsuarioOut): void {
    this.toggleTarget     = u;
    this.showToggleModal  = true;
    this._lockMain();
  }
  cerrarToggleModal(): void { this.showToggleModal = false; this.toggleTarget = null; this._releaseMain(); }

  confirmarToggle(): void {
    if (!this.toggleTarget || this.toggling) return;
    const u = this.toggleTarget;
    this.toggling = true;
    this.svc.cambiarActivo(u.id, !u.activo).subscribe({
      next: (updated) => {
        this.usuarios = this.usuarios.map(x => x.id === updated.id ? updated : x);
        this.toggling = false;
        this.cerrarToggleModal();
      },
      error: () => { this.toggling = false; },
    });
  }

  // ── Modal reset password ──────────────────────────────────────────────────
  abrirResetModal(u: UsuarioOut): void {
    this.resetTarget     = u;
    this.resetMsg        = '';
    this.resetPwd        = '';
    this.resetConfirm    = '';
    this.resetDni        = '';
    this.resetShowPwd    = false;
    this.showResetModal  = true;
    this._lockMain();
  }
  cerrarResetModal(): void { this.showResetModal = false; this.resetTarget = null; this._releaseMain(); }

  usarSugerida(): void {
    const s = this.resetPwdSugerida;
    if (s) { this.resetPwd = s; this.resetConfirm = s; }
  }

  confirmarReset(): void {
    if (!this.resetTarget || this.resetandoPass) return;
    this.resetMsg = '';
    if (!this.resetPwd) { this.resetMsg = 'Ingresa la nueva contraseña.'; return; }
    if (this.resetPwd.length < 6) { this.resetMsg = 'Mínimo 6 caracteres.'; return; }
    if (this.resetPwd !== this.resetConfirm) { this.resetMsg = 'Las contraseñas no coinciden.'; return; }
    this.resetandoPass = true;
    this.svc.resetPassword(this.resetTarget.id, this.resetPwd).subscribe({
      next: () => {
        this.resetandoPass = false;
        this.cerrarResetModal();
      },
      error: (err) => {
        this.resetMsg = err?.error?.detail ?? 'No se pudo restablecer.';
        this.resetandoPass = false;
      },
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  iniciales(u: UsuarioOut): string {
    return `${u.nombre[0] ?? ''}${u.apellido[0] ?? ''}`.toUpperCase();
  }

  minVal(a: number, b: number): number { return Math.min(a, b); }
}
