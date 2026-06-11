import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-justificacion-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    @if (visible) {
    <div class="jm-backdrop" (click)="cancelar()"></div>
    <div class="jm-box fade-in-up" (click)="$event.stopPropagation()">
      <div class="jm-header">
        <h3 class="jm-title">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="jm-icon">
            <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
          </svg>
          {{ titulo }}
        </h3>
        <button class="jm-close" (click)="cancelar()">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
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
    </div>
    }
  `,
  styles: [`
    .jm-backdrop {
      position: fixed; inset: 0; background: rgba(0,0,0,.55); z-index: 900;
    }
    .jm-box {
      position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);
      background: var(--card-bg, #1e2330); border: 1px solid var(--border, #2d3448);
      border-radius: 14px; padding: 28px; width: min(520px, 92vw);
      box-shadow: 0 20px 60px rgba(0,0,0,.5); z-index: 901;
    }
    .jm-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
    .jm-title { font-size: 1.05rem; font-weight: 600; color: var(--text-primary, #e2e8f0);
                display: flex; align-items: center; gap: 8px; margin: 0; }
    .jm-icon { width: 18px; height: 18px; color: var(--accent, #f59e0b); }
    .jm-close { background: none; border: none; cursor: pointer; color: var(--text-muted, #6b7280); padding: 4px;
                display: flex; border-radius: 6px; }
    .jm-close:hover { color: var(--text-primary, #e2e8f0); background: var(--hover, rgba(255,255,255,.06)); }
    .jm-close svg { width: 18px; height: 18px; }
    .jm-desc { font-size: .85rem; color: var(--text-muted, #9ca3af); margin-bottom: 14px; }
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
    .fade-in-up { animation: fadeInUp .2s ease; }
    @keyframes fadeInUp { from { opacity: 0; transform: translate(-50%, -46%); } to { opacity: 1; transform: translate(-50%, -50%); } }
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
