import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

interface Solicitud {
  id: string;
  tipo: string;
  fechaEmision: string;
  estadoActual: 'enviado' | 'visto' | 'proceso' | 'aceptado' | 'rechazado';
}

@Component({
  selector: 'app-permisos',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './permisos.component.html',
  styleUrls: ['./permisos.component.css']
})
export class PermisosComponent {
  // Pestañas: 'solicitar' o 'historial'
  tabActiva: string = 'solicitar';

  // Datos en vivo para el PDF
  formulario = {
    tipo: 'Descanso Médico',
    fechaInicio: '',
    fechaFin: '',
    motivo: '',
    firmaBase64: '' // Aquí se guardará la firma después
  };

  // Historial de Trámites Simulados
  misTramites: Solicitud[] = [
    { id: 'PRM-0042', tipo: 'Vacaciones Anuales', fechaEmision: '02 May, 2026', estadoActual: 'proceso' },
    { id: 'PRM-0038', tipo: 'Permiso Personal', fechaEmision: '15 Abr, 2026', estadoActual: 'aceptado' }
  ];

  cambiarTab(tab: string) {
    this.tabActiva = tab;
  }

  // Simulación del flujo de envío
  prepararEnvio() {
    if (!this.formulario.firmaBase64) {
      alert("Debes firmar el documento antes de enviarlo.");
      return;
    }
    // Lógica futura para subir a Cloudinary y guardar en Postgres...
    console.log("Enviando documento...", this.formulario);
  }

  // Función temporal para simular que el usuario firmó
  simularFirma() {
    this.formulario.firmaBase64 = 'FIRMA_OK';
  }
}