# Plan MVP — App Móvil E-Zyro (igualar y superar la web)

> Objetivo: cerrar las brechas detectadas en el análisis para tener una app **robusta, empresarial y 100% funcional con lógica consistente**.
> Base: hallazgos sobre `E-zyro-app/e_zyro_app` y `E-zyro-Backend` (2026-05-28).
> Leyenda esfuerzo: **S** ≤ medio día · **M** 1-2 días · **L** 3-5 días.
> Prioridad: **P0** bloqueante (seguridad/lógica) · **P1** paridad con web · **P2** superar web / calidad.

---

## Estado de avance
- ✅ **Fase 0** — Seguridad y reglas de negocio (backend enforcement + sin bypass en móvil). *Pendiente: solo-lectura al estar Completado.*
- ✅ **Fase 1A** — `ApiResult<T>` + errores con causa real en las mutaciones del detalle (`proyecto_service.dart`). *Pendiente: migrar el resto de servicios.*
- ✅ **Fase 3** — paridad: lógica de fases compartida, stepper de 4 fases, checklist de Preparación + botón Iniciar con candado, pestaña Equipos/Herramientas en solicitar, edición de cantidad de materiales asignados/solicitados. *Nota: `clase` en el detalle no se añadió porque el backend no la provee (igual que la web).*
- ✅ **Fase 2** — tiempo real: el detalle abre un WS al room del servicio (`ChatService.eventos`) y refresca borrador + recepción al vuelo. Backend emite `requerimiento_actualizado` al aprobar/firmar. **Además se corrigió un error de sintaxis preexistente en `logistica.py` (línea 1190, mal merge) que impedía cargar TODO el router de logística.**
- ✅ **Fase 1B/1C** — cola offline genérica (`accion_pendiente`, DB v5) para toggle de tarea, firma de recepción y notas; drena en `_triggerSync` + al reconectar; badge de pendientes en el AppBar; estado `enqueued` en `ApiResult`. UI optimista con rollback en el toggle. *El borrador NO se encola offline a propósito (IDs de servidor + es función colaborativa en tiempo real).*
- ⬜ Fase 4, 5, y solo-lectura en Completado.

## Resumen de fases

| Fase | Tema | Prioridad | Esfuerzo |
|---|---|---|---|
| 0 | Seguridad y reglas de negocio (backend + móvil) | P0 | M |
| 1 | Robustez: errores con causa + cola offline | P0 | L |
| 2 | Tiempo real (borrador + recepción) | P1 | M |
| 3 | Paridad de features con la web | P1 | M |
| 4 | Superar a la web | P2 | M |
| 5 | Arquitectura, seguridad de datos y tests | P2 | L |

**Definición de "MVP listo":** Fases 0, 1, 2 y 3 completas. Fases 4-5 son endurecimiento posterior.

---

## FASE 0 — Seguridad y reglas de negocio · P0 · M

**Problema:** las reglas ("solo Jefe finaliza", "iniciar requiere checklist", "Completado = solo lectura") están **solo en la UI**; el backend `PATCH /operaciones/servicio/{id}/estado` no valida nada y el popup del móvil expone el bypass.

### Backend (`E-zyro-Backend`)
- [ ] En `actualizar_estado_servicio` (`operaciones.py:602`):
  - Rechazar con **403** si el usuario no es jefe/admin y el destino es `Completado` o `Cancelado`.
  - Para `En_Proceso`: validar server-side el checklist de Fase 1 (equipo ≥1, todas las tareas con responsable, sin borrador sin enviar, sin pendientes de entrega) → 409 con `detail` explicando qué falta.
  - Bloquear cualquier cambio si el servicio ya está `Completado`.
- [ ] Mismo criterio de rol en `actualizar_estado_procedimiento` y en mutaciones de notas/borrador si aplica.
- [ ] Crear un `Depends` reutilizable `requiere_rol(...)` para no repetir lógica.
- *(Esto también tapa el mismo hueco en la web.)*

### Móvil
- [ ] **Eliminar el `PopupMenuButton` de estado** del AppBar (`pantalla_detalle_servicio.dart:208-233`).
- [ ] Reemplazar por botones con lógica:
  - **"Iniciar"** (solo visible en `Pendiente`) bloqueado hasta cumplir checklist (ver Fase 3, `motivosInicio`).
  - **"Finalizar"** (solo `_puedeFinalizar` y `progreso==100`).
  - Estado `Completado` → toda la pantalla en solo-lectura (deshabilitar toggles, sheets, enviar, firmar).
- [ ] Manejar el 403/409 del backend mostrando el `detail`.

**Aceptación:** un técnico no puede cerrar/cancelar ni iniciar sin checklist, ni desde la UI ni golpeando el API directo.

---

## FASE 1 — Robustez: errores con causa + cola offline · P0 · L

**Problema:** 36 `catch (_) {}` en `proyecto_service.dart` ocultan la causa; y solo evidencias/asistencia se encolan offline — firma, toggle, borrador y notas se pierden sin red.

### 1A. Resultado tipado en la capa de servicios (S-M)
- [ ] Introducir `ApiResult<T>` (`ok`, `data`, `errorKind: network|auth|server|validation|notFound`, `message`).
- [ ] `ApiClient` traduce status → `ApiResult` (reusar `_extractDetail`). Dejar de tragar errores.
- [ ] Migrar `proyecto_service.dart` (y luego el resto) a devolver `ApiResult`. La UI muestra causa real + acción ("Reintentar").

