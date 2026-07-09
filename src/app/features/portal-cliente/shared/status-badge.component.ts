import { Component, Input, ChangeDetectionStrategy } from '@angular/core';

/**
 * Badge de estado unificado del Portal Cliente (rediseño 2026-07).
 * Un solo vocabulario para todo el portal: ok | prog | warn | err | neutral.
 * Colores vía tokens globales --st-* (se adaptan solos a claro/oscuro).
 */
@Component({
  selector: 'pc-status-badge',
  standalone: true,
  template: `
    <span class="pcb" [class]="'pcb pcb-' + status">
      <span class="pcb-dot"></span>{{ label }}
    </span>
  `,
  styles: [`
    .pcb {
      display: inline-flex; align-items: center; gap: 6px;
      padding: 4px 11px; border-radius: 99px;
      font-size: 12px; font-weight: 600; white-space: nowrap;
      line-height: 1.2;
    }
    .pcb-dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; flex: none; }
    .pcb-ok      { background: var(--st-ok-bg);      color: var(--st-ok); }
    .pcb-prog    { background: var(--st-prog-bg);    color: var(--st-prog); }
    .pcb-warn    { background: var(--st-warn-bg);    color: var(--st-warn); }
    .pcb-err     { background: var(--st-err-bg);     color: var(--st-err); }
    .pcb-neutral { background: var(--st-neutral-bg); color: var(--st-neutral); }
  `],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class StatusBadgeComponent {
  @Input() status: 'ok' | 'prog' | 'warn' | 'err' | 'neutral' = 'neutral';
  @Input() label = '';
}
