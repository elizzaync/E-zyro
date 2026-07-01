import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AppModalComponent } from '../modal/app-modal.component';

@Component({
  selector: 'app-justificacion-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, AppModalComponent],
  template: `
    <app-modal
      [open]="visible"
      [title]="titulo"
      maxWidth="520px"
      iconBg="rgba(245,158,11,0.12)"
      iconColor="#f59e0b"
      (closeModal)="cancelar()">

      <svg modal-icon viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
      </svg>

      <p class="jm-desc">{{ descripcion }}</p>
      <textarea
        class="jm-textarea"
        [(ngModel)]="texto"
        rows="4"
        maxlength="500"
        placeholder="Escribe aquí la justificación del cambio..."
        autofocus
      ></textarea>
      <div class="jm-counter">{{ texto.length }} / 500</div>
      <div class="jm-actions">
        <button class="jm-btn-cancel" (click)="cancelar()">Cancelar</button>
        <button class="jm-btn-confirm" (click)="confirmar()" [disabled]="!texto.trim()">
          Confirmar cambio
        </button>
      </div>
    </app-modal>
  `,
  styles: [`
    .jm-desc { font-size: .85rem; color: var(--text-muted, #9ca3af); margin: 0 0 14px; }
    .jm-textarea {
      width: 100%; resize: vertical; padding: 10px 12px; font-size: .9rem; line-height: 1.5;
      background: var(--input-bg, #161b26); border: 1.5px solid var(--border, #2d3448);
      border-radius: 8px; color: var(--text-primary, #e2e8f0); box-sizing: border-box;
    }
    .jm-textarea:focus { outline: none; border-color: var(--accent, #f59e0b); }
    .jm-counter { font-size: .75rem; color: var(--text-muted, #6b7280); text-align: right; margin: 4px 0 16px; }
    .jm-actions { display: flex; gap: 10px; justify-content: flex-end; }
    .jm-btn-cancel { padding: 8px 18px; border-radius: 8px; border: 1.5px solid var(--border, #2d3448);
                     background: transparent; color: var(--text-muted, #9ca3af); cursor: pointer; font-size: .9rem; }
    .jm-btn-cancel:hover { border-color: var(--text-muted, #9ca3af); color: var(--text-primary, #e2e8f0); }
    .jm-btn-confirm { padding: 8px 20px; border-radius: 8px; border: none;
                      background: var(--accent, #f59e0b); color: #000; font-weight: 600;
                      cursor: pointer; font-size: .9rem; }
    .jm-btn-confirm:hover:not(:disabled) { filter: brightness(1.1); }
    .jm-btn-confirm:disabled { opacity: .45; cursor: not-allowed; }
  `]
})
export class JustificacionModalComponent {
  @Input() visible = false;
  @Input() titulo  = 'Justificación requerida';
  @Input() descripcion = 'Como Jefe de Operaciones, todos tus cambios quedan registrados en auditoría. Describe brevemente el motivo de esta modificación.';
  @Output() confirmado = new EventEmitter<string>();
  @Output() cancelado  = new EventEmitter<void>();

  texto = '';

  confirmar(): void {
    const t = this.texto.trim();
    if (!t) return;
    this.confirmado.emit(t);
    this.texto = '';
  }

  cancelar(): void {
    this.texto = '';
    this.cancelado.emit();
  }
}
