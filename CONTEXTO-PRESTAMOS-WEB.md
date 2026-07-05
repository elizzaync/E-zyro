# Préstamos de Equipo — módulo web en Logística

Fecha: 2026-07-05.

## Qué se hizo

Se agregó visibilidad web (rol de monitoreo/gestión de Logística) para el módulo
**Préstamo de Equipos/Herramientas** (`/prestamos`, backend `app/routers/prestamo.py`),
que hasta ahora solo existía en la app móvil y no tenía ninguna pantalla ni
llamada HTTP en el frontend Angular. No es lo mismo que "Retornos" — ver
`CONTEXTO-*` u otras notas de la sesión si hace falta esa distinción.

**No se tocó el backend.** Todos los endpoints usados ya existían y están en
producción (usados por la app móvil desde antes). Solo se construyó el
consumo web.

## Archivos nuevos

- `src/app/features/logistica/components/prestamos-tabla/prestamos-tabla.component.ts`
- `src/app/features/logistica/components/prestamos-tabla/prestamos-tabla.component.html`
- `src/app/features/logistica/components/prestamos-tabla/prestamos-tabla.component.css`

## Archivos modificados

- `src/app/features/logistica/logistica.models.ts` — se agregaron las interfaces
  `PrestamoItem`, `PrestamoEstado`, `Prestamo` (al final del bloque de Retornos,
  antes de Incidencias). **Ojo:** a diferencia de `Retorno` (que el backend
  serializa en camelCase), el backend de `/prestamos` serializa en **snake_case
  nativo** (`schemas/prestamo.py`) — las interfaces respetan eso a propósito,
  no es un error de tipeo.
- `src/app/core/services/logistica.service.ts` — se agregó el import de `Prestamo`
  y 4 métodos nuevos, todos apuntando a `${this.api}/prestamos` (prefijo propio,
  **no** `/logistica/prestamos`):
  - `getPrestamos(estado)` → `GET /prestamos?estado=`
  - `entregarPrestamo(id, body)` → `POST /prestamos/{id}/entregar`
  - `rechazarPrestamo(id, observacion)` → `POST /prestamos/{id}/rechazar`
  - `confirmarDevolucionPrestamo(id, aceptar, observacion?)` → `POST /prestamos/{id}/confirmar-devolucion`
- `src/app/features/logistica/logistica.component.ts` — nuevo tipo de tab
  `'prestamos'`, import + registro de `PrestamosTablaComponent`.
- `src/app/features/logistica/logistica.component.html` — nuevo botón de tab
  "Préstamos" (mismo bloque `@if (!esOperativo)` que Retornos/Incidencias/
  Histórico Legacy, o sea solo visible para logística/admin, no para técnicos
  ni jefes de operaciones) + rama de contenido `<app-prestamos-tabla>`.

## Qué cubre la pantalla nueva

Bandeja tipo la de Retornos, filtrable por estado
(`solicitado | por_recibir | entregado | devuelto | confirmado | rechazado`).
Al abrir el detalle de un préstamo, las acciones disponibles cambian según el
estado (igual que el backend las restringe):

- **solicitado** → Logística puede **Entregar** (con firma capturada en un
  canvas propio, requerida por el backend — `firmaEntregadorUrl`) o **Rechazar**
  (con motivo).
- **por_recibir** → solo lectura; el backend exige que el TÉCNICO firme la
  recepción desde la app móvil (segunda firma), eso no se replicó en web
  a propósito (es una acción de campo, no de oficina).
- **entregado** → solo lectura, equipo en uso en el servicio.
- **devuelto** → Logística puede **Confirmar recepción** (acepta la devolución,
  el backend registra la bitácora de retorno del equipo) u **Observar**
  (rechaza la devolución con un motivo, queda pendiente de corrección por el técnico).
- **confirmado / rechazado** → histórico, solo lectura.

## Qué NO se hizo (limitaciones conocidas, a propósito por alcance)

- No se agregó vista "por servicio" (`GET /prestamos/servicio/{id}`) dentro del
  detalle de servicio en Operaciones — solo la bandeja global de Logística.
- No hay generación de PDF/comprobante de entrega (como sí existe para
  Requerimientos en `requerimientos.component.ts`).
- No se replicó el mecanismo de "firma guardada" (`GET /permisos/mi-firma`) que
  usa el modal de Requerimientos — aquí la firma se dibuja de cero cada vez.
- No se tocó el bloqueo "cinema-seat" (`bloquear-firma`/`liberar-firma`) porque
  esos endpoints protegen la firma de RECEPCIÓN del técnico (acción de campo),
  no la de entrega de logística.

## Verificación hecha

`npx ng build --configuration development` — build exitoso, sin errores nuevos
(un warning preexistente en `equipo-form-modal` no relacionado).
**No se probó manualmente en navegador** (no se levantó `ng serve`) — antes de
dar esto por cerrado, conviene entrar como usuario de logística y probar el
flujo real: ver la bandeja, entregar un préstamo de prueba (firmando), y
confirmar una devolución.

## Cómo revertir si algo falla

1. Eliminar la carpeta `src/app/features/logistica/components/prestamos-tabla/`.
2. En `logistica.models.ts`: quitar el bloque `// ── Préstamos de equipo (HU-FASE5) ──`
   (interfaces `PrestamoItem`, `PrestamoEstado`, `Prestamo`).
3. En `logistica.service.ts`: quitar el import `Prestamo` y el bloque
   `// ── Préstamos de equipo (router aparte...) ──` (4 métodos).
4. En `logistica.component.ts`: quitar el import de `PrestamosTablaComponent`,
   el tipo `'prestamos'` del union type `TabLogistica`, y la entrada en el
   array `imports` del `@Component`.
5. En `logistica.component.html`: quitar el botón de tab "Préstamos" y la rama
   `@else if (tab === 'prestamos')`.
6. Como alternativa más simple: `git diff`/`git checkout --` sobre estos 4
   archivos modificados + `git clean` sobre la carpeta nueva, ya que todo quedó
   en commits separados de esta tarea (ver `git log` de esta fecha).

Nada de esto toca el backend ni la base de datos — es 100% reversible sin
riesgo de pérdida de datos, ya que solo agrega una forma de LEER/ACTUAR sobre
filas que ya existían en la tabla `prestamo`/`prestamo_item` desde antes.
