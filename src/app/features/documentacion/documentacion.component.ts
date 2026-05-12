import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-documentacion',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './documentacion.component.html',
  styleUrls: ['./documentacion.component.css']
})
export class DocumentacionComponent implements OnInit {
  searchTerm: string = '';

  // Datos simulados basados en tu diseño
  categorias = [
    { id: 'instalacion', nombre: 'Instalación', cantidad: 24, icon: '🔧', colorClass: 'cat-blue' },
    { id: 'redes', nombre: 'Redes', cantidad: 18, icon: '🌐', colorClass: 'cat-purple' },
    { id: 'seguridad', nombre: 'Seguridad', cantidad: 12, icon: '⚠️', colorClass: 'cat-red' },
    { id: 'mantenimiento', nombre: 'Mantenimiento', cantidad: 16, icon: '🔨', colorClass: 'cat-orange' }
  ];

  vistosRecientemente = [
    { id: 1, titulo: 'Guía de Infraestructura de Red', tiempo: 'Hace 2h' },
    { id: 2, titulo: 'Protocolos de Seguridad', tiempo: 'Ayer' }
  ];

  todosLosManuales = [
    {
      id: 101,
      titulo: 'Guía de Instalación de Infraestructura de Red',
      categoria: 'Instalación',
      paginas: 48,
      actualizado: '15 Mar',
      favorito: true,
      tipoIcono: 'doc'
    },
    {
      id: 102,
      titulo: 'Empalme de Cable de Fibra Óptica',
      categoria: 'Redes',
      tiempoLectura: '22 min',
      actualizado: '10 Mar',
      favorito: false,
      tipoIcono: 'video'
    }
  ];

  constructor() {}

  ngOnInit(): void {}

  // Lógica simple para el buscador
  get manualesFiltrados() {
    if (!this.searchTerm) return this.todosLosManuales;
    const term = this.searchTerm.toLowerCase();
    return this.todosLosManuales.filter(m =>
      m.titulo.toLowerCase().includes(term) || m.categoria.toLowerCase().includes(term)
    );
  }

  toggleFavorito(manual: any) {
    manual.favorito = !manual.favorito;
  }
}