# Contexto — Elevación visual del módulo EPPs

> Documento de trabajo para no perder contexto entre sesiones.
> Fecha: 2026-07-02
> Backend: `C:\E-zyro\BACKEND` · Frontend: `C:\E-zyro-frontend`

## 1. Qué pidió el usuario

Importar el moodboard de Claude Design del proyecto **"Gestión de EPP
moodboards"** (`https://claude.ai/design/p/78b405c4-f597-4a51-a4f0-f3f44b9b5472`,
archivo `EPP Moodboards.dc.html`, turno **2** — "Elevación visual del módulo
EPPs — sobre el diseño actual") y aplicar ese estilo al módulo EPPs ya
funcional (ver `feedback_modal_appmodal` y memorias previas de este proyecto
para contexto de la convención de modales `<app-modal>`), incluyendo el flujo
completo de "proceso de entrega" (wizard), y adaptando todo a **tema oscuro**.

Acceso al proyecto de diseño requiere `/design-login` (autorización aparte de
`/login`) — ya autorizado en esta sesión.

## 2. Referencia de diseño (moodboard, turno 2, opciones 2a-2e)

- **2a** — Catálogo: vista tabla (+ toggle Grid/Tabla), columnas Nombre,
  Marca, Stock actual/mín. con barra de progreso, Precio, Estado (badge
  "Activo" verde / "⚠ Bajo mín." rojo), Acciones. Filas bajo mínimo con franja
  roja izquierda.
- **2b** — Entregas: tabla con avatar (iniciales) + nombre de técnico, chips
  de ítems, **indicador de firma** (✓ Firmada verde / sin firma), badge de
  estado (Registrada/Anulada), filas anuladas atenuadas y tachadas.
- **2c** — Modal "Nueva entrega": **wizard de 4 pasos** en el mock (Técnico →
  Ítems → Firma → Confirmación), con stepper visual (círculos verdes ✓
  completados, azul actual, gris pendiente).
- **2d** — Modal "Detalle de entrega": receptor con avatar, lista de ítems,
  caja de firma (imagen o placeholder "Sin firma"), footer con botones
  "Anular" (outline) / "Generar PDF" (azul sólido).
- **2e** — Paleta: fondo gris `#F3F4F6`, verde `#16A34A` (EPPs/positivo), azul
  `#2563EB` (navegación/acciones), rojo `#DC2626` (stock crítico), tipografía
  Inter en toda la app.

## 3. Qué se implementó (commit pendiente de verificar en este branch)

### Decisiones de diseño (adaptaciones deliberadas del mock)

- **Wizard de 3 pasos, no 4.** El "paso 4" del mock es en realidad una barra
  de confirmación final, no una pantalla aparte — se implementó como parte
  visible del paso 3 (Firma), no como paso independiente.
- **Indicador de firma sin estado "Pendiente".** El mock muestra ✓ Firmada /
  ✎ Pendiente (ámbar) para dos entregas distintas, pero el modelo de datos
  real no tiene un flujo de "firma pendiente de completar" — la firma se
  captura o no en el momento de crear la entrega. Se implementó solo
  ✓ Firmada (verde) / "Sin firma" (gris neutro), fiel a los datos reales, sin
  inventar un estado que no existe en el backend.
- **Un solo color para "bajo mínimo"**, no dos (el mock usa rojo Y ámbar para
  filas que visualmente parecen el mismo caso "en/bajo mínimo" — se unificó a
  rojo, que es el color del badge en ambos casos del mock).
- **Barra de stock**: ancho = `min(100, stock_actual / stock_min * 100)`,
  color por separado (verde si stock > mínimo, rojo si ≤ mínimo) — el relleno
  no comunica salud por sí solo, el color sí.
- **Cantidad con botones +/-** en el paso 2 del wizard de entrega (antes era
  un `<input type="number">` suelto), clamped a `stockDisponible` (no se
  permite exceder el stock real, a diferencia del mock que muestra un estado
  de "excede stock" — preferimos impedirlo de raíz).

### Archivos modificados

