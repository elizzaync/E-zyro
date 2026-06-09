import {
  AfterViewInit,
  Component,
  ElementRef,
  NgZone,
  OnDestroy,
  ViewChild,
  inject,
} from '@angular/core';
import { Subscription } from 'rxjs';
import { ThemeService } from '../../../core/services/theme.service';

/** Nodo de la red neuronal: posición + velocidad lenta aleatoria */
interface NeuralNode {
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  brand: boolean; // nodo de acento en verde corporativo
}

@Component({
  selector: 'app-neural-background',
  standalone: true,
  templateUrl: './neural-background.component.html',
  styleUrls: ['./neural-background.component.css'],
})
export class NeuralBackgroundComponent implements AfterViewInit, OnDestroy {
  @ViewChild('neuralCanvas', { static: true })
  private canvasRef!: ElementRef<HTMLCanvasElement>;

  private themeService = inject(ThemeService);
  private zone = inject(NgZone);

  /* ── Parámetros de la simulación ── */
  private readonly CONNECT_DIST = 150;   // px máx. para trazar una conexión
  private readonly MAX_SPEED = 0.22;     // px/frame — deriva muy lenta
  private readonly DENSITY = 14000;      // px² de viewport por nodo
  private readonly MAX_NODES = 120;

  /* ── Colores corporativos por tema ── */
  private readonly DARK_RGB = '59, 130, 246';   // azul corporativo translúcido
  private readonly DARK_ALPHA = 0.3;
  private readonly LIGHT_RGB = '15, 23, 42';    // slate oscuro sutil
  private readonly LIGHT_ALPHA = 0.15;
  private readonly BRAND_RGB = '141, 198, 63';  // verde e-zyro — nodos de acento
  private readonly BRAND_RATIO = 0.12;
  private readonly NODE_ALPHA_BOOST = 1.7;      // nodos algo más visibles que las líneas

  private ctx!: CanvasRenderingContext2D;
  private nodes: NeuralNode[] = [];
  private rafId = 0;
  private isDark = false;
  private reducedMotion = false;
  private themeSub?: Subscription;

  private readonly onResize = () => this.setupCanvas();
  private readonly onVisibility = () => {
    if (document.hidden) {
      cancelAnimationFrame(this.rafId);
    } else if (!this.reducedMotion) {
      this.zone.runOutsideAngular(() => this.animate());
    }
  };

  ngAfterViewInit(): void {
    const canvas = this.canvasRef.nativeElement;
    this.ctx = canvas.getContext('2d')!;
    this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    this.isDark = this.resolveIsDark();
    this.themeSub = this.themeService.isDark$.subscribe(dark => {
      this.isDark = dark;
      if (this.reducedMotion) this.drawFrame(); // refrescar el frame estático
    });

    this.setupCanvas();
    window.addEventListener('resize', this.onResize);
    document.addEventListener('visibilitychange', this.onVisibility);

    // El loop corre fuera de Angular: rAF no debe disparar change detection
    this.zone.runOutsideAngular(() => {
      if (this.reducedMotion) {
        this.drawFrame();
      } else {
        this.animate();
      }
    });
  }

  ngOnDestroy(): void {
    cancelAnimationFrame(this.rafId);
    window.removeEventListener('resize', this.onResize);
    document.removeEventListener('visibilitychange', this.onVisibility);
    this.themeSub?.unsubscribe();
  }

  /** El atributo data-theme puede no estar fijado aún (modo automático del SO) */
  private resolveIsDark(): boolean {
    const attr = document.documentElement.getAttribute('data-theme');
    if (attr === 'dark') return true;
    if (attr === 'light') return false;
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  private setupCanvas(): void {
    const canvas = this.canvasRef.nativeElement;
    const dpr = window.devicePixelRatio || 1;
    const w = window.innerWidth;
    const h = window.innerHeight;

    canvas.width = w * dpr;
    canvas.height = h * dpr;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    this.seedNodes(w, h);
    if (this.reducedMotion) this.drawFrame();
  }

  private seedNodes(w: number, h: number): void {
    const count = Math.min(this.MAX_NODES, Math.floor((w * h) / this.DENSITY));
    this.nodes = Array.from({ length: count }, () => ({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: (Math.random() - 0.5) * 2 * this.MAX_SPEED,
      vy: (Math.random() - 0.5) * 2 * this.MAX_SPEED,
      radius: 1.2 + Math.random() * 1.6,
      brand: Math.random() < this.BRAND_RATIO,
    }));
  }

  private animate = (): void => {
    this.updateNodes();
    this.drawFrame();
    this.rafId = requestAnimationFrame(this.animate);
  };

  private updateNodes(): void {
    const w = window.innerWidth;
    const h = window.innerHeight;
    for (const n of this.nodes) {
      n.x += n.vx;
      n.y += n.vy;
      // Rebote suave en los bordes del viewport
      if (n.x <= 0 || n.x >= w) n.vx *= -1;
      if (n.y <= 0 || n.y >= h) n.vy *= -1;
    }
  }

  private drawFrame(): void {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const rgb = this.isDark ? this.DARK_RGB : this.LIGHT_RGB;
    const alpha = this.isDark ? this.DARK_ALPHA : this.LIGHT_ALPHA;

    this.ctx.clearRect(0, 0, w, h);

    // Conexiones: solo entre nodos a menos de CONNECT_DIST, opacidad ∝ cercanía
    for (let i = 0; i < this.nodes.length; i++) {
      const a = this.nodes[i];
      for (let j = i + 1; j < this.nodes.length; j++) {
        const b = this.nodes[j];
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const dist = Math.hypot(dx, dy);
        if (dist >= this.CONNECT_DIST) continue;

        this.ctx.strokeStyle =
          `rgba(${rgb}, ${(alpha * (1 - dist / this.CONNECT_DIST)).toFixed(3)})`;
        this.ctx.lineWidth = 1;
        this.ctx.beginPath();
        this.ctx.moveTo(a.x, a.y);
        this.ctx.lineTo(b.x, b.y);
        this.ctx.stroke();
      }
    }

    const nodeAlpha = Math.min(1, alpha * this.NODE_ALPHA_BOOST).toFixed(3);
    for (const n of this.nodes) {
      this.ctx.fillStyle = `rgba(${n.brand ? this.BRAND_RGB : rgb}, ${nodeAlpha})`;
      this.ctx.beginPath();
      this.ctx.arc(n.x, n.y, n.radius, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }
}
