import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class ChatbotService {
  private isOpenSubject = new BehaviorSubject<boolean>(false);
  isOpen$ = this.isOpenSubject.asObservable();

  toggleChat() {
    this.isOpenSubject.next(!this.isOpenSubject.value);
  }

  openChat() {
    this.isOpenSubject.next(true);
  }

  closeChat() {
    this.isOpenSubject.next(false);
  }
}