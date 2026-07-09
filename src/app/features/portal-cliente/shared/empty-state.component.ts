import { Component, Input, ChangeDetectionStrategy } from '@angular/core';

/**
 * Estado vacío compartido del Portal Cliente.
 * El ícono se proyecta con <ng-content> (un SVG de ~28px).
 */
@Component({
  selector: 'pc-empty-state',
  standalone: true,
  template: `
    <div class="pce">
      <div class="pce-icon"><ng-content></ng-content></div>
      <p class="pce-title">{{ title }}</p>
      @if (subtitle) { <p class="pce-sub">{{ subtitle }}</p> }
    </div>
  `,
  styles: [`
    .pce {
      display: flex; flex-direction: column; align-items: center;
      padding: 3rem 1.5rem; gap: 6px; text-align: center;
    }
    .pce-icon {
      width: 56px; height: 56px; border-radius: 16px;
      display: grid; place-items: center;
      background: var(--hover-bg); color: var(--text-muted);
      margin-bottom: 6px;
    }
    .pce-title { margin: 0; font-size: 15px; font-weight: 700; color: var(--text-main); }
    .pce-sub   { margin: 0; font-size: 13px; color: var(--text-muted); max-width: 380px; line-height: 1.5; }
  `],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EmptyStateComponent {
  @Input() title = '';
  @Input() subtitle = '';
}
