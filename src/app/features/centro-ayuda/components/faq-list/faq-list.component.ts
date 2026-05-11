import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

export interface Faq {
  id: number;
  categoria: string;
  pregunta: string;
  respuesta: string;
}

@Component({
  selector: 'app-faq-list',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './faq-list.component.html',
  styleUrls: ['./faq-list.component.css']
})
export class FaqListComponent {
  @Input() faqs: Faq[] = [];

  expandedId: number | null = null;

  toggle(id: number): void {
    this.expandedId = this.expandedId === id ? null : id;
  }

  isExpanded(id: number): boolean {
    return this.expandedId === id;
  }
}
