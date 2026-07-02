import { Component, Input, Output, EventEmitter, OnInit, AfterViewInit, ViewChild, ElementRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LogisticaService } from '../../../../core/services/logistica.service';
import { OperacionesService } from '../../../../core/services/operaciones.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { AppModalComponent } from '../../../../shared/components/modal/app-modal.component';
import { Epp, EppEntregaItemIn } from '../../logistica.models';

interface TecnicoOpt {
  id: string;
  nombre: string;
  cargo: string;
}

interface ItemSeleccionado {
  eppId: string;
  nombre: string;
  stockDisponible: number;
  cantidad: number;
}

@Component({
  selector: 'app-epp-entrega-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent, AppModalComponent],
  templateUrl: './epp-entrega-modal.component.html',
  styleUrls: ['./epp-entrega-modal.component.css'],
})
export class EppEntregaModalComponent implements OnInit, AfterViewInit {
  @Input() epps: Epp[] = [];
  @Output() registrada = new EventEmitter<void>();
  @Output() cerrar     = new EventEmitter<void>();

  @ViewChild('firmaCanvas') firmaCanvasEl?: ElementRef<HTMLCanvasElement>;

  private svc          = inject(LogisticaService);
  private operaciones  = inject(OperacionesService);
  private toast        = inject(ToastService);

  tecnicos: TecnicoOpt[] = [];
  empleadoId = '';

  buscarItem = '';
  seleccionados: ItemSeleccionado[] = [];

  observacion = '';
  hayFirma = false;
  private _dibujando = false;

  guardando = false;

  ngOnInit(): void {
    document.body.style.overflow = 'hidden';
    this.operaciones.getPersonalTecnicos().subscribe({
      next: (r: any) => {
        this.tecnicos = (r?.tecnicos ?? []).map((t: any) => ({
          id: t.id,
          nombre: `${t.nombre} ${t.apellido ?? ''}`.trim(),
          cargo: t.cargo,
        }));
      },
      error: () => {},
    });
  }

  ngAfterViewInit(): void {
    this._initCanvas();
  }

  get eppsFiltrados(): Epp[] {
    const q = this.buscarItem.toLowerCase().trim();
    const yaSel = new Set(this.seleccionados.map(s => s.eppId));
    return this.epps.filter(e => !yaSel.has(e.id) && (!q || e.nombre.toLowerCase().includes(q)));
  }

  agregarItem(e: Epp): void {
    if (e.stock_actual <= 0) {
      this.toast.mostrar(`"${e.nombre}" no tiene stock disponible.`, 'error');
      return;
    }
    this.seleccionados.push({ eppId: e.id, nombre: e.nombre, stockDisponible: e.stock_actual, cantidad: 1 });
    this.buscarItem = '';
  }

  quitarItem(it: ItemSeleccionado): void {
    this.seleccionados = this.seleccionados.filter(s => s.eppId !== it.eppId);
  }

  ajustarCantidad(it: ItemSeleccionado, valor: number): void {
    let n = Math.floor(valor);
    if (n < 1) n = 1;
    if (n > it.stockDisponible) n = it.stockDisponible;
    it.cantidad = n;
  }

  // ── Firma (canvas) ──────────────────────────────────────────────────────
  private _initCanvas(): void {
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (!canvas) return;
    const ctx = canvas.getContext('2d')!;
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';

    const getPos = (e: MouseEvent | Touch) => {
      const r = canvas.getBoundingClientRect();
      return { x: (e.clientX - r.left) * (canvas.width / r.width), y: (e.clientY - r.top) * (canvas.height / r.height) };
    };

    canvas.onmousedown = e => { this._dibujando = true; this.hayFirma = true; const p = getPos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
    canvas.onmousemove = e => { if (!this._dibujando) return; const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); };
    canvas.onmouseup = canvas.onmouseleave = () => { this._dibujando = false; };
    canvas.ontouchstart = e => { e.preventDefault(); this._dibujando = true; this.hayFirma = true; const p = getPos(e.touches[0]); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
    canvas.ontouchmove  = e => { e.preventDefault(); if (!this._dibujando) return; const p = getPos(e.touches[0]); ctx.lineTo(p.x, p.y); ctx.stroke(); };
    canvas.ontouchend   = () => { this._dibujando = false; };
  }

  limpiarFirma(): void {
    const canvas = this.firmaCanvasEl?.nativeElement;
    if (canvas) canvas.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height);
    this.hayFirma = false;
  }

  // ── Guardar ──────────────────────────────────────────────────────────────
  onGuardar(): void {
    if (!this.empleadoId) {
      this.toast.mostrar('Selecciona el técnico que recibe.', 'error');
      return;
    }
    if (this.seleccionados.length === 0) {
      this.toast.mostrar('Agrega al menos un ítem a entregar.', 'error');
      return;
    }
    const items: EppEntregaItemIn[] = this.seleccionados.map(s => ({ epp_id: s.eppId, cantidad: s.cantidad }));
    const canvas = this.firmaCanvasEl?.nativeElement;
    const firma = this.hayFirma && canvas ? canvas.toDataURL('image/png').split(',')[1] : null;

    this.guardando = true;
    this.svc.crearEntregaEpp({
      empleado_id: this.empleadoId,
      items,
      firma_base64: firma,
      observacion: this.observacion.trim() || null,
    }).subscribe({
      next: () => {
        this.guardando = false;
        this.toast.mostrar('Entrega de EPP registrada correctamente.', 'success');
        this.registrada.emit();
      },
      error: (err) => {
        this.guardando = false;
        this.toast.mostrar(err?.error?.detail ?? 'Error al registrar la entrega.', 'error');
      },
    });
  }
}
