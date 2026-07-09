# Portal Cliente Externo — Ficha de Diseño Completa (E-zyro)

> Documento de contexto para rediseño. Relevado directamente del código en
> `C:\E-zyro-frontend` (Angular 21, standalone components, control flow
> `@if`/`@for`). No incluye capturas de pantalla — todos los valores (colores,
> tamaños, layout) son exactos, tomados del CSS real.

---

## 1. Qué es

El Portal Cliente Externo es la vista que ven los clientes de E-zyro (rol
`ClienteExterno`) cuando inician sesión: un subconjunto de solo lectura del
mismo ERP, para que el cliente pueda ver el avance de sus proyectos, el
estado de sus equipos, descargar documentos generados (informes, cartas de
garantía, certificados) y consultar el historial de mantenimientos — sin
poder editar nada.

Reutiliza el shell del ERP (mismo navbar, mismo layout raíz `app.html`), no
es una aplicación aparte. Se diferencia visualmente por: un fondo animado de
partículas exclusivo, un badge "Solo lectura" en el navbar, y un navbar con
muchos menos ítems.

## 2. Cómo se accede / arquitectura de rutas

6 páginas, todas bajo el prefijo `/portal-cliente/*`, protegidas por
`clientPortalGuard` (`src/app/app.routes.ts`), **rutas planas** (no hay
sub-rutas anidadas ni un layout propio):

| Ruta | Componente | Archivo |
|---|---|---|
| `/portal-cliente` → redirect | — | → `dashboard` |
| `/portal-cliente/dashboard` | `PortalDashboardComponent` | `features/portal-cliente/dashboard/` |
| `/portal-cliente/proyectos` | `PortalProyectosComponent` | `features/portal-cliente/proyectos/` |
| `/portal-cliente/proyecto/:id` | `PortalProyectoDetalleComponent` | `features/portal-cliente/proyecto-detalle/` |
| `/portal-cliente/documentos` | `PortalDocumentosComponent` | `features/portal-cliente/documentos/` |
| `/portal-cliente/mantenimientos` | `ClientEquipmentHistoryComponent` | `features/portal-cliente/mantenimientos/` |
| `/portal-cliente/mantenimiento/:id` | `PortalEquipoDetalleComponent` | `features/portal-cliente/equipo-detalle/` |

**Importante para el diseño**: existe `features/portal-cliente/client-layout/`
(`ClientLayoutComponent`) — **es código muerto, nunca se enruta**. Cualquier
propuesta de rediseño que toque el "layout" del portal debe ir en `app.html`
(condicionado a `esPortalCliente`) o en `styles.css` bajo `.portal-mode`, NO
en ese componente.

Todas las páginas se renderizan dentro de `<main class="portal-mode">`
(definido en `app.html`), que reutiliza el `<app-navbar>` global del ERP.

## 3. Stack y restricciones técnicas relevantes para diseño

- Angular 21, componentes standalone, `@if`/`@for` (no `*ngIf`/`*ngFor`).
- Los 6 componentes del portal son `ChangeDetectionStrategy.OnPush` y cargan
  sus rutas con `loadComponent` (lazy) — cualquier rediseño debe seguir
  disparando `cdr.markForCheck()` si agrega nuevas mutaciones de estado fuera
  de eventos de template (ver componentes `.ts` si se tocan).
- El fondo de partículas (`public/background.js`, plain JS fuera de Angular)
  y los gráficos de Chart.js del dashboard corren deliberadamente **fuera de
  la Angular zone** (`NgZone.runOutsideAngular`) — si el rediseño agrega
  animaciones o librerías con sus propios loops/listeners (por ejemplo,
  librerías de gráficos, carruseles, mapas), aplicar el mismo patrón para no
  reintroducir jank.
- Chart.js ya está en el proyecto (dashboard). Si el rediseño pide más
  gráficos, reusar Chart.js en vez de sumar otra librería.

## 4. Sistema de diseño global (tokens)

Fuente: `src/styles.css`. Tipografía global: `'Inter', 'Segoe UI', Roboto, sans-serif`
(token `--font-base`, aunque muchos componentes la hardcodean en vez de usar
la variable).

No existe una escala formal de `font-size` (`--font-size-sm/md/lg`) — cada
componente define sus propios `px` sueltos. Tampoco hay una escala formal de
espaciado (`--space-1/2/3...`) más allá de los tokens fluidos de página
descritos abajo. Esto es una oportunidad de sistematización para el rediseño.

### 4.1 Colores — tema claro (`:root`)

