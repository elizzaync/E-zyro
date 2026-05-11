import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HelpSearchComponent } from './components/help-search/help-search.component';
import { FaqListComponent } from './components/faq-list/faq-list.component';
import { ContactCardsComponent } from './components/contact-cards/contact-cards.component';
import { DocBannerComponent } from './components/doc-banner/doc-banner.component';
import { Faq } from './components/faq-list/faq-list.component';

@Component({
  selector: 'app-centro-ayuda',
  standalone: true,
  imports: [
    CommonModule,
    HelpSearchComponent,
    FaqListComponent,
    ContactCardsComponent,
    DocBannerComponent
  ],
  templateUrl: './centro-ayuda.component.html',
  styleUrls: ['./centro-ayuda.component.css']
})
export class CentroAyudaComponent implements OnInit {

  allFaqs: Faq[] = [];
  filteredFaqs: Faq[] = [];
  searchTerm = '';
  mostrarTodas = false;

  get preguntasVisibles(): Faq[] {
    if (this.searchTerm) return this.filteredFaqs;
    return this.mostrarTodas ? this.filteredFaqs : this.filteredFaqs.slice(0, 5);
  }

  async ngOnInit(): Promise<void> {
    try {
      const res = await fetch('/assets/data/faq.json');
      if (!res.ok) throw new Error();
      const data: Faq[] = await res.json();
      this.allFaqs = data;
      this.filteredFaqs = data;
    } catch (error) {
      console.error('[CentroAyuda] Error al cargar FAQ:', error);
    }
  }

  onSearch(term: string): void {
    this.searchTerm = term;
    const normalized = this.normalize(term);
    if (!normalized) {
      this.filteredFaqs = this.allFaqs;
      this.mostrarTodas = false;
      return;
    }
    this.filteredFaqs = this.allFaqs.filter(faq =>
      this.normalize(faq.pregunta).includes(normalized) ||
      this.normalize(faq.respuesta).includes(normalized) ||
      this.normalize(faq.categoria).includes(normalized)
    );
  }

  verTodas(): void {
    this.mostrarTodas = true;
  }

  private normalize(text: string): string {
    return text
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '');
  }
}
