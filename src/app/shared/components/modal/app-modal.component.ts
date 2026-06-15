import { Component, Input, Output, EventEmitter, OnChanges, OnDestroy, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './app-modal.component.html',
  styleUrls: ['./app-modal.component.css'],
})
export class AppModalComponent implements OnChanges, OnDestroy {
  @Input() open = false;
  @Input() title = '';
  @Input() subtitle = '';
  @Input() maxWidth = '580px';
  @Input() iconBg = 'rgba(141,198,63,0.12)';
  @Input() iconColor = 'var(--brand-green,#22c55e)';
  @Output() closeModal = new EventEmitter<void>();

  ngOnChanges(c: SimpleChanges): void {
    if ('open' in c) {
      const val = this.open ? 'hidden' : '';
      document.body.style.overflow = val;
      document.documentElement.style.overflow = val;
    }
  }

  ngOnDestroy(): void {
    document.body.style.overflow = '';
    document.documentElement.style.overflow = '';
  }

  close(): void {
    this.closeModal.emit();
  }
}
