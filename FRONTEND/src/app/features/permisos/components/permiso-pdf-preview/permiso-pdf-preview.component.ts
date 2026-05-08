import { Component, Input, ViewChild, ElementRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { PreviewData } from '../permiso-form/permiso-form.component';

export interface EmpleadoInfo {
  nombre: string;
  cargo:  string;
  area:   string;
}

const TIPOS_PERMISO = [
  { id: 'permiso_personal',         label: 'Permiso personal',            num: 1 },
  { id: 'comision_trabajo',         label: 'Comisión de Trabajo',         num: 2 },
  { id: 'cita_essalud',             label: 'Cita Essalud / Clínica',      num: 3 },
  { id: 'permanencia_capacitacion', label: 'Permanencia Capacitación',    num: 4 },
  { id: 'permanencia_extra',        label: 'Permanencia Extra (H)',       num: 5 },
  { id: 'recuperacion',             label: 'Recuperación (H)',            num: 6 },
  { id: 'vacaciones',               label: 'Vacaciones',                  num: 7 },
  { id: 'dias_libres',              label: 'Día(s) Libre(s)',             num: 8 },
  { id: 'transferencia',            label: 'Transferencia',               num: 9 },
  { id: 'otros',                    label: 'Otros',                       num: 10 },
];

@Component({
  selector: 'app-permiso-pdf-preview',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './permiso-pdf-preview.component.html',
  styleUrls: ['./permiso-pdf-preview.component.css']
})
export class PermisoPdfPreviewComponent {
  @Input() previewData:  PreviewData | null = null;
  @Input() empleadoInfo: EmpleadoInfo       = { nombre: '', cargo: 'PRACTICANTE', area: 'TI' };

  @ViewChild('a4Paper') a4PaperRef!: ElementRef<HTMLElement>;

  readonly tiposGrid = TIPOS_PERMISO.slice(0, 9);
  readonly tipoOtros = TIPOS_PERMISO[9];

  get todayStr(): string {
    return new Date().toLocaleDateString('es-PE', {
      day: '2-digit', month: '2-digit', year: 'numeric'
    });
  }

  isSelected(tipoId: string): boolean {
    return this.previewData?.tipo === tipoId;
  }

  mostrarHorario(): boolean {
    return ['permiso_personal', 'dias_libres', 'cita_essalud',
            'permanencia_extra', 'permanencia_capacitacion', 'recuperacion']
      .includes(this.previewData?.tipo ?? '');
  }
}
