import { Component, ElementRef, ViewChild, AfterViewChecked, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ChatbotService } from '../../../core/services/chatbot.service'; // Ajusta la ruta si es necesario

interface ChatMessage {
  sender: 'bot' | 'user';
  text: string;
  time: string;
}

@Component({
  selector: 'app-chatbot',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './chatbot.component.html',
  styleUrls: ['./chatbot.component.css']
})
export class ChatbotComponent implements OnInit, AfterViewChecked {
  @ViewChild('chatScroll') private chatScrollContainer!: ElementRef;

  // Inyectamos el nuevo servicio
  private chatbotService = inject(ChatbotService);

  isOpen = false;
  newMessage = '';
  isTyping = false;

  messages: ChatMessage[] = [
    { sender: 'bot', text: '¡Hola, soy E-Zyro! 🤖 Tu asistente virtual de E-System TIC. ¿En qué te puedo ayudar hoy?', time: this.getCurrentTime() }
  ];

  ngOnInit() {
    // Escuchamos las órdenes del servicio
    this.chatbotService.isOpen$.subscribe(state => {
      this.isOpen = state;
      if (this.isOpen) {
        // Pequeño delay para asegurar que el HTML ya se renderizó antes de hacer scroll
        setTimeout(() => this.scrollToBottom(), 50);
      }
    });
  }

  toggleChat() {
    // Ahora el servicio decide si se abre o cierra
    this.chatbotService.toggleChat();
  }

  sendMessage() {
    if (!this.newMessage.trim()) return;

    this.messages.push({ sender: 'user', text: this.newMessage, time: this.getCurrentTime() });
    this.newMessage = '';
    this.isTyping = true;
    this.scrollToBottom();

    setTimeout(() => {
      this.isTyping = false;
      this.messages.push({
        sender: 'bot',
        text: 'Por ahora solo soy un diseño visual, ¡pero pronto podré procesar solicitudes, agendar servicios y buscar materiales!',
        time: this.getCurrentTime()
      });
      this.scrollToBottom();
    }, 1500);
  }

  getCurrentTime(): string {
    const now = new Date();
    return now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  ngAfterViewChecked() {
    this.scrollToBottom();
  }

  private scrollToBottom(): void {
    try {
      if (this.chatScrollContainer) {
        this.chatScrollContainer.nativeElement.scrollTop = this.chatScrollContainer.nativeElement.scrollHeight;
      }
    } catch(err) { }
  }
}