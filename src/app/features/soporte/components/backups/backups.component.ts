import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SoporteService, BackupJobDto, BackupConfigDto, BackupConfigEdit } from '../../../../core/services/soporte.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';

@Component({
  selector: 'app-backups',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './backups.component.html',
  styleUrls: ['./backups.component.css'],
})
export class BackupsComponent implements OnInit, OnDestroy {
  private svc   = inject(SoporteService);
  private toast = inject(ToastService);

  cargando = true;
  backups: BackupJobDto[] = [];
  total = 0;
  page = 1;
  pageSize = 20;
  filtroEstado = 'todos';

  config: BackupConfigDto | null = null;
  configAbierta = false;

  // Formulario de programación (se llena desde el GET, se guarda con PUT)
  form: BackupConfigEdit = {
    bdAuto: true, bdFrecuencia: 'diario', bdHora: '23:30',
    bdDiaSemana: 6, bdCorreo: true, archivosAuto: true,
  };
  guardandoConfig = false;
  readonly diasSemana = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  // ── Backup manual ──
  alcance: 'bd' | 'completo' = 'bd';
  generando = false;
  jobEnProceso: BackupJobDto | null = null;
  cancelando = false;
  private pollTimer: ReturnType<typeof setInterval> | null = null;

  descargandoId: string | null = null;

  ngOnInit(): void {
    this.cargar();
    this.cargarConfig();
  }

  private cargarConfig(): void {
    this.svc.getBackupConfig().subscribe({
      next: c => { this.config = c; this.aplicarConfigAlForm(c); },
      error: () => {},
    });
  }

  private aplicarConfigAlForm(c: BackupConfigDto): void {
    this.form = {
      bdAuto: c.bdAuto, bdFrecuencia: c.bdFrecuencia, bdHora: c.bdHora,
      bdDiaSemana: c.bdDiaSemana, bdCorreo: c.bdCorreo, archivosAuto: c.archivosAuto,
    };
  }

  guardarConfig(): void {
    if (this.guardandoConfig) return;
    this.guardandoConfig = true;
    this.svc.actualizarBackupConfig(this.form).subscribe({
      next: c => {
        this.guardandoConfig = false;
        this.config = c;
        this.aplicarConfigAlForm(c);
        this.configAbierta = false;
        this.toast.mostrar('Programación guardada. Aplica desde el próximo minuto.', 'success');
      },
      error: err => {
        this.guardandoConfig = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo guardar la programación.', 'error');
      },
    });
  }

  ngOnDestroy(): void { this.detenerPolling(); }

  cargar(): void {
    this.cargando = true;
    this.svc.getBackups(this.filtroEstado, this.page, this.pageSize).subscribe({
      next: r => {
        this.backups = r.items;
        this.total = r.total;
        this.cargando = false;
        // Si hay un job corriendo (auto o manual), seguirlo en vivo
        const activo = r.items.find(b => b.estado === 'pendiente' || b.estado === 'en_proceso');
        if (activo) this.iniciarPolling(activo.id);
      },
      error: () => { this.cargando = false; this.toast.mostrar('Error al cargar backups.', 'error'); },
    });
  }

  filtrar(): void { this.page = 1; this.cargar(); }
  get totalPaginas(): number { return Math.max(1, Math.ceil(this.total / this.pageSize)); }
  irPagina(p: number): void { if (p >= 1 && p <= this.totalPaginas) { this.page = p; this.cargar(); } }

  // ── Generar backup manual ──
  generarBackup(): void {
    if (this.generando) return;
    this.generando = true;
    this.svc.crearBackup(this.alcance).subscribe({
      next: job => {
        this.jobEnProceso = job;
        this.toast.mostrar(
          this.alcance === 'bd'
            ? 'Generando backup de base de datos…'
            : 'Generando backup completo (BD + archivos). Puede tardar varios minutos…',
          'info');
        this.iniciarPolling(job.id);
        this.cargar();
      },
      error: err => {
        this.generando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo iniciar el backup.', 'error');
      },
    });
  }

