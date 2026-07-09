import { Component, Input, ChangeDetectionStrategy } from '@angular/core';

/**
 * Barra de progreso del Portal Cliente con color por rango:
 * gris <25 · ámbar 25–59 · azul 60–99 · verde 100 (o completado).
 */
@Component({
  selector: 'pc-progress-bar',
  standalone: true,
  template: `
    <div class="pcp-row">
      <div class="pcp-track" [style.height]="height">
        <div class="pcp-fill" [class]="'pcp-fill ' + rangeClass" [style.width.%]="pct"></div>
      </div>
      @if (showLabel) { <span class="pcp-label">{{ pct }}%</span> }
    </div>
  `,
  styles: [`
    .pcp-row { display: flex; align-items: center; gap: 10px; }
    .pcp-track {
      flex: 1; height: 8px; background: var(--track-bg);
      border-radius: 99px; overflow: hidden;
    }
    .pcp-fill { height: 100%; border-radius: 99px; transition: width .4s ease; }
    .pcp-gris  { background: #9ca3af; }
    .pcp-ambar { background: linear-gradient(90deg, #fbbf24, #f59e0b); }
    .pcp-azul  { background: linear-gradient(90deg, #60a5fa, #3b82f6); }
    .pcp-verde { background: linear-gradient(90deg, #34d399, #10b981); }
    .pcp-label { font-size: 12px; font-weight: 700; color: var(--text-main); flex: none; }
  `],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ProgressBarComponent {
  @Input() value = 0;
  @Input() height = '8px';
  @Input() showLabel = false;

  get pct(): number {
    return Math.max(0, Math.min(100, Math.round(this.value ?? 0)));
  }

  get rangeClass(): string {
    const p = this.pct;
    if (p >= 100) return 'pcp-verde';
    if (p >= 60)  return 'pcp-azul';
    if (p >= 25)  return 'pcp-ambar';
    return 'pcp-gris';
  }
}
