import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly KEY = 'ezyro_tema';
  private _isDark = new BehaviorSubject<boolean>(false);

  readonly isDark$ = this._isDark.asObservable();
  get isDark(): boolean { return this._isDark.value; }

  /** Leer estado inicial desde localStorage o prefers-color-scheme */
  init(): void {
    const saved = localStorage.getItem(this.KEY);
    const dark  = saved !== null
      ? saved === 'dark'
      : window.matchMedia('(prefers-color-scheme: dark)').matches;
    this._apply(dark);
  }

  /** Alternar y persistir */
  toggle(): void {
    const next = !this.isDark;
    localStorage.setItem(this.KEY, next ? 'dark' : 'light');
    this._apply(next);
  }

  private _apply(dark: boolean): void {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    this._isDark.next(dark);
  }
}
