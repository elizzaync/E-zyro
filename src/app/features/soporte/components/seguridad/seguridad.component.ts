import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SoporteService, IpBloqueadaDto, SesionActivaDto, IpFrecuenteDto } from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

type TabSeguridad = 'ips' | 'sesiones';

interface ModalConfirm {
  open: boolean;
  titulo: string;
  subtitulo: string;
  accion: () => void;
}

@Component({
  selector: 'app-seguridad',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  templateUrl: './seguridad.component.html',
  styleUrls: ['./seguridad.component.css']
})
export class SeguridadComponent implements OnInit {
  private svc   = inject(SoporteService);
  private toast = inject(ToastService);

  tab: TabSeguridad = 'ips';
  cargando = false;

  // IPs bloqueadas
  ips: IpBloqueadaDto[] = [];
  ipsFrequentes: IpFrecuenteDto[] = [];
  mostrarHistorial = false;
  ipForm = { ip: '', motivo: '' };
  ipError = '';
  bloqueando = false;

  // Sesiones activas
  sesiones: SesionActivaDto[] = [];
  cargandoSesiones = false;
  cerrandoTodasId = '';

  // Modal de confirmación
  modal: ModalConfirm = {
    open: false,
    titulo: '',
    subtitulo: '',
    accion: () => {}
  };

  private readonly IP_REGEX = /^(\d{1,3}\.){3}\d{1,3}$|^([0-9a-fA-F:]+)$/;

  ngOnInit(): void {
    this.cargarIps();
    this.cargarIpsFrequentes();
  }

  setTab(t: TabSeguridad): void {
    this.tab = t;
    if (t === 'sesiones' && this.sesiones.length === 0) this.cargarSesiones();
    if (t === 'ips') { this.cargarIps(); this.cargarIpsFrequentes(); }
  }

  // ── IPs Bloqueadas ──────────────────────────────────────────────────────────

  cargarIps(): void {
    this.cargando = true;
    this.svc.getIpsBloqueadas(this.mostrarHistorial).subscribe({
      next: data => { this.ips = data; this.cargando = false; },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar IPs bloqueadas.', 'error'); }
    });
  }

  cargarIpsFrequentes(): void {
    this.svc.getIpsFrecuentes().subscribe({
      next: data => { this.ipsFrequentes = data; },
      error: () => {}
    });
  }

  seleccionarIpFrecuente(ip: string): void {
    this.ipForm.ip = ip;
    this.ipError = '';
    document.getElementById('input-ip')?.focus();
  }

  toggleHistorial(): void {
    this.mostrarHistorial = !this.mostrarHistorial;
    this.cargarIps();
  }

  validarIp(): boolean {
    if (!this.ipForm.ip.trim()) {
      this.ipError = 'La IP es obligatoria.';
      return false;
    }
    if (!this.IP_REGEX.test(this.ipForm.ip.trim())) {
      this.ipError = 'Formato de IP inválido. Ej: 192.168.1.1';
      return false;
    }
    // Validate IPv4 octets
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(this.ipForm.ip.trim())) {
      const partes = this.ipForm.ip.trim().split('.');
      if (partes.some(p => parseInt(p, 10) > 255)) {
        this.ipError = 'Cada octeto de la IP debe estar entre 0 y 255.';
        return false;
      }
    }
    this.ipError = '';
    return true;
  }

  bloquearIp(): void {
    if (!this.validarIp()) return;
    this.bloqueando = true;
    this.svc.bloquearIp({ ip: this.ipForm.ip.trim(), motivo: this.ipForm.motivo.trim() || undefined }).subscribe({
      next: () => {
        this.toast.mostrar(`IP ${this.ipForm.ip.trim()} bloqueada correctamente.`, 'success');
        this.ipForm = { ip: '', motivo: '' };
        this.bloqueando = false;
        this.cargarIps();
      },
      error: (err) => {
        this.bloqueando = false;
        const msg = err?.error?.detail || 'Error al bloquear la IP.';
        this.toast.mostrar(msg, 'error');
      }
    });
  }

  confirmarDesbloquear(ip: IpBloqueadaDto): void {
    this.modal = {
      open: true,
      titulo: 'Desbloquear IP',
      subtitulo: `¿Está seguro de desbloquear la IP ${ip.ip}? Volverá a poder acceder al sistema.`,
      accion: () => this.ejecutarDesbloquear(ip)
    };
    this.setMainModal(true);
  }

  private ejecutarDesbloquear(ip: IpBloqueadaDto): void {
    this.cerrarModal();
    this.svc.desbloquearIp(ip.id).subscribe({
      next: () => {
        this.toast.mostrar(`IP ${ip.ip} desbloqueada.`, 'success');
        this.cargarIps();
      },
      error: (err) => {
        const msg = err?.error?.detail || 'Error al desbloquear la IP.';
        this.toast.mostrar(msg, 'error');
      }
    });
  }

  // ── Sesiones Activas ────────────────────────────────────────────────────────

  cargarSesiones(): void {
    this.cargandoSesiones = true;
    this.svc.getSesionesActivas().subscribe({
      next: data => { this.sesiones = data; this.cargandoSesiones = false; },
      error: () => { this.cargandoSesiones = false; this.toast.mostrar('Error al cargar sesiones activas.', 'error'); }
    });
  }

  confirmarCerrarSesion(sesion: SesionActivaDto): void {
    this.modal = {
      open: true,
      titulo: 'Cerrar Sesión Remota',
      subtitulo: `¿Cerrar la sesión de ${sesion.usuario_nombre}? El usuario será desconectado inmediatamente de ese dispositivo.`,
      accion: () => this.ejecutarCerrarSesion(sesion)
    };
    this.setMainModal(true);
  }

  private ejecutarCerrarSesion(sesion: SesionActivaDto): void {
    this.cerrarModal();
    this.svc.cerrarSesionRemota(sesion.id).subscribe({
      next: () => {
        this.toast.mostrar(`Sesión de ${sesion.usuario_nombre} cerrada.`, 'success');
        this.cargarSesiones();
      },
      error: (err) => {
        const msg = err?.error?.detail || 'Error al cerrar la sesión.';
        this.toast.mostrar(msg, 'error');
      }
    });
  }

  confirmarCerrarTodasSesiones(sesion: SesionActivaDto): void {
    this.modal = {
      open: true,
      titulo: 'Cerrar TODAS las sesiones',
      subtitulo: `¿Cerrar todas las sesiones de ${sesion.usuario_nombre}? El usuario será desconectado de web y aplicativo móvil.`,
      accion: () => this.ejecutarCerrarTodas(sesion)
    };
    this.setMainModal(true);
  }

  private ejecutarCerrarTodas(sesion: SesionActivaDto): void {
    this.cerrarModal();
    this.cerrandoTodasId = sesion.usuario_id;
    this.svc.cerrarTodasSesiones(sesion.usuario_id).subscribe({
      next: (res) => {
        this.cerrandoTodasId = '';
        this.toast.mostrar(`Se cerraron ${res.cerradas} sesión(es) de ${sesion.usuario_nombre} (web + móvil).`, 'success');
        this.cargarSesiones();
      },
      error: (err) => {
        this.cerrandoTodasId = '';
        const msg = err?.error?.detail || 'Error al cerrar las sesiones.';
        this.toast.mostrar(msg, 'error');
      }
    });
  }

  plataforma(sesion: SesionActivaDto): 'Web' | 'Móvil' {
    return (sesion as any).plataforma ?? 'Web';
  }

  // ── Modal ───────────────────────────────────────────────────────────────────

  cerrarModal(): void {
    this.modal = { ...this.modal, open: false };
    this.setMainModal(false);
  }

  confirmarAccionModal(): void {
    this.modal.accion();
  }

  private setMainModal(open: boolean): void {
    const main = document.querySelector('main');
    if (!main) return;
    open ? main.classList.add('modal-open') : main.classList.remove('modal-open');
    document.body.style.overflow = open ? 'hidden' : '';
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  truncarUserAgent(ua: string | undefined): string {
    if (!ua) return '—';
    // Extract browser name from user agent string
    if (ua.includes('Chrome') && !ua.includes('Edg')) return 'Chrome';
    if (ua.includes('Edg')) return 'Edge';
    if (ua.includes('Firefox')) return 'Firefox';
    if (ua.includes('Safari') && !ua.includes('Chrome')) return 'Safari';
    if (ua.includes('OPR') || ua.includes('Opera')) return 'Opera';
    return ua.length > 40 ? ua.substring(0, 40) + '…' : ua;
  }

  trackIp(_: number, ip: IpBloqueadaDto): string { return ip.id; }
  trackSesion(_: number, s: SesionActivaDto): string { return s.id; }
}