- `src/app/features/logistica/components/epp-tabla/epp-tabla.component.ts` —
  agrega `vistaCatalogo` (grid/tabla), mapa de marcas (id→nombre) para la
  columna Marca, helpers `bajoMinimo()`, `barraStockPct()`,
  `inicialesEmpleado()`. Elimina `resumenItems()` (ya no se usa, reemplazado
  por chips).
- `.../epp-tabla/epp-tabla.component.html` — reescrito: toggle grid/tabla,
  vista tabla nueva del catálogo, tabla de entregas con avatar + indicador de
  firma + chips de ítems, modal de detalle rediseñado (receptor, ítems, caja
  de firma, footer Anular/Generar PDF).
- `.../epp-tabla/epp-tabla.component.css` — reescrito con las clases nuevas +
  bloque `:host-context([data-theme="dark"])` completo.
- `.../epp-entrega-modal/epp-entrega-modal.component.ts` — agrega estado
  `paso: 1|2|3`, navegación (`irPaso`, `siguiente`, `atras`), getters
  `puedeAvanzarPaso1/2`, `tecnicoSeleccionado`, `totalItems`,
  `resumenItemsTexto`, `iniciales()`, y `incrementar()/decrementar()` para los
  botones +/-. `ngAfterViewInit` solo inicializa el canvas si `paso === 3`
  (el canvas no existe en el DOM hasta llegar a ese paso, al estar detrás de
  un `@if`).
- `.../epp-entrega-modal/epp-entrega-modal.component.html` — reescrito con
  stepper de 3 pasos + contenido condicional por paso + footer con
  Atrás/Siguiente/Registrar contextual.
- `.../epp-entrega-modal/epp-entrega-modal.component.css` — reescrito:
  estilos del stepper, tarjeta de técnico seleccionado, filas de ítems con
  botones +/-, estados de firma vacía/llena, resumen final, dark mode.
- `.../epp-form-modal/epp-form-modal.component.css` — **fix real de bug**:
  usaba `var(--bg-soft, #f8fafc)`, una variable que **no existe** en
  `styles.css` (nunca se definió, ni en tema claro ni oscuro) — el fallback
  literal se aplicaba siempre, rompiendo el tema oscuro silenciosamente. Se
  reemplazó por `var(--input-bg)`/`var(--hover-bg)`, que sí están definidas
  para ambos temas. Mismo fix aplicado en los otros dos componentes (no
  tenían el bug pero se dejaron con las variables correctas de una vez).

### Verificación hecha

- `npm run build` limpio (sin errores nuevos, solo warnings preexistentes no
  relacionados).
- **NO se pudo verificar visualmente en navegador** en esta sesión: no hay
  `chromium-cli` ni Playwright con navegador instalado en este entorno, y
  generar una sesión de login válida requeriría insertar un registro de
  sesión falso en la tabla de sesiones activas de producción (`verificar_token`
  en `app/core/security.py` valida el JWT contra `sesion_activa()`, no solo
  la firma) — no se hizo sin autorización explícita del usuario.

## 4. Cómo retomar / verificar pendiente

1. `cd C:\E-zyro-frontend && npm run start` (puerto 4200).
2. Login normal con una cuenta real → Logística → pestaña **EPPs**.
3. Revisar: toggle Grid/Tabla en Catálogo, tabla de Entregas (indicador de
   firma, chips), modal "Nueva entrega" (los 3 pasos, botones +/- de
   cantidad, canvas de firma), modal de detalle de una entrega existente.
4. Repetir con el botón de tema oscuro del navbar activado.
5. Si algo se ve mal alineado o los colores no contrastan bien en oscuro,
   son ajustes de CSS puntuales en los 3 archivos `.css` listados arriba —
   todos los colores nuevos están en bloques `:host-context([data-theme="dark"])`
   al final de cada archivo, fáciles de ubicar y tocar.

## 5. Pendiente de la conversación (fuera de este tema visual)

Después de EPPs, el usuario planea migrar datos de **Ingresos** (con la regla
ya acordada: ingresos anteriores al 24/06 quedan solo como historial, sin
sumar a inventario; desde el 24/06 en adelante sí se suman al stock actual).
