import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-password-strength',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './password-strength.component.html',
  styleUrls: ['./password-strength.component.css']
})
export class PasswordStrengthComponent {
  @Input() password = '';

  get score(): number {
    let s = 0;
    if (!this.password) return 0;
    if (this.password.length >= 6) s++;
    if (this.password.length >= 10) s++;
    if (/[A-Z]/.test(this.password)) s++;
    if (/[0-9]/.test(this.password)) s++;
    if (/[^A-Za-z0-9]/.test(this.password)) s++;
    return s;
  }

  get strengthClass(): string {
    if (this.score <= 1) return 'weak';
    if (this.score <= 3) return 'medium';
    return 'strong';
  }

  get strengthLabel(): string {
    const map: Record<string, string> = {
      weak: 'Débil',
      medium: 'Media',
      strong: 'Fuerte'
    };
    return map[this.strengthClass] || '';
  }
}