```css
--bg-color / --page-bg:  #f3f4f6
--card-bg / --box-bg:    #ffffff
--card-border:           transparent
--text-main:             #111827
--text-muted:            #6b7280
--input-bg:               #f9fafb
--input-border:          #d1d5db
--input-text:            #111827
--border-color:          #e5e7eb
--hover-bg:              #f3f4f6
--shadow-color:          rgba(17, 24, 39, 0.06)
--brand-green:           #8dc63f     /* color de marca, acento principal */
--brand-green-hover:     #7ab530
```

### 4.2 Colores — tema oscuro (`:root[data-theme="dark"]` o `prefers-color-scheme: dark`)

```css
--bg-color / --page-bg:  #0f172a
--card-bg / --box-bg:    #1e293b
--card-border:           #334155
--text-main:             #f8fafc
--text-muted:            #94a3b8
--input-bg:              #0f172a
--input-border:          #475569
--input-text:            #f8fafc
--border-color:          #334155
--hover-bg:              #334155
--shadow-color:          rgba(0, 0, 0, 0.4)
```

El toggle claro/oscuro vive en el dropdown de perfil del navbar (ítem
"Tema" → `ThemeService.toggle()`), disponible también para el cliente
externo. Al cambiar, se setea `data-theme` en `<html>` y se sincroniza en
vivo la paleta del canvas de partículas (`window.setParticleTheme`).

**Regla de CSS de componente**: `:root[data-theme="dark"]` NO funciona
dentro del CSS encapsulado de un componente Angular (la encapsulación le
agrega `[_ngcontent]` al `:root` y la regla nunca matchea). Hay que usar
`:host-context(html[data-theme="dark"])`. Varios componentes del portal ya
lo hacen bien (dashboard, mantenimientos); otros (proyectos, detalle de
proyecto, detalle de equipo) usan colores hardcodeados y NO se adaptan a
dark mode — ver sección 7.

### 4.3 Radios, sombras, espaciado

```css
--radius-sm: 6px   --radius-md: 10px   --radius-lg: 16px   --radius-xl: 20px
--shadow-sm:    0 1px 3px rgba(0,0,0,.07), 0 1px 2px rgba(0,0,0,.04)
--shadow-panel: 0 4px 16px rgba(0,0,0,.06)
--shadow-modal: 0 20px 60px rgba(0,0,0,.18)   /* en dark: 0 20px 60px rgba(0,0,0,.5) */
```
Radios realmente usados en la práctica (más allá de los tokens): 8px
(inputs/botones chicos), 12px (cards internas), 16-18px (modales, cards
grandes), 20-99px (pills/badges), 50% (avatares).

Espaciado de página fluido con breakpoints (`--bp-*` son solo documentación,
no `var()` usables dentro de `@media`):
```
Desktop (>1024px):  --space-page-x: 32px   --space-page-y: 40px   --space-gap: 24px   --nav-height: 72px
Tablet  (≤1024px):  --space-page-x: 24px   --space-page-y: 28px   --space-gap: 18px
Móvil   (≤640px):   --space-page-x: 16px   --space-page-y: 20px   --space-gap: 14px   --nav-height: 60px
Móvil chico (≤480px): --space-page-x: 12px  --space-page-y: 16px
--container-max: 1600px
--anim-speed: 0.3s   --anim-easing: cubic-bezier(0.2, 0.8, 0.2, 1)
```

### 4.4 Utilidades globales reusables

```css
/* Botones */
.btn-primary   { background: var(--brand-green); color: #fff; }
.btn-secondary { background: var(--card-bg); border: 1px solid var(--border-color); color: var(--text-main); }
.btn-cancel    { background: var(--hover-bg); color: var(--text-muted); }
.btn-danger    { background: #ef4444; color: #fff; }
/* todos: padding 8px 16px; border-radius: var(--radius-md); font-size:14px; font-weight:600; */

/* Badges de estado (sistema A — usado por dashboard y mantenimientos) */
.badge-success { background: #dcfce7; color: #166534; }
.badge-warning { background: #fef3c7; color: #92400e; }
.badge-danger  { background: #fee2e2; color: #991b1b; }

/* Card panel genérico */
.card-panel {
  background: var(--card-bg); border: 1px solid var(--border-color);
  border-radius: var(--radius-lg); box-shadow: var(--shadow-panel);
}

/* Glassmorphism específico de modo portal — MUY IMPORTANTE */
.portal-mode .card-panel, .portal-mode .client-portal-card {
  background: rgba(255,255,255,0.6);              /* dark: rgba(30,41,59,0.6) */
  backdrop-filter: blur(12px) saturate(140%);
  border: 1px solid rgba(0,0,0,0.05);              /* dark: rgba(255,255,255,0.08) */
  box-shadow: 0 4px 20px rgba(0,0,0,.08), 0 1px 3px rgba(0,0,0,.05);
}

/* Timeline reusable */
.timeline-container { border-left: 2px solid var(--border-color); margin-left: 20px; }
.timeline-marker { width:15px; height:15px; border-radius:50%; background: var(--border-color); }
.timeline-item.completed .timeline-marker { background:#16a34a; }
.timeline-item.upcoming  .timeline-marker { background:#f59e0b; }
.timeline-item.overdue   .timeline-marker { background:#dc2626; }

/* Grid de cards estilo Drive */
.grid-cards { display:grid; grid-template-columns: repeat(auto-fill, minmax(220px,1fr)); gap:1.25rem; }

/* Animaciones DRY */
.fade-in  { animation: fadeIn  var(--anim-speed) var(--anim-easing) both; }
.slide-up { animation: slideUp var(--anim-speed) var(--anim-easing) both; }
.scale-in { animation: scaleIn var(--anim-speed) var(--anim-easing) both; }
.fade-in-up { animation: modalPop 0.2s cubic-bezier(0.16,1,0.3,1) forwards; } /* modales */
```

