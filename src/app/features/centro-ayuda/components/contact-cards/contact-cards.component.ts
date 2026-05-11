import { Component, inject } from '@angular/core';
import { ChatbotService } from '../../../../core/services/chatbot.service'; // Ajusta ruta

@Component({
  selector: 'app-contact-cards',
  standalone: true,
  templateUrl: './contact-cards.component.html',
  styleUrls: ['./contact-cards.component.css']
})
export class ContactCardsComponent {
  private chatbotService = inject(ChatbotService);

  // Esta función es la que llamará el botón
  abrirAsistente() {
    this.chatbotService.openChat();
  }
}