  private iniciarPolling(jobId: string): void {
    this.detenerPolling();
    this.pollTimer = setInterval(() => {
      this.svc.getBackup(jobId).subscribe({
        next: job => {
          this.jobEnProceso = job;
          if (job.estado === 'completado' || job.estado === 'fallido' || job.estado === 'cancelado') {
            this.detenerPolling();
            this.generando = false;
            this.cancelando = false;
            this.jobEnProceso = null;
            if (job.estado === 'completado') {
              this.toast.mostrar(`Backup listo — ${this.fmtBytes(job.tamanoBytes)}. Ya puedes descargarlo.`, 'success');
            } else if (job.estado === 'fallido') {
              this.toast.mostrar(`Backup fallido: ${job.errorDetalle ?? 'error desconocido'}`, 'error');
            } else {
              this.toast.mostrar('Backup cancelado.', 'info');
            }
            this.cargar();
          }
        },
        error: () => { this.detenerPolling(); this.generando = false; },
      });
    }, 3000);
  }

  private detenerPolling(): void {
    if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
  }

  // ── Cancelar ──
  cancelar(b: BackupJobDto): void {
    if (this.cancelando) return;
    this.cancelando = true;
    this.svc.cancelarBackup(b.id).subscribe({
      next: job => {
        // Si quedó cancelado de inmediato (estaba pendiente), cerrar aquí;
        // si sigue en_proceso, el polling detecta el estado final.
        if (job.estado === 'cancelado') {
          this.cancelando = false;
          this.generando = false;
          this.detenerPolling();
          this.jobEnProceso = null;
          this.toast.mostrar('Backup cancelado.', 'info');
          this.cargar();
        } else {
          this.toast.mostrar('Cancelando backup…', 'info');
        }
      },
      error: err => {
        this.cancelando = false;
        this.toast.mostrar(err?.error?.detail ?? 'No se pudo cancelar.', 'error');
      },
    });
  }

  // ── Descargar ──
  descargar(b: BackupJobDto): void {
    if (this.descargandoId) return;
    this.descargandoId = b.id;
    this.svc.descargarBackup(b.id).subscribe({
      next: blob => {
        this.descargandoId = null;
        // Nombre real del artefacto (extensión correcta, incl. .dump antiguos);
        // fallback: .sql para solo-BD, .tar.gz para paquetes
        const nombre = b.nombreArchivo ??
          `ezyro_backup_${b.nivel}_${(b.fechaInicio || '').slice(0, 10)}_${b.id.slice(0, 8)}` +
          (b.contenido === 'bd' ? '.sql' : '.tar.gz');
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = nombre; a.click();
        setTimeout(() => URL.revokeObjectURL(url), 5000);
        this.toast.mostrar('Descarga iniciada. Guárdalo en tu disco de respaldos y verifica el hash.', 'success');
      },
      error: err => {
        this.descargandoId = null;
        const detail = err?.error instanceof Blob ? 'El artefacto ya no está disponible. Genera un backup nuevo.' : (err?.error?.detail ?? 'Error al descargar.');
        this.toast.mostrar(detail, 'error');
      },
    });
  }

  copiarHash(b: BackupJobDto): void {
    if (!b.hashSha256) return;
    navigator.clipboard.writeText(b.hashSha256).then(
      () => this.toast.mostrar('Hash SHA-256 copiado.', 'success'),
      () => this.toast.mostrar('No se pudo copiar.', 'error'));
  }

  // ── Helpers presentación ──
  fmtBytes(n: number | null): string {
    if (!n) return '—';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0; let v = n;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return `${v.toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
  }

  fmtFecha(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short' }) + ' ' +
           d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' });
  }

  nivelLabel(n: string): string {
    const m: Record<string, string> = {
      bd_horario: 'BD · horario', bd_diario: 'BD · diario', bd_semanal: 'BD · semanal',
      archivos_incremental: 'Archivos · incremental', archivos_full: 'Archivos · completo',
      reconciliacion: 'Reconciliación',
    };
    return m[n] ?? n;
  }

  contenidoLabel(c: string): string {
    if (c === 'bd') return 'Base de datos';
    if (c.includes('bd')) return 'BD + PDFs + Cloudinary';
    return 'PDFs + Cloudinary';
  }

  estadoLabel(e: string): string {
    const m: Record<string, string> = {
      pendiente: 'Pendiente', en_proceso: 'En proceso',
      completado: 'Completado', fallido: 'Fallido', cancelado: 'Cancelado',
    };
    return m[e] ?? e;
  }
}