### 1B. Cola offline genérica (M-L)
- [ ] Tabla `accion_pendiente` en `local_db` (tipo, payload JSON, reintentos, createdAt) — espejo del patrón de `evidencia_local_repo`.
- [ ] Encolar cuando no hay red / falla por red: `toggleProcedimiento`, `agregarItemBorrador`, `removerItemBorrador`, `enviarBorrador`, `firmarRequerimiento`, notas CRUD.
- [ ] Drenar la cola en `sync_service.procesarTodo` y al recuperar conectividad; reintentos con tope (5) + descarte controlado.
- [ ] Badge/indicador "N acciones pendientes de sincronizar" (reusar `pendientesEvidenciaNotifier` → notifier genérico).

### 1C. UI optimista con rollback (S)
- [ ] `toggleProcedimiento`: aplicar cambio local inmediato y revertir si falla (como la web). Igual para marcar comunicado leído.

**Aceptación:** sin red, las acciones críticas se guardan y reenvían solas; los errores muestran causa; nada se pierde en silencio.

---

## FASE 2 — Tiempo real · P1 · M

**Problema:** el borrador (anti-duplicidad) no es realtime en móvil; la web usa WebSocket.

- [ ] En `_DetalleServicioScreenState` suscribir `FcmFlutterService.messageStream`:
  - tipo `borrador_actualizado` + `servicio_id` → `_reloadBorrador()`.
  - tipo `requerimiento`/`recepcion` aprobado/firmado → recargar `reqsRecepcion`.
- [ ] Throttle 10-15s para no saturar (patrón ya existente `_throttledDetailLoad`).
- [ ] (Opcional superior) conectar al WS `/ws/chat/servicio/{id}` que ya emite `borrador_actualizado`, igual que la web, para latencia menor que FCM.
- [ ] Backend: asegurar que `agregar/quitar/enviar` borrador emite la notificación a los miembros del servicio.

**Aceptación:** dos dispositivos en el mismo servicio ven el borrador y la recepción actualizarse en vivo.

---

## FASE 3 — Paridad de features con la web · P1 · M

- [ ] **Lógica de fases compartida** `lib/utils/fase_servicio.dart` (espejo de `fase-servicio.ts`: `faseActiva`, `faseClase`).
- [ ] **Stepper visual de 4 fases** en el Header (Preparación/En sitio/Ejecución/Cierre).
- [ ] **Checklist Fase 1 + candado "Iniciar"**: getters `motivosInicio`/`puedeIniciar` (equipo, tareas con responsable, materiales gestionados); botón bloqueado con tooltip de lo que falta.
- [ ] **3er modo en "Solicitar material": Equipos/Herramientas** del inventario:
  - Añadir campo `clase` (`material|herramienta|equipo`) a `ItemMaterial` y al borrador.
  - Endpoint de búsqueda de equipos (reusar `/logistica/equipos?q=&estado=operativo` o equivalente del backend móvil).
- [ ] **Editar cantidad** de materiales asignados/solicitados cuando `puedeEditar` (no entregado/aprobado).
- [ ] Badge de **comunicados no leídos** y de evidencias por etapa, como la web.

**Aceptación:** el móvil tiene, función por función, lo que la web ofrece en `/operaciones/servicio/:id`.

---

## FASE 4 — Superar a la web · P2 · M

- [ ] **Firma → Cloudinary** (no base64 en el JSON): subir como en `/permisos/guardar-firma` y enviar la URL. Reduce payload, evita 413 y deja la firma reutilizable.
- [ ] **Equipos intervenidos**: el móvil ya usa backend real (la web sigue con MOCK) — pulir esta vista y exponer KPIs por zona.
- [ ] **Deep-links de push**: abrir directamente la tarea/tab correcto desde la notificación (equivalente a `?abrirTareaId=` de la web).
- [ ] **Pre-informe PDF** unificado: idealmente generarlo en backend (`GET /operaciones/servicio/{id}/informe.pdf`) para un único formato de verdad web+móvil.
- [ ] Acciones rápidas offline-aware (cámara de evidencia ya es fuerte: destacarlo en UX).

---

## FASE 5 — Arquitectura, seguridad de datos y tests · P2 · L

- [ ] **Partir `pantalla_detalle_servicio.dart`** (~2.800 líneas) en archivos por tab (`tabs/procedimientos_tab.dart`, `materiales_tab.dart`, `recepcion_sheet.dart`, etc.).
- [ ] **Gestión de estado**: un `ChangeNotifier`/Riverpod por pantalla para evitar recargas completas y desincronización entre tabs (p. ej. firmar refresca el Header).
- [ ] **Roles como enum/constantes** (`app_session.dart:49`) en vez de comparar strings sueltos; mapear desde un único catálogo de roles del backend.
- [ ] **`flutter_secure_storage`** para el token (hoy en `SharedPreferences` plano).
- [ ] **Tests**: unit de `fase_servicio.dart` y reglas de permiso; servicios con `ApiClient` mockeado; widget test de los flujos críticos (firma, enviar borrador, iniciar/finalizar).
- [ ] CI: `flutter analyze` + `flutter test` en cada push.

---

## Orden de ejecución sugerido

1. **Fase 0** (seguridad) — es el riesgo real y es rápido.
2. **Fase 1A** (errores tipados) antes de tocar más lógica — base para todo.
3. **Fase 3** (paridad: fases + iniciar + equipos/herramientas) — valor visible.
4. **Fase 2** (realtime) — cierra la metodología anti-duplicidad.
5. **Fase 1B/1C** (cola offline + optimista) — endurecimiento.
6. **Fases 4 y 5** — superar a la web y calidad sostenible.

## Riesgos / dependencias
- Las Fases 0 y 2 tocan **backend compartido**: coordinar para no romper la web (de hecho la mejora).
- El campo `clase` y la búsqueda de equipos dependen de que el backend móvil exponga el inventario de equipos/herramientas (verificar endpoint).
- La cola offline genérica debe respetar el orden (no enviar borrador antes de que sus ítems estén encolados).
