import { Component, OnInit, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';

// ─── Types ─────────────────────────────────────────────────────────────────
export type EstadoEquipo =
  | 'operativo'
  | 'en_mantenimiento'
  | 'fuera_de_servicio'
  | 'pendiente';

export interface EquipoZona {
  id: number;
  codigo: string;
  nombre: string;
  tipo: string;
  ultimoMantenimiento: string | null;
  estado: EstadoEquipo;
  seleccionado: boolean;
}

export interface ZonaInfo {
  id: string;
  nombre: string;
  ciudad: string;
  region: string;
  tecnico?: string;
  fecha?: string;
}

// ─── Mock zone info ─────────────────────────────────────────────────────────
const ZONA_INFO: Record<string, ZonaInfo> = {
  trujillo:     { id: 'trujillo',   nombre: 'Sede Norte',       ciudad: 'Trujillo',    region: 'La Libertad', tecnico: 'Carlos Vargas',  fecha: '24 May 2026' },
  iquitos:      { id: 'iquitos',    nombre: 'Base Amazónica',   ciudad: 'Iquitos',     region: 'Loreto',      tecnico: 'Miguel Ríos',    fecha: '24 May 2026' },
  loreto:       { id: 'loreto',     nombre: 'Sede Loretana',    ciudad: 'Yurimaguas',  region: 'Loreto',                                 fecha: '25 May 2026' },
  'lima-norte': { id: 'lima-norte', nombre: 'Planta Lima Norte',ciudad: 'Los Olivos',  region: 'Lima',        tecnico: 'Sandra Mejía',   fecha: '23 May 2026' },
  callao:       { id: 'callao',     nombre: 'Puerto Industrial', ciudad: 'Callao',     region: 'Callao',      tecnico: 'Karla Flores',   fecha: '22 May 2026' },
};

// ─── Mock equipment per zone ────────────────────────────────────────────────
const EQUIPOS: Record<string, EquipoZona[]> = {
  trujillo: [
    { id: 1, codigo: 'EQ-TRU-001', nombre: 'Compresor Atlas Copco GA-15',  tipo: 'Compresor',      ultimoMantenimiento: '2026-04-10', estado: 'operativo',          seleccionado: false },
    { id: 2, codigo: 'EQ-TRU-002', nombre: 'Generador Kohler 20REOZJB',    tipo: 'Generador',      ultimoMantenimiento: '2026-03-22', estado: 'en_mantenimiento',   seleccionado: false },
    { id: 3, codigo: 'EQ-TRU-003', nombre: 'Bomba Hidráulica BH-5000',     tipo: 'Bomba',          ultimoMantenimiento: '2026-02-14', estado: 'fuera_de_servicio',  seleccionado: false },
    { id: 4, codigo: 'EQ-TRU-004', nombre: 'UPS Eaton 5kVA',               tipo: 'UPS',            ultimoMantenimiento: null,         estado: 'pendiente',          seleccionado: false },
    { id: 5, codigo: 'EQ-TRU-005', nombre: 'Tablero Eléctrico TE-01',       tipo: 'Eléctrico',     ultimoMantenimiento: '2026-05-01', estado: 'operativo',          seleccionado: false },
    { id: 6, codigo: 'EQ-TRU-006', nombre: 'Pozo a Tierra PT-001',          tipo: 'Puesta a tierra',ultimoMantenimiento: '2026-04-28', estado: 'operativo',         seleccionado: false },
    { id: 7, codigo: 'EQ-TRU-007', nombre: 'Extintor CO2 5 kg',             tipo: 'Seguridad',     ultimoMantenimiento: null,         estado: 'pendiente',          seleccionado: false },
  ],
  iquitos: [
    { id: 101, codigo: 'EQ-IQT-001', nombre: 'Aire Acondicionado Daikin 24K', tipo: 'HVAC',          ultimoMantenimiento: '2026-03-15', estado: 'en_mantenimiento',  seleccionado: false },
    { id: 102, codigo: 'EQ-IQT-002', nombre: 'Servidor Dell PowerEdge R350',  tipo: 'Servidor',      ultimoMantenimiento: '2026-04-20', estado: 'operativo',         seleccionado: false },
    { id: 103, codigo: 'EQ-IQT-003', nombre: 'Switch Cisco SG250-26',         tipo: 'Red',           ultimoMantenimiento: '2026-01-09', estado: 'fuera_de_servicio', seleccionado: false },
    { id: 104, codigo: 'EQ-IQT-004', nombre: 'Panel Solar 200W ×8',           tipo: 'Energía Solar', ultimoMantenimiento: null,         estado: 'fuera_de_servicio', seleccionado: false },
  ],
  loreto: [],   // ← empty state demo
  'lima-norte': [
    { id: 201, codigo: 'EQ-LIM-001', nombre: 'Montacargas Toyota 8FBE15',    tipo: 'Montacargas', ultimoMantenimiento: '2026-05-10', estado: 'operativo',  seleccionado: false },
    { id: 202, codigo: 'EQ-LIM-002', nombre: 'Compresor de Tornillo 7.5HP',  tipo: 'Compresor',   ultimoMantenimiento: '2026-04-05', estado: 'operativo',  seleccionado: false },
    { id: 203, codigo: 'EQ-LIM-003', nombre: 'Grupo Electrógeno 15 kW',       tipo: 'Generador',   ultimoMantenimiento: null,         estado: 'pendiente',  seleccionado: false },
  ],
  callao: [
    { id: 301, codigo: 'EQ-CAL-001', nombre: 'Puente Grúa 5 T',               tipo: 'Izaje',      ultimoMantenimiento: '2026-05-01', estado: 'operativo',  seleccionado: false },
    { id: 302, codigo: 'EQ-CAL-002', nombre: 'Bomba Centrífuga BC-3000',       tipo: 'Bomba',      ultimoMantenimiento: '2026-04-25', estado: 'operativo',  seleccionado: false },
    { id: 303, codigo: 'EQ-CAL-003', nombre: 'Transformador 250 kVA',          tipo: 'Eléctrico',  ultimoMantenimiento: '2026-04-10', estado: 'operativo',  seleccionado: false },
    { id: 304, codigo: 'EQ-CAL-004', nombre: 'Compresor Atlas GA-22',          tipo: 'Compresor',  ultimoMantenimiento: '2026-03-28', estado: 'operativo',  seleccionado: false },
    { id: 305, codigo: 'EQ-CAL-005', nombre: 'UPS APC Smart-UPS 10 kVA',      tipo: 'UPS',        ultimoMantenimiento: '2026-04-15', estado: 'operativo',  seleccionado: false },
    { id: 306, codigo: 'EQ-CAL-006', nombre: 'Aire Acondicionado 5 T',         tipo: 'HVAC',       ultimoMantenimiento: '2026-04-30', estado: 'operativo',  seleccionado: false },
  ],
};

// ─── Component ─────────────────────────────────────────────────────────────
@Component({
  selector: 'app-equipos-zona',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './equipos-zona.component.html',
  styleUrl: './equipos-zona.component.css',
})
export class EquiposZonaComponent implements OnInit {
  private route    = inject(ActivatedRoute);
  private location = inject(Location);

  servicioId: string | null = null;
  zonaId: string | null = null;
  zona: ZonaInfo | null = null;
  equipos: EquipoZona[] = [];
  isLoading = true;

  // report
  generandoReporte = false;
  reporteToast     = false;

  // ─── Lifecycle ───────────────────────────────────────────────────────────
  ngOnInit(): void {
    this.servicioId = this.route.snapshot.paramMap.get('id');
    this.zonaId     = this.route.snapshot.paramMap.get('zonaId');

    setTimeout(() => {
      if (this.zonaId) {
        this.zona   = ZONA_INFO[this.zonaId]   ?? { id: this.zonaId, nombre: 'Zona desconocida', ciudad: '—', region: '—' };
        this.equipos = (EQUIPOS[this.zonaId] ?? []).map(e => ({ ...e }));
      }
      this.isLoading = false;
    }, 900);
  }

  // ─── Navigation ──────────────────────────────────────────────────────────
  volver(): void { this.location.back(); }

  // ─── Selection helpers ───────────────────────────────────────────────────
  get seleccionados(): EquipoZona[] {
    return this.equipos.filter(e => e.seleccionado);
  }

  get todosSeleccionados(): boolean {
    return this.equipos.length > 0 && this.equipos.every(e => e.seleccionado);
  }

  get algunoSeleccionado(): boolean {
    const s = this.seleccionados.length;
    return s > 0 && s < this.equipos.length;
  }

  toggleTodos(): void {
    const v = !this.todosSeleccionados;
    this.equipos.forEach(e => (e.seleccionado = v));
  }

  deseleccionarTodo(): void {
    this.equipos.forEach(e => (e.seleccionado = false));
  }

  // ─── Stats ───────────────────────────────────────────────────────────────
  contar(estado: EstadoEquipo): number {
    return this.equipos.filter(e => e.estado === estado).length;
  }

  // ─── Labels ──────────────────────────────────────────────────────────────
  estadoLabel(estado: EstadoEquipo): string {
    return {
      operativo:          'Operativo',
      en_mantenimiento:   'En mantenimiento',
      fuera_de_servicio:  'Fuera de servicio',
      pendiente:          'Pendiente',
    }[estado];
  }

  // ─── Report ──────────────────────────────────────────────────────────────
  generarReporte(soloSeleccionados = false): void {
    const lista = soloSeleccionados ? this.seleccionados : this.equipos;
    if (!lista.length) return;

    this.generandoReporte = true;

    // Construye CSV
    const header = ['Código', 'Nombre', 'Tipo', 'Último mantenimiento', 'Estado'];
    const rows = lista.map(e => [
      e.codigo,
      `"${e.nombre}"`,
      e.tipo,
      e.ultimoMantenimiento ?? 'Sin registro',
      this.estadoLabel(e.estado),
    ]);

    const csv = [header, ...rows].map(r => r.join(',')).join('\n');
    const meta = [
      `Zona: ${this.zona?.nombre ?? ''} — ${this.zona?.ciudad ?? ''}`,
      `Servicio ID: ${this.servicioId ?? '—'}`,
      `Fecha reporte: ${new Date().toLocaleDateString('es-PE', { day: '2-digit', month: 'long', year: 'numeric' })}`,
      `Técnico responsable: ${this.zona?.tecnico ?? 'No asignado'}`,
      '',
    ].join('\n');

    const blob = new Blob(['﻿' + meta + csv], { type: 'text/csv;charset=utf-8;' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = `reporte-equipos-${this.zonaId ?? 'zona'}-${Date.now()}.csv`;
    a.click();
    URL.revokeObjectURL(url);

    this.generandoReporte = false;
    this.reporteToast     = true;
    setTimeout(() => (this.reporteToast = false), 3200);
  }
}