**El punto clave de `.portal-mode`**: el `<main>` del portal es
`background: transparent` a propósito, para dejar ver el canvas de
partículas de fondo. Los paneles/cards del portal DEBERÍAN usar el glass de
`.portal-mode .card-panel` para que el fondo se note a través — pero como se
ve en la sección 7, no todas las páginas del portal lo hacen.

---

## 5. Chrome compartido

### 5.1 Navbar (mismo componente para todo el ERP, con rama condicional para portal)

No hay un navbar separado para el portal — es el mismo `<app-navbar>`, con
`@if (isClienteExterno)` cambiando qué se renderiza. `isClienteExterno` se
calcula normalizando el nombre de rol (`=== 'clienteexterno'` sin espacios).

**Marca (izquierda)**: logo cuadrado 42×42px verde marca con "E" blanca +
título "e-zyro" (verde) / "TIC" (texto principal) + subtítulo dinámico
(`panelSubtitulo` = **"Portal Cliente"** para clientes externos).

**Enlaces centrales — para cliente externo, SOLO 3 links planos, sin
dropdowns** (el personal interno ve Operaciones/Logística/RRHH con
submenús):
- Dashboard → `/portal-cliente/dashboard`
- Proyectos → `/portal-cliente/proyectos`
- Documentos → `/portal-cliente/documentos`
- Seguido de un badge fijo **"Solo lectura"** (ícono candado):
  ```css
  .portal-badge { padding:4px 10px; border-radius:99px;
    background: rgba(141,198,63,.12); color: var(--brand-green);
    border: 1px solid rgba(141,198,63,.25); font-size:11px; font-weight:600; }
  ```

**Nota**: el link "Historial de Mantenimientos"
(`/portal-cliente/mantenimientos`) y "Detalle de Equipo" NO están en el
navbar — solo se llega desde el dashboard o desde el detalle de un proyecto.
Vale la pena que el rediseño evalúe si deberían tener entrada directa.

**Acciones derechas** — para cliente externo:
- ❌ NO se muestra la campana de notificaciones.
- ❌ NO se muestra el divisor vertical entre acciones y perfil.
- ✅ Sí se muestra el dropdown de perfil (avatar + nombre + rol), pero con
  menos ítems: se ocultan "Trámites y Permisos", "Nube de Planos", "Crear
  Evaluación"; quedan "Mi Perfil" (subtítulo "Información de cuenta"), "Mis
  Evaluaciones", "Tema" (toggle claro/oscuro), "Ajustes", "Cerrar Sesión".

Dropdown: 280px de ancho, `border-radius:16px`, header con avatar 48px +
nombre + rol + "ID: ...", cuerpo con ítems ícono+título+subtítulo, footer
con "Cerrar Sesión" en rojo `#ef4444`. Animación: `dropFade 0.2s` (opacity +
`translateY(-10px)→0`).

Responsive: colapsa a hamburguesa por debajo de 1024px, con drawer deslizante
y backdrop `rgba(15,23,42,.45)`.

### 5.2 Fondo de partículas (`public/background.js`) — exclusivo del portal

Canvas fijo detrás de todo (`z-index:-1`), **solo se activa en rutas
`/portal-cliente/*`**. Valores visuales:

- 80 partículas, radio 1–4px aleatorio, 55% usa el color "B" del tema / 45%
  el color "A".
- Líneas de conexión entre partículas a menos de 80px de distancia, opacidad
  según distancia.
