import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { UsuariosService, UsuarioOut, RolOut, CrearUsuarioIn } from '../../../../core/services/usuarios.service';

@Component({
  selector: 'app-crear-cuentas',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './crear-cuentas.component.html',
  styleUrls: ['./crear-cuentas.component.css'],
})
export class CrearCuentasComponent implements OnInit {
  private svc = inject(UsuariosService);

  // Lista
  usuarios: UsuarioOut[] = [];
  roles: RolOut[]        = [];
  cargando = true;

  // Filtro
  busqueda = '';

  // Modal crear
  showModal  = false;
  guardando  = false;
  errorMsg   = '';

  form: CrearUsuarioIn = this.formVacio();

  // Modal cambiar rol
  showRolModal    = false;
  rolTarget: UsuarioOut | null = null;
  nuevoRolId      = '';
  cambiandoRol    = false;

  // Modal reset password
  showResetModal     = false;
  resetTarget: UsuarioOut | null = null;
  resetandoPass      = false;
  resetMsg           = '';

  // Modal toggle activo
  toggleTarget: UsuarioOut | null = null;
  toggling                        = false;

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

  get passwordPreview(): string {
    const dni   = (this.form.numero_documento ?? '').trim();
    const letra = (this.form.nombre ?? '').trim()[0]?.toUpperCase() ?? '';
    const anio  = new Date().getFullYear();
    if (!dni || !letra) return '—';
    return `${dni}${letra}${anio}`;
  }

  ngOnInit(): void {
    this.cargar();
    this.svc.getRoles().subscribe({ next: r => (this.roles = r) });
  }

  cargar(): void {
    this.cargando = true;
    this.svc.listar().subscribe({
      next:  r  => { this.usuarios = r; this.cargando = false; },
      error: () => { this.cargando = false; },
    });
  }

  formVacio(): CrearUsuarioIn {
    return {
      nombre: '', apellido: '', email: '', username: '', password: '',
      rol_id: '', telefono: '', crear_ficha: true,
      cargo: '', area: '', tipo: 'planilla', codigo: '',
      tipo_documento: 'DNI', numero_documento: '', sexo: '', fecha_ingreso: '',
    };
  }

  abrirModal(): void {
    this.form     = this.formVacio();
    this.errorMsg = '';
    this.showModal = true;
    document.body.style.overflow = 'hidden';
  }

  cerrarModal(): void {
    this.showModal = false;
    document.body.style.overflow = '';
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
    if (!this.form.username.trim()) { this.errorMsg = 'El usuario es obligatorio.'; return; }
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
      telefono:         this.form.telefono || undefined,
      cargo:            this.form.cargo    || undefined,
      area:             this.form.area     || undefined,
      codigo:           this.form.codigo   || undefined,
      numero_documento: this.form.numero_documento || undefined,
      sexo:             this.form.sexo     || undefined,
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

  // ── Cambio de rol ────────────────────────────────────────────────────────
  abrirRolModal(u: UsuarioOut): void {
    this.rolTarget  = u;
    this.nuevoRolId = u.rol_id ?? '';
    this.showRolModal = true;
    document.body.style.overflow = 'hidden';
  }
  cerrarRolModal(): void { this.showRolModal = false; this.rolTarget = null; document.body.style.overflow = ''; }

  confirmarRol(): void {
    if (!this.rolTarget || !this.nuevoRolId || this.cambiandoRol) return;
    this.cambiandoRol = true;
    this.svc.cambiarRol(this.rolTarget.id, this.nuevoRolId).subscribe({
      next: (u) => {
        this.usuarios = this.usuarios.map(x => x.id === u.id ? u : x);
        this.cambiandoRol = false; this.cerrarRolModal();
      },
      error: () => { this.cambiandoRol = false; },
    });
  }

  // ── Reset password ───────────────────────────────────────────────────────
  abrirResetModal(u: UsuarioOut): void {
    this.resetTarget = u;
    this.resetMsg    = '';
    this.showResetModal = true;
    document.body.style.overflow = 'hidden';
  }
  cerrarResetModal(): void { this.showResetModal = false; this.resetTarget = null; document.body.style.overflow = ''; }

  confirmarReset(): void {
    if (!this.resetTarget || this.resetandoPass) return;
    const u = this.resetTarget;
    // Recalcula la contraseña original con los datos del usuario
    const letra = u.nombre[0]?.toUpperCase() ?? 'X';
    const anio  = new Date().getFullYear();
    // Sin DNI almacenado en el UsuarioOut, usamos un placeholder visible
    this.resetMsg = `La contraseña de ${u.nombre} ${u.apellido} será restablecida al valor original (DNI + inicial + año). Confirma en el campo abajo.`;
  }

  resetConPassword(pwd: string): void {
    if (!this.resetTarget || !pwd.trim() || this.resetandoPass) return;
    this.resetandoPass = true;
    this.svc.resetPassword(this.resetTarget.id, pwd.trim()).subscribe({
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

  // ── Toggle activo ────────────────────────────────────────────────────────
  toggleActivo(u: UsuarioOut): void {
    if (this.toggling) return;
    this.toggling = true;
    this.svc.cambiarActivo(u.id, !u.activo).subscribe({
      next: (updated) => {
        this.usuarios = this.usuarios.map(x => x.id === updated.id ? updated : x);
        this.toggling = false;
      },
      error: () => { this.toggling = false; },
    });
  }

  iniciales(u: UsuarioOut): string {
    return `${(u.nombre[0] ?? '')}${(u.apellido[0] ?? '')}`.toUpperCase();
  }
}
