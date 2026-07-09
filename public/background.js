/* ============================================================================
 * background.js — Animated particle background layer (standalone, no deps)
 * ----------------------------------------------------------------------------
 * INTEGRATION:
 *   1. Drop this file into your project and load it once:
 *        <script src="background.js" defer></script>
 *   2. The script creates and appends its own <canvas> (fixed, full-viewport,
 *      z-index: -1, pointer-events: none, transparent). Your app controls the
 *      page background color — the canvas only draws particles on top of it.
 *      NOTE: any element that should reveal the particles must have a
 *      transparent background; opaque wrappers will cover the canvas.
 *   3. Stack your UI above it:
 *        <!-- background canvas renders here, behind everything -->
 *        <!-- your navbar z-index: 10 -->
 *        <!-- your cards z-index: 1 -->
 *      i.e. dashboard cards, navbar and modals must use z-index >= 1 and
 *      sit in a positioned context (position: relative is enough).
 *   4. Enable / disable (E-zyro: SOLO portal cliente / rol ClienteExterno):
 *        window.setParticleBackground(true | false)
 *      Starts hidden; the app enables it on /portal-cliente/* routes.
 *      If the app boots first, it can pre-set window.__particleBgEnabled.
 *   5. Theme switching:
 *        window.setParticleTheme('dark')   // cyan #00d4ff + green #00ff88
 *        window.setParticleTheme('light')  // navy #1a4a8a + teal #007a8a (op. 0.4)
 *      Colors interpolate smoothly over 30 frames. Initial theme is read from
 *      <html data-theme="..."> or prefers-color-scheme.
 *
 * PERFORMANCE:
 *   - 80 particles, DPR capped at 1.5
 *   - Spatial grid (cell = link distance) instead of O(n²) line checks
 *   - mousemove throttled to one update per animation frame
 *   - Animation fully paused (and line pass skipped) while the tab is hidden
 * ========================================================================== */
