import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { DashboardService } from '../../../../core/services/dashboard.service';
import { ToastService } from '../../../../core/services/toast.service';

@Component({
  selector: 'app-calendar-widget',
  standalone: true,
  imports: [CommonModule, FormsModule, SpinnerComponent],
  templateUrl: './calendar-widget.component.html',
  styleUrls: ['./calendar-widget.component.css']
})
export class CalendarWidgetComponent implements OnInit, OnDestroy {
  fechaVista = new Date();
  mesActual: string = '';
  diasSemana = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];
  private toastService = inject(ToastService);
  private router = inject(Router);

  diasMes: { num: number | null, isHoy: boolean, hasEvent: boolean, fechaStr: string, tooltipText: string }[] = [];
  notasGuardadas: { [fecha: string]: string } = {};
  diasConServicio: string[] = [];
  proximosEventos: any[] = [];

  // Modal nota
  showModal = false;
  diaSeleccionado: any = null;
  textoNota = '';

  // Modal servicio
  showServicioModal = false;
  serviciosDelDia: any[] = [];
  cargandoServicio = false;
  servicioModoNota = false;

  constructor(private dashboardService: DashboardService) {}

ngOnInit() {
    this.generarCalendario();
    this.dashboardService.refreshWidgets$.subscribe(() => {
      this.cargarDatosCalendario();
    });
  }

  ngOnDestroy() {
    document.body.style.overflow = '';
  }

  cargarDatosCalendario() {
    this.dashboardService.getCalendarioEventos().subscribe({
      next: (res: any) => {
        if (res.status === 'success') {
          this.proximosEventos = res.data.proximosEventos;
          this.notasGuardadas = res.data.notas;
          this.diasConServicio = res.data.diasConServicio;
          this.generarCalendario();
        }
      },
      error: (err) => console.error("Error cargando calendario", err)
    });
  }

  generarCalendario() {
    const hoy = new Date();
    const mes = this.fechaVista.getMonth();
    const anio = this.fechaVista.getFullYear();

    const meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    this.mesActual = `${meses[mes]} ${anio}`;

    const primerDia = new Date(anio, mes, 1).getDay();
    const diasEnMes = new Date(anio, mes + 1, 0).getDate();

    this.diasMes = [];

    for (let i = 0; i < primerDia; i++) {
      this.diasMes.push({ num: null, isHoy: false, hasEvent: false, fechaStr: '', tooltipText: '' });
    }

    for (let i = 1; i <= diasEnMes; i++) {
      const isHoy = (i === hoy.getDate() && mes === hoy.getMonth() && anio === hoy.getFullYear());

      const mStr = (mes + 1).toString().padStart(2, '0');
      const dStr = i.toString().padStart(2, '0');
      const fechaStr = `${anio}-${mStr}-${dStr}`;

      const nota = this.notasGuardadas[fechaStr];
      const tieneServicio = this.diasConServicio.includes(fechaStr);
      const hasEvent = !!nota || tieneServicio;

      // 👇 LÓGICA DEL TOOLTIP DINÁMICO
      let tooltipText = '';
      if (hasEvent) {
        if (tieneServicio && nota) {
            tooltipText = `📌 OT Programada\n📝 ${nota}`;
        } else if (tieneServicio) {
            tooltipText = `📌 OT Programada`;
        } else if (nota) {
            tooltipText = `📝 ${nota}`;
        }
      }

      this.diasMes.push({ num: i, isHoy, hasEvent, fechaStr, tooltipText });
    }
  }

  cambiarMes(delta: number) {
    this.fechaVista.setMonth(this.fechaVista.getMonth() + delta);
    this.generarCalendario();
  }

  abrirModal(dia: any) {
    if (!dia.num) return;
    this.diaSeleccionado = dia;

    if (this.diasConServicio.includes(dia.fechaStr)) {
      this.servicioModoNota = false;
      this.serviciosDelDia = [];
      this.cargandoServicio = true;
      this.showServicioModal = true;
      document.body.style.overflow = 'hidden';
      this.dashboardService.getDetalleServicioDia(dia.fechaStr).subscribe({
        next: (res: any) => {
          this.serviciosDelDia = res.data || [];
          this.cargandoServicio = false;
        },
        error: () => { this.cargandoServicio = false; }
      });
    } else {
      this.textoNota = this.notasGuardadas[dia.fechaStr] || '';
      this.showModal = true;
      document.body.style.overflow = 'hidden';
    }
  }

  cerrarModal() {
    this.showModal = false;
    this.diaSeleccionado = null;
    document.body.style.overflow = '';
  }

  cerrarServicioModal() {
    this.showServicioModal = false;
    this.servicioModoNota = false;
    this.serviciosDelDia = [];
    document.body.style.overflow = '';
  }

  abrirNotaDesdeServicio() {
    this.servicioModoNota = true;
    this.textoNota = this.notasGuardadas[this.diaSeleccionado.fechaStr] || '';
  }

  verEnOperaciones() {
    if (this.serviciosDelDia.length === 1) {
      this.router.navigate(['/operaciones/detalle', this.serviciosDelDia[0].id]);
    } else {
      this.router.navigate(['/operaciones'], {
        queryParams: { fecha: this.diaSeleccionado?.fechaStr }
      });
    }
    this.cerrarServicioModal();
  }

  eliminarNota() {
    this.textoNota = '';
    this.guardarNota();
  }

  guardarNota() {
    const textoLimpio  = this.textoNota.trim();
    const notaOriginal = this.notasGuardadas[this.diaSeleccionado.fechaStr];

    let mensajeToast = '';
    if (!textoLimpio && notaOriginal) {
      mensajeToast = 'Evento eliminado correctamente';
    } else if (textoLimpio && notaOriginal && textoLimpio !== notaOriginal) {
      mensajeToast = 'Evento actualizado correctamente';
    } else if (textoLimpio && !notaOriginal) {
      mensajeToast = 'Evento creado correctamente';
    } else {
      this.servicioModoNota ? (this.servicioModoNota = false) : this.cerrarModal();
      return;
    }

    this.dashboardService.guardarNotaCalendario(this.diaSeleccionado.fechaStr, this.textoNota).subscribe({
      next: () => {
        if (this.servicioModoNota) {
          this.servicioModoNota = false;
        } else {
          this.cerrarModal();
        }
        this.toastService.mostrar(mensajeToast, 'success');
        this.dashboardService.refreshWidgets$.next(true);
      },
      error: () => this.toastService.mostrar('Error al procesar el evento', 'error')
    });
  }
}