- Deriva lenta hacia arriba + leve drift horizontal.
- **Tema oscuro**: cyan `#00d4ff` + verde `#00ff88`.
- **Tema claro**: navy `#1a4a8a` + teal `#007a8a`, opacidad base 0.4.
- Transición de color entre temas: interpolación suave en 30 frames.
- Reacciona al mouse (atracción + glow) y se pausa cuando la pestaña está
  oculta.

Esto es el elemento de marca más distintivo del portal — cualquier
rediseño de cards/paneles debería preservar transparencia suficiente para
que el fondo se siga viendo (ver "glass" en 4.4).

### 5.3 `<app-modal>` — modal compartido estándar del proyecto

Usarlo para CUALQUIER modal nuevo (regla del proyecto: nunca hacer overlay
propio a mano). Inputs: `open`, `title`, `subtitle`, `maxWidth` (default
`580px`), `iconBg`, `iconColor`; `(closeModal)` output. Slots: `[modal-icon]`,
`[modal-header-actions]`, contenido libre.

```css
.modal-backdrop-pro { position:fixed; inset:0; z-index:9000; background:rgba(0,0,0,.6); }
.app-modal-shell {
  position:fixed; top:50%; left:50%; transform:translate(-50%,-50%);
  width:92%; max-height:calc(100vh - 80px); overflow-y:auto;
  background: var(--card-bg); border:1px solid var(--border-color);
  border-radius:18px; box-shadow: var(--shadow-modal);
}
.app-modal-head { position:sticky; top:0; background:var(--card-bg);
  padding:16px 18px 14px; border-bottom:1px solid var(--border-color); }
```
Cierre: click en backdrop o botón X (no tiene atajo de teclado ESC propio —
si una página lo necesita, como el detalle de proyecto, lo implementa ella
misma con `@HostListener`). Animación de entrada: `modalPop` (scale 0.96→1 +
fade), 0.2s.

**Nota**: coexiste con un sistema de modal "legacy" (`.modal-dialog-pro` en
`styles.css`, usado por logout/sesión/perfil, ancho fijo 400-520px) — para
el portal, todo nuevo modal debería ser `<app-modal>`.

### 5.4 Toast

Esquina superior derecha, `min-width:300px`, borde izquierdo de color de 4px,
ícono circular 36px. Solo 3 variantes: **success/default** (verde marca),
**error** (`#ef4444`), **info** (`#3b82f6`) — **no existe variante
`warning`**. Entrada: `slideInRight 0.4s`.

### 5.5 Spinner

Dos variantes: **ring** (círculo girando, borde superior de color) y
**loader de bolas** (dos bolas orbitando). Cada una con sub-variante
`primary` (verde marca / negro-blanco según tema) y `light` (blanco). El
portal usa mayormente un ring simple inline por página (no siempre el
componente compartido — ver "eh-page" y "pdoc-page" que definen su propio
`.spinner-ring` local en vez de usar `<app-spinner>`).

---

## 6. Páginas

### 6.1 Dashboard (`/portal-cliente/dashboard`) — la página más densa

**Layout**: CSS Grid de 12 columnas (`.mega-dashboard-grid`), sin wrapper de
ancho máximo (usa todo el ancho disponible, `padding:1.75rem 2rem 3rem`).
Fondo del wrapper `transparent` (se ve el canvas de partículas).

**De arriba a abajo**:
1. Header: eyebrow "Panel en vivo" (punto verde animado, `pulse 2s`) + título
   "Dashboard Ejecutivo" (28px/800) + fecha de hoy + chip de saludo + botón
   "Historial completo".
2. **Fila de 4 KPI cards** (`col-span-3` c/u): Total Equipos, Vigentes/
   Operativos (verde), Próximos a Vencer (ámbar), Vencidos (rojo). Cada una:
   valor grande (38px/800), tendencia vs. mes anterior (▲/▼ %), mini-gráfico
   sparkline de Chart.js (línea, sin ejes, 50px alto).
3. **Fila de gráfico mixto (8 col) + stack de 2 donuts (4 col)**: gráfico
   barras (Ejecutados) + línea (Programados) por los últimos 12 meses;
   donut de "Cumplimiento Operativo" (% grande verde) y donut de
   "Distribución por Proyecto" (top 3 + "Otros").
4. **Fila de barra horizontal (6 col) + calendario de próximos 7 días (6
   col)**: top 9 ubicaciones con más equipos intervenidos; lista de eventos
   próximos con ícono/color según urgencia (rojo si vencido/≤3 días, ámbar
   si ≤7, verde si ok), footer "Ver historial completo →" si hay pocos.

**Estilo visual — glassmorphism real** (única página que lo usa
consistentemente):
```css
.widget {
  background: var(--d-glass);              /* rgba(255,255,255,.6) / rgba(30,41,59,.6) en dark */
  backdrop-filter: blur(12px) saturate(140%);
  border-radius: 12px; border: 1px solid var(--d-glass-border);
  box-shadow: 0 4px 20px rgba(0,0,0,.12), 0 1px 3px rgba(0,0,0,.08);
}
```
Paleta de acento (invariante, no cambia con el tema):
`blue #3b82f6, green #10b981, amber #f59e0b, red #ef4444, brand #8dc63f, purple #8b5cf6, cyan #06b6d4`.

Responsive: en ≤1200px el gráfico mixto y los donuts pasan a ancho completo
(12 columnas); en ≤900px las filas de 6 col también; en ≤768px todo se apila
a 1 columna y el grid pasa a `1fr`.

**Interacciones**: sin modales ni drawers — es 100% lectura/visualización.
Hover sutil en widgets (`border-color` cambia a verde) y en items de evento.

### 6.2 Proyectos — lista (`/portal-cliente/proyectos`)

**Layout**: `max-width:1200px; margin:0 auto` (wrapper centrado — ver
inconsistencia en sección 7), grid `auto-fill minmax(300px,1fr)`.

**Estructura**: header (título + subtítulo) → grid de cards de proyecto, sin
filtros ni buscador (a diferencia de Documentos y Mantenimientos, que sí
tienen filtros — inconsistencia funcional a evaluar).

**Card de proyecto** (`.pp-card`, fondo `#fff` sólido hardcodeado — no usa
`var(--card-bg)`):
- Header: badge de estado + `%` de avance grande (20px/800).
- Nombre del proyecto (15px/600).
- Barra de progreso delgada (8px, pill, verde `#8dc63f` → verde `#10b981` al
  100%).
- Meta: ícono reloj + "N/M servicios", fecha inicio, fecha fin estimada.
- Botón "Ver detalle →".
- Hover: `translateY(-2px)` + sombra `0 8px 32px rgba(0,0,0,.1)`.

**Badges de estado — sistema DISTINTO al del dashboard** (ver sección 7):
`activo→badge-prog` (azul `#dbeafe/#1d4ed8`, "En curso"),
`completado→badge-ok` (verde), `cancelado→badge-err` (rojo),
`planificado→badge-pend` (gris, "Planificado").

Sin `@media` propio — solo el auto-fill del grid resuelve el responsive.

### 6.3 Detalle de Proyecto (`/portal-cliente/proyecto/:id`)

**Layout**: `max-width:1100px; margin:0 auto`. Cards apiladas
(`.pdet-card`, fondo `#fff` sólido, `border-radius:16px`).

**Estructura**:
1. Link "← Volver a Proyectos".
2. Hero: nombre del proyecto + fechas (izq), badge de estado grande (der).
3. Card "Avance del Proyecto": `%` grande (36px/800, verde), barra de
   progreso, borde izquierdo verde 4px (`.pdet-avance-card`).
4. Card "Servicios / Mantenimientos": grid de cards de servicio
   (`auto-fill minmax(320px,1fr)`), **clickeables** → abren un drawer
   lateral.
5. Card "Equipos e Instalaciones Intervenidas" (condicional): grid
   `auto-fill minmax(180px,1fr)` con badge de estado del equipo.

**Card de servicio** (`.pdet-svc-card`): nombre + fecha (izq), badge de
estado (der), barra de progreso con color por rango (`pg-gris <25%`,
`pg-ambar 25-59%`, `pg-azul 60-99%`, `pg-verde 100%`), bloque de "equipo
asignado" clickeable (abre modal, con `stopPropagation` para no disparar
también el drawer).

**Drawer lateral de cronograma** (patrón único en el portal, NO usa
`<app-modal>` — es un panel deslizante propio):
```css
.pdet-dw-overlay { position:fixed; inset:0; z-index:990; background:rgba(15,23,42,.45);
  display:flex; justify-content:flex-end; }
.pdet-dw {
  width:100%; max-width:480px; height:100%; background:#fff;
  box-shadow:-12px 0 40px rgba(0,0,0,.18);
  animation: pdetSlide .25s ease;   /* translateX(40px)→0 + fade */
}
@media (max-width:540px) { .pdet-dw { max-width:100%; } }  /* full-width en mobile */
```
⚠️ **Bug detectado**: el overlay usa `animation: pdetFade .18s ease` pero no
se encontró el `@keyframes pdetFade` definido — el fade de entrada del
overlay probablemente no está animando (solo el slide del panel sí). Vale la
pena que quien rediseñe esto lo revise/corrija.