(function () {
  'use strict';

  // --- run outside Angular's zone -------------------------------------------
  // zone.js (loaded as an Angular polyfill before this script) monkey-patches
  // requestAnimationFrame/addEventListener on window/document *globally*, not
  // just calls made by Angular. Without this, every particle animation frame
  // (and every mousemove sample) would re-enter NgZone and trigger a full
  // Angular change-detection pass across the whole app, ~60 times/sec, for as
  // long as the portal is open. Grabbing the pre-patch native functions (the
  // convention zone.js itself uses: `__zone_symbol__<name>`) keeps this
  // entirely outside Angular, with zero behavior change and no Angular dep.
  function zoneSymbol(name) {
    return (window.Zone && typeof window.Zone.__symbol__ === 'function')
      ? window.Zone.__symbol__(name) : name;
  }
  function native(name, ctx) {
    const fn = ctx[zoneSymbol(name)] || ctx[name];
    return fn.bind(ctx);
  }
  const rafNative = native('requestAnimationFrame', window);
  const windowAddEventListenerNative = native('addEventListener', window);
  const documentAddEventListenerNative = native('addEventListener', document);

  // --- canvas as background layer -------------------------------------------
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  canvas.style.cssText =
    'position:fixed;top:0;left:0;width:100vw;height:100vh;' +
    'z-index:-1;pointer-events:none;display:block;background:transparent;';
  document.body.insertBefore(canvas, document.body.firstChild);
  const ctx = canvas.getContext('2d');

  let W, H, DPR;

  const COUNT = 80;
  const LINK_DIST = 80;
  const MOUSE_RADIUS = 100;
  const particles = [];
  const mouse = { x: -9999, y: -9999, active: false };

  // --- themes ---------------------------------------------------------------
  // flat layout: [aR,aG,aB, bR,bG,bB, lineR,lineG,lineB, particleAlpha, lineAlpha]
  const THEMES = {
    dark:  [0, 212, 255,   0, 255, 136,   0, 212, 255,   0.55, 0.35],
    light: [26, 74, 138,   0, 122, 138,   26, 74, 138,   0.40, 0.25]
  };
  const TRANSITION_FRAMES = 30;

  function initialTheme() {
    const attr = document.documentElement.getAttribute('data-theme');
    if (attr === 'dark' || attr === 'light') return attr;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  let cur = THEMES[initialTheme()].slice();
  let from = cur.slice();
  let to = cur.slice();
  let transLeft = 0;

  window.setParticleTheme = function (theme) {
    const target = THEMES[theme] || THEMES.dark;
    from = cur.slice();
    to = target.slice();
    transLeft = TRANSITION_FRAMES;
  };

  function tickTheme() {
    if (transLeft <= 0) return;
    transLeft--;
    const t = 1 - transLeft / TRANSITION_FRAMES;
    for (let i = 0; i < cur.length; i++) cur[i] = from[i] + (to[i] - from[i]) * t;
  }

  // --- particles --------------------------------------------------------------
  function resize() {
    DPR = Math.min(window.devicePixelRatio || 1, 1.5);
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = W * DPR;
    canvas.height = H * DPR;
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  }

  function rand(min, max) { return Math.random() * (max - min) + min; }

  function makeParticle(atBottom) {
    return {
      x: rand(0, W),
      y: atBottom ? rand(H, H + 40) : rand(0, H),
      vy: rand(-0.6, -0.2),          // drifting upward
      vx: rand(-0.15, 0.15),
      r: rand(1, 4),
      green: Math.random() < 0.55,   // color B vs color A
      glow: 0
    };
  }

  function init() {
    particles.length = 0;
    for (let i = 0; i < COUNT; i++) particles.push(makeParticle(false));
  }

  // --- spatial grid: only compare particles in the same / neighboring cells ---
  const grid = new Map();

  function cellKey(cx, cy) { return cx + cy * 4096; }

  function buildGrid() {
    grid.clear();
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const key = cellKey((p.x / LINK_DIST) | 0, (p.y / LINK_DIST) | 0);
      const bucket = grid.get(key);
      if (bucket) bucket.push(p); else grid.set(key, [p]);
    }
  }

  // `strokeStyle` se fija UNA vez por frame en drawLines() (más abajo) — es
  // el mismo color para todas las líneas del frame. Aquí solo varía la
  // opacidad por línea, vía `globalAlpha` (número) en vez de reconstruir un
  // string 'rgba(...)' y reasignar `strokeStyle` en cada llamada: evita que
  // el navegador reparsee un color CSS por cada línea, cientos de veces por
  // frame — el resultado pintado es idéntico (alpha efectivo = mismo valor).
  function linkPair(a, b) {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    const d2 = dx * dx + dy * dy;
    if (d2 >= LINK_DIST * LINK_DIST) return;
    const d = Math.sqrt(d2);
    ctx.globalAlpha = (1 - d / LINK_DIST) * cur[10];
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
  }

  function drawLines() {
    const lineRGB = (cur[6] | 0) + ',' + (cur[7] | 0) + ',' + (cur[8] | 0);
    ctx.lineWidth = 0.6;
    ctx.strokeStyle = 'rgb(' + lineRGB + ')';
    buildGrid();
    // for each occupied cell: pairs within the cell, plus the 4 "forward"
    // neighbors (E, SW, S, SE) so every neighboring pair is checked exactly once
    grid.forEach(function (bucket, key) {
      const cx = ((key % 4096) + 4096) % 4096;
      const cy = Math.round((key - (key % 4096)) / 4096);
      for (let i = 0; i < bucket.length; i++) {
        for (let j = i + 1; j < bucket.length; j++) linkPair(bucket[i], bucket[j]);
      }
      const neighbors = [
        grid.get(cellKey(cx + 1, cy)),
        grid.get(cellKey(cx - 1, cy + 1)),
        grid.get(cellKey(cx, cy + 1)),
        grid.get(cellKey(cx + 1, cy + 1))
      ];
      for (let n = 0; n < 4; n++) {
        const other = neighbors[n];
        if (!other) continue;
        for (let i = 0; i < bucket.length; i++) {
          for (let j = 0; j < other.length; j++) linkPair(bucket[i], other[j]);
        }
      }
    });
    ctx.globalAlpha = 1; // las partículas de más abajo llevan su propio alpha en fillStyle
  }

  // --- main loop ---------------------------------------------------------------
  let running = false;
  let enabled = false; // solo se activa para el portal cliente (rol ClienteExterno)

  function step() {
    if (!running) return;

    tickTheme();
    ctx.clearRect(0, 0, W, H);

    if (!document.hidden) drawLines();

    const colA = (cur[0] | 0) + ',' + (cur[1] | 0) + ',' + (cur[2] | 0);
    const colB = (cur[3] | 0) + ',' + (cur[4] | 0) + ',' + (cur[5] | 0);
    const baseAlpha = cur[9];

    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];

      // mouse attraction + glow
      let glowing = false;
      if (mouse.active) {
        const dx = mouse.x - p.x;
        const dy = mouse.y - p.y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < MOUSE_RADIUS && d > 0.1) {
          const force = (1 - d / MOUSE_RADIUS) * 0.6;
          p.x += (dx / d) * force;
          p.y += (dy / d) * force;
          glowing = true;
        }
      }
      p.glow += ((glowing ? 1 : 0) - p.glow) * 0.15;

      p.x += p.vx;
      p.y += p.vy;

      // float up, reset at bottom
      if (p.y < -10) Object.assign(p, makeParticle(true));
      if (p.x < -10) p.x = W + 10;
      if (p.x > W + 10) p.x = -10;

      const baseColor = p.green ? colB : colA;
      const r = p.r + p.glow * 1.6;
      const alpha = baseAlpha + p.glow * 0.45;

      if (p.glow > 0.05) {
        ctx.shadowBlur = 12 * p.glow;
        ctx.shadowColor = 'rgba(' + baseColor + ',0.9)';
      } else {
        ctx.shadowBlur = 0;
      }

      ctx.beginPath();
      ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(' + baseColor + ',' + alpha + ')';
      ctx.fill();
    }
    ctx.shadowBlur = 0;

    rafNative(step);
  }

  function start() {
    if (running || !enabled) return;
    running = true;
    rafNative(step);
  }

  window.setParticleBackground = function (on) {
    enabled = !!on;
    canvas.style.display = enabled ? 'block' : 'none';
    if (enabled) { init(); start(); }
    else running = false;
  };

  // pause completely while the tab is hidden
  documentAddEventListenerNative('visibilitychange', function () {
    if (document.hidden) running = false;
    else start();
  });

  // --- input: mousemove throttled to one update per animation frame ----------
  let pendingX = 0, pendingY = 0, mouseRafQueued = false;

  function applyMouse() {
    mouse.x = pendingX;
    mouse.y = pendingY;
    mouse.active = true;
    mouseRafQueued = false;
  }

  windowAddEventListenerNative('mousemove', function (e) {
    pendingX = e.clientX;
    pendingY = e.clientY;
    if (!mouseRafQueued) {
      mouseRafQueued = true;
      rafNative(applyMouse);
    }
  }, { passive: true });

  documentAddEventListenerNative('mouseleave', function () { mouse.active = false; });

  windowAddEventListenerNative('touchmove', function (e) {
    if (e.touches[0]) {
      pendingX = e.touches[0].clientX;
      pendingY = e.touches[0].clientY;
      if (!mouseRafQueued) {
        mouseRafQueued = true;
        rafNative(applyMouse);
      }
    }
  }, { passive: true });
  windowAddEventListenerNative('touchend', function () { mouse.active = false; });

  windowAddEventListenerNative('resize', function () { resize(); init(); });

  resize();
  init();
  canvas.style.display = 'none'; // oculto hasta que la app lo active
  // si la app arrancó antes que este script, respeta el estado que dejó
  if (window.__particleBgEnabled) window.setParticleBackground(true);
})();
