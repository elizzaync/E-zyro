import { Component, Input, Output, EventEmitter, ChangeDetectionStrategy } from '@angular/core';

/**
 * Paginación compartida del Portal Cliente: « ‹ 1 2 3 › » con ventana de ±2.
 */
@Component({
  selector: 'pc-pagination',
  standalone: true,
  template: `
    @if (pages > 1) {
    <div class="pcg">
      <button class="pcg-btn pcg-nav" (click)="go(1)" [disabled]="page === 1">«</button>
      <button class="pcg-btn pcg-nav" (click)="go(page - 1)" [disabled]="page === 1">‹</button>
      @if (visible[0] > 1) { <span class="pcg-dots">…</span> }
      @for (p of visible; track p) {
        <button class="pcg-btn" [class.active]="p === page" (click)="go(p)">{{ p }}</button>
      }
      @if (visible[visible.length - 1] < pages) { <span class="pcg-dots">…</span> }
      <button class="pcg-btn pcg-nav" (click)="go(page + 1)" [disabled]="page === pages">›</button>
      <button class="pcg-btn pcg-nav" (click)="go(pages)" [disabled]="page === pages">»</button>
    </div>
    }
  `,
  styles: [`
    .pcg { display: flex; align-items: center; justify-content: center; gap: 4px; flex-wrap: wrap; }
    .pcg-btn {
      min-width: 34px; height: 34px; padding: 0 8px; border-radius: 9px;
      font-size: 13px; font-weight: 600; cursor: pointer;
      border: 1px solid var(--border-color); background: var(--card-bg); color: var(--text-main);
      transition: all .15s; display: flex; align-items: center; justify-content: center;
    }
    .pcg-btn:hover:not(:disabled):not(.active) { border-color: var(--brand-green); color: var(--brand-green); }
    .pcg-btn.active { background: var(--brand-green); color: #fff; border-color: var(--brand-green); }
    .pcg-btn:disabled { opacity: .35; cursor: not-allowed; }
    .pcg-nav { font-size: 15px; }
    .pcg-dots { font-size: 14px; color: var(--text-muted); padding: 0 4px; }
  `],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class PortalPaginationComponent {
  @Input() page = 1;
  @Input() pages = 1;
  @Output() pageChange = new EventEmitter<number>();

  get visible(): number[] {
    const out: number[] = [];
    for (let i = Math.max(1, this.page - 2); i <= Math.min(this.pages, this.page + 2); i++) out.push(i);
    return out;
  }

  go(p: number): void {
    if (p < 1 || p > this.pages || p === this.page) return;
    this.pageChange.emit(p);
  }
}