Contenido del drawer: barra de avance del servicio, timeline vertical de
"Cronograma de actividades" (mismo patrón visual que la sección 6.6),
checklist de "Pasos del servicio", botón "Equipo" (reabre el modal). Cierre:
click en overlay, botón X, o tecla `Escape` (prioriza cerrar el modal si
ambos están abiertos). Bloquea scroll del body mientras está abierto.

**Modal de equipo del servicio** (SÍ usa `<app-modal>`, `maxWidth="640px"`):
lista de miembros con foto circular 76px (o iniciales con color hash),
nombre, badge de rol (dorado ★ si "Líder del Servicio", azul si "Técnico
Líder"), cargo, email (`mailto:`), teléfono (`tel:`).

Responsive: grid de 2 columnas → 1 columna en ≤700px.

### 6.4 Documentos (`/portal-cliente/documentos`)

**Layout**: `max-width:1200px; margin:0 auto`.

**Estructura**: header → filtros por tipo (chips horizontales, solo si hay
más de 1 tipo) → grid de cards (`auto-fill minmax(280px,1fr)`) o estado
vacío.

**Card de documento** (`.pdoc-card`, SÍ usa `var(--card-bg)` — se adapta a
dark mode correctamente): borde superior de 3px de color según tipo
(garantía azul `#3b82f6`, informe verde marca, otro morado `#8b5cf6`), ícono
44px, badge de tipo, título, proyecto/servicio, fecha, dos botones "Ver"
(abre en pestaña nueva) / "Descargar" (o "En procesamiento" en itálica si no
hay `url` aún). Hover: `translateY(-2px)`.

Filtros: chips pill, estado activo = fondo verde marca sólido.

### 6.5 Historial de Mantenimientos (`/portal-cliente/mantenimientos`)

**Layout**: `max-width:1400px; margin:0 auto` — la página más ancha del
portal. Única sección envuelta en un card único con glass real:
```css
.eh-section {
  background: rgba(255,255,255,.85);            /* dark: rgba(30,41,59,.75) */
  backdrop-filter: blur(10px) saturate(140%);
  border-radius: 16px;
  box-shadow: 0 10px 15px -3px rgba(0,0,0,.08), 0 4px 6px -4px rgba(0,0,0,.05);
}
```

**Estructura interna** (todo dentro de un único card):
1. Toolbar: contador "N de M equipos", buscador (ícono + input 240px),
   select de ubicación.
2. Chips de filtro por estado (Todos / Vigente-Operativo / Próximo a Vencer
   / Vencido), cada uno con contador, + botón "Limpiar" si hay filtros
   activos.
3. Tabla (`.eh-table`): #, Equipo (nombre + código + marca/modelo), Proyecto,
   Ubicación, Último Mtto., Próximo Mtto. (resaltado ámbar si vence en
   ≤30 días), Estado (badge), "Ver Detalles →".
4. Paginación (25 por página, `« ‹ 1 2 3 › »`).

Sistema de badges: `badge-success/warning/danger` (el "sistema A", igual al
dashboard) — coherente entre estas dos páginas, pero distinto al de
Proyectos/Detalle de Proyecto (ver sección 7).

Todos los tokens de color acá SÍ usan `var(--text-main)`, `var(--card-bg)`,
etc. con fallback hex — se adapta bien a dark mode, incluyendo el
`:host-context(html[data-theme="dark"])` explícito para el fondo glass.

### 6.6 Detalle de Equipo/Mantenimiento (`/portal-cliente/mantenimiento/:id`)

**Layout**: `max-width:1280px; margin:0 auto`. Grid principal de 2 columnas
`1fr 380px` (colapsa a 1 columna en ≤900px).

**Columna izquierda**:
1. Card "Estado del Mantenimiento": barra de progreso + 3 pasos con dots
   (Programado/En Proceso/Completado) + grid de metadatos 2 columnas
   (Proyecto+OT, Servicio+zona, fechas, duración, frecuencia, ubicación,
   alcance, observaciones — estos 3 últimos a ancho completo).
2. Card "Documentos Generados": grid de cards clickeables (mismo patrón de
   color por tipo que en 6.4: pre `#3b82f6`, final `#8b5cf6`, garantía
   `#f59e0b`).
3. Card "Ciclo de Vida del Equipo" — **timeline vertical** (línea + marcador
   circular + card de contenido por evento), coloreado por tipo:
   `completed`/`vigente` = verde `#16a34a`, `upcoming` = ámbar `#f59e0b`,
   `overdue` = rojo `#dc2626`. Los eventos vienen del historial de
   mantenimientos + un evento derivado calculado del próximo mantenimiento
   programado.

**Columna derecha**:
1. Card "Personal Técnico": lista con avatar de iniciales (fondo verde
   marca translúcido), nombre, cargo, tag de rol.
2. Card "Herramientas y Equipos": lista con ícono según tipo, nombre,
   marca/modelo, código, badge de estado de calibración (ok verde / warn
   ámbar / danger rojo, inferido de un prefijo emoji en el dato:
   `✓`/`⏳`/`⚠`).

Header propio: link "← Volver al Historial", título + subtítulo
(marca·modelo·código), badge de estado grande a la derecha.

Página 100% de solo lectura, sin modal ni drawer — únicos elementos
interactivos son los links de documentos y el hover en el timeline.

---

## 7. Inconsistencias y oportunidades de mejora detectadas

Esto es lo más accionable del documento — son cosas reales del código, no
apreciaciones estéticas, y son el mejor punto de partida para priorizar el
rediseño:

1. **Ancho de página inconsistente entre las 6 páginas**: Dashboard usa el
   100% del ancho disponible (grid de 12 columnas sin límite); las otras 5
   páginas usan `max-width + margin:0 auto`, pero con **4 valores
   distintos**: Proyectos y Documentos 1200px, Detalle de Proyecto 1100px,
   Mantenimientos 1400px, Detalle de Equipo 1280px. En una pantalla ancha,
   navegar entre páginas del portal hace que el contenido "salte" de ancho
   constantemente.

2. **Los cards NO son consistentes en cómo se adaptan al tema oscuro**:
   Dashboard y Mantenimientos usan glassmorphism real con `var(--card-bg)`/
   `var(--text-main)` y `:host-context(html[data-theme="dark"])` — se ven
   bien en ambos temas y dejan traslucir el fondo de partículas. Documentos
   también usa los tokens correctamente. **Pero Proyectos, Detalle de
   Proyecto y Detalle de Equipo usan `#fff`, `#111827`, `#e5e7eb`, etc.
   hardcodeados** — en dark mode esas 3 páginas muestran cards blancos
   opacos sobre fondo oscuro (rompe el tema, y tapa completamente el fondo
   de partículas que se supone es la seña de identidad del portal).

3. **Dos sistemas de badges de estado en paralelo, sin relación visual
   entre sí**: Dashboard/Mantenimientos usan `badge-success/warning/danger`
   (definidos globalmente en `styles.css`); Proyectos/Detalle de Proyecto
   usan `badge-ok/prog/err/pend` (definidos localmente, con paleta similar
   pero no idéntica: p.ej. `badge-ok` es verde `#d1fae5/#065f46` en un lado
   pero `badge-success` es `#dcfce7/#166534` en el otro — colores parecidos
   pero no iguales, un usuario atento nota la diferencia).

4. **Cada página inventó su propio prefijo de clases CSS** sin componentes
   compartidos: `ex-` (dashboard), `pp-` (proyectos), `pdet-` (detalle de
   proyecto), `pdoc-` (documentos), `eh-` (mantenimientos), `ped-` (detalle
   de equipo). No hay, por ejemplo, un solo componente `<status-badge>` o
   `<stat-card>` reusado — cada página reimplementa sus cards, sus badges y
   sus estados de loading/error/empty desde cero (con ligeras diferencias
   entre sí). Es la oportunidad más grande de simplificación para el
   rediseño: definir 4-5 componentes/patrones compartidos (card, badge,
   estado vacío, estado de carga, paginación) y que las 6 páginas los
   reusen.

5. **Solo Dashboard y Mantenimientos tienen filtros/búsqueda** — Proyectos y
   Documentos (que también son listas) no. Si un cliente tiene muchos
   proyectos o documentos, no hay forma de buscar/filtrar.

6. **Bug de animación**: el overlay del drawer de cronograma
   (`portal-proyecto-detalle`) referencia `animation: pdetFade` pero ese
   `@keyframes` no está definido en el archivo — el fade de entrada del
   overlay no está funcionando (revisar/corregir junto con el rediseño).

7. **Dos paradigmas de panel superpuesto conviviendo**: `<app-modal>`
   (centrado, estándar del proyecto) y el drawer lateral custom (solo en
   Detalle de Proyecto, para el cronograma). Ambos coexisten en la misma
   página. Vale la pena decidir de forma consciente cuál es el patrón para
   "ver más detalle sin salir de la página" y ser consistentes.

8. **Sin acceso directo a Mantenimientos desde el navbar**: la página de
   Historial de Mantenimientos y el Detalle de Equipo no están en los 3
   links del navbar (solo Dashboard/Proyectos/Documentos) — solo se llega
   por links internos. Confirmar si es intencional.

9. **No hay estado "warning" en el Toast** (solo success/error/info) — si
   el rediseño necesita avisos de tipo advertencia, hay que agregarlo.

10. **Loading states inconsistentes**: cada página define su propio
    `.spinner-ring` local en CSS en vez de usar el `<app-spinner>`
    compartido del proyecto — visualmente son casi idénticos pero es
    duplicación de código que el rediseño podría consolidar.

## 8. Reglas del proyecto que el rediseño debe respetar

Estas son convenciones ya establecidas en E-zyro (no específicas del
portal) que cualquier propuesta de diseño nueva debe seguir para encajar sin
fricción con el resto del sistema:

- **Layout full-width**: nunca `max-width + margin:0 auto` en el wrapper
  raíz de una página — usar `width:100% + box-sizing:border-box` (ver
  inconsistencia #1 arriba: 5 de las 6 páginas del portal violan esta regla
  hoy).
- **Modales**: siempre `<app-modal>` compartido, nunca overlay hecho a mano.
- **Sin sidebars por módulo**: si el rediseño agrega secciones nuevas
  (settings del portal, filtros avanzados, etc.), deben ser páginas
  completas navegadas por el navbar, no un layout master/detail con sidebar
  interna.
- **CSS de componente + dark mode**: usar `:host-context(html[data-theme="dark"])`,
  nunca `:root[data-theme="dark"]` directamente (no matchea por la
  encapsulación de estilos de Angular).
- **El body/main es dueño del color de fondo**: no hardcodear `background`
  en el wrapper raíz de cada página — dejar que `.portal-mode` (transparente,
  para ver las partículas) y las variables globales lo resuelvan.

## 9. Modelo de datos por página (resumen, todo `any` sin tipar en el service)

`PortalClienteService` (`src/app/core/services/portal-cliente.service.ts`):
`getDashboard()`, `getKpis()`, `getHistorial()`, `getProyectos()`,
`getProyectoDetalle(id)`, `getDocumentos()`, `getMantenimientoDetalle(id)`,
`getPortalPerfil()` (este último no se usa en ninguna de las 6 páginas
actuales — posible feature futura de perfil de cliente).

```ts
// Proyectos (lista)
{ id, nombre_proyecto, estado: 'activo'|'completado'|'cancelado'|'planificado',
  avance_pct: number, servicios_completados: number, total_servicios: number,
  fecha_inicio: string|null, fecha_fin_estimada: string|null }

// Detalle de Proyecto
{ proyecto: { nombre_proyecto, estado, avance_pct, fecha_inicio, fecha_fin_estimada },
  servicios: ServicioPortal[], equipos: [{ id, nombre, codigo, marca, modelo, estado }] }

ServicioPortal { id, nombre, descripcion, estado, fecha_programada, fecha_inicio,
  fecha_fin, progreso, equipo: MiembroServicioPortal[],
  cronograma: ActividadCronograma[], pasos: PasoServicio[] }
MiembroServicioPortal { id, nombre, apellido, cargo, foto_url, email, telefono, empresa, rol }

// Detalle de Equipo/Mantenimiento
{ equipo: { nombre, marca, modelo, codigo, estado_intervencion, ubicacion,
            observaciones, frecuencia_meses, proximo_mantenimiento, ultimo_mantenimiento },
  proyecto: { nombre, orden_trabajo },
  servicio: { nombre, zona_ejecucion, fecha_programada, fecha_inicio, fecha_fin,
              duracion_dias, alcance },
  personal: [{ nombre, cargo, rol }],
  herramientas: [{ tipo, nombre, marca, modelo, codigo, especificacion, cantidad }],
  documentos: [{ url, tipo: 'pre'|'final'|'garantia', titulo, fecha }],
  historial: [{ fecha_fin, fecha_inicio, servicio, proyecto, observaciones }] }

// Dashboard e Historial de Mantenimientos: array de equipos intervenidos
{ id, nombre, codigo, marca, modelo, ubicacion, proyecto,
  ultimo_mantenimiento, proximo_mantenimiento, estado_intervencion }

// Documentos
{ id, tipo, titulo, proyecto, servicio, fecha, url }
```

---

*Generado a partir de una lectura completa del código fuente el 2026-07-09.
No incluye capturas visuales — recomendado correr `npm start` y navegar
`/portal-cliente/dashboard` para ver el resultado real antes de proponer
cambios, especialmente el efecto de fondo de partículas y el glassmorphism,
que no se aprecian bien solo con valores CSS.*
