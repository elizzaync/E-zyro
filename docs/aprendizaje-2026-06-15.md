# Aprendizaje semanal del 2026-06-15

Período analizado: `docs/2026-06-08.md` a `docs/2026-06-12.md` (únicos resúmenes diarios disponibles en `main` dentro de los últimos 7 días; 06-13 y 06-14 todavía no tienen archivo generado).

## Patrones recurrentes esta semana

### 1. Consultas N+1 / falta de batching en el backend (presente los 5 días)

**Qué es**: dentro de un `for` sobre N elementos (cajas, equipos, empleados, facturas, días del mes...), se ejecuta una query adicional por cada elemento, en vez de traer todo de una vez con `IN (...)` / `GROUP BY` / `JOIN` y resolver con un diccionario en memoria. Es el clásico **"N+1 query problem"**.

**Dónde apareció**:
- `BACKEND/app/routers/caja_chica.py:75-85` (08-06, `2c8e2f34`): `_caja_out` llama a `cc._totales(db, c.id)` por cada `CajaChica` → N consultas `GROUP BY` extra.
- `BACKEND/app/routers/operaciones.py:2876-2908` (09-06, `acc7884b`): hasta 2 SELECTs extra a `historial_mantenimiento` por cada equipo de la lista.
- `BACKEND/app/routers/indicadores.py:87-88` (09-06, `bb7ff7d8`): `_saldo(...)` + lookup de `Usuario` por cada empleado.
- `BACKEND/app/routers/personal.py:152-156` (09-06, `bb7ff7d8`): un `SUM` separado por cada una de hasta 50 `EppEntrega`.
- `BACKEND/app/routers/operaciones.py:3657-3661` (10-06, `525bd9a3`): doble round-trip cuando el filtro por zona no devuelve resultados.
- `BACKEND/app/routers/rrhh_asistencia.py:196-224` (11-06, `a53338b1`): `_contar_advertencias` ejecuta un `COUNT` por empleado.
- `BACKEND/app/services/scheduler_service.py` (`_aviso_fin_almuerzo`, ~310-380, 11-06, `37c7b413`): 4 queries (`TurnoEmpleado`, `Turno`, `Empleado`, `Usuario`) por cada registro `en_almuerzo`, repetido cada 5 minutos.
- `BACKEND/app/services/scheduler_service.py` (`_alertas_vencimientos`, 11-06, `c2bd336b`): un `db.query(Equipo/Proveedor/Cliente)` extra por cada `Calibracion`/`Factura` solo para obtener el nombre.
- `BACKEND/app/routers/asistencia.py:925-938` (`_filas_export`, 12-06, `43ac3d64`): para un reporte mensual, `_resumen_dia` se llama ~30 veces y cada llamada repite 3 queries completas, incluida la de "empleados activos" que ni depende del día.
- `BACKEND/app/routers/rrhh_asistencia.py:231,651` (12-06, `68a4a97a`): doble bucle `for emp → for dia` con filtro lineal `[r for r in regs if r.fecha_hora.date() == dia]` en cada combinación → O(empleados × días × registros).

**Por qué importa**: cada query extra es un round-trip a la BD (red + planner + locks). Con N=10 no se nota, pero con N=50-250 (los 245 equipos de TALMA, un reporte mensual con 30 días × decenas de empleados, o un scheduler que corre cada 5 min) la latencia y la carga sobre la BD crecen de forma lineal o peor, y se nota en producción.

**Lo más relevante**: el propio código YA tiene el patrón correcto en varios sitios — `regs_por_emp`/`solis_por_emp` y `detalle_diario` en `rrhh_asistencia.py`, y las consultas de `portal_cliente.py`/`operaciones.py` del 10-06 que el resumen señala explícitamente como "correctamente batcheadas". No es un problema de no conocer la técnica, sino de **no aplicarla de forma consistente a todo el código nuevo**.

**Regla de oro**: antes de escribir `for x in lista: db.query(...)`, preguntarse "¿puedo traer esto con un `WHERE id IN (...)` / `GROUP BY` antes del bucle y armar un `dict` para lookup O(1) dentro del bucle?". Concepto a estudiar: **N+1 query problem** y **batching con `IN`/`GROUP BY` + diccionario de lookup**.

---

### 2. Cómputo costoso repetido dentro de `build()` / getters sin memoizar (Flutter)

**Qué es**: funciones que recorren listas, parsean strings o calculan diffs (O(n) o peor) se ejecutan dentro de `build()` o de getters llamados varias veces por `build()`, repitiéndose en cada `setState` aunque el resultado no haya cambiado.

**Dónde apareció**:
- `e_zyro_app/lib/screens/finanzas/pantalla_cuentas_cobrar.dart` y `pantalla_cuentas_pagar.dart` (08-06, `02ea5a86`): `onChanged: (_) => setState(() {})` en el campo de monto reconstruye TODO el formulario (todos los `CheckboxListTile`) y recalcula el getter `_totalAplicado` (itera `_seleccionados`) en cada pulsación de teclado.
- `e_zyro_app/lib/screens/almuerzo/tarjeta_almuerzo.dart:62-69` (10-06, `bbdbb098`): `Timer.periodic(1s)` llama `setState({})` y reconstruye toda la tarjeta (Container, BoxDecoration, BoxShadow, ícono...) solo para refrescar un `Text` con el cronómetro.
- `e_zyro_app/lib/screens/pantalla_detalle_servicio.dart:570,572,606-607` (10-06, `25b0e522`): los getters `_progresoTareas` (`.where().length`) y `_todasTareasCompletas` (`.every()`) se llaman 2 veces cada uno dentro del mismo `build()`, más un tercer recorrido inline equivalente.
- `e_zyro_app/lib/screens/detalle_servicio/tab_equipos_intervenidos.dart:1025,1090` (10-06, `a24bda6b`): `_eppsDisponibles`/`_personalNoAsignado` reconstruyen un `Set` y filtran listas en cada `build()` del formulario, es decir en cada cambio de cualquier campo.
- `e_zyro_app/lib/screens/pantalla_auditoria.dart:700` (12-06, `5d27b906`): `_computeDiff(...)` (armado de `Set`, `sort`, `jsonEncode`) se ejecuta en cada `build()` de la tarjeta, incluso con el accordion colapsado.
- `e_zyro_app/lib/screens/pantalla_auditoria.dart:1035` (12-06, `5d27b906`): `_parseUserAgent(...)` (varias `RegExp.firstMatch`) se recalcula en cada `build()` de la sección de contexto, en cada expandir/colapsar.

**Por qué importa**: en Flutter, `setState` reconstruye el subárbol completo del widget. Si dentro de `build()` hay trabajo O(n) (iterar listas, parsear strings, calcular diffs), ese costo se paga en cada frame/interacción, no solo cuando el dato realmente cambió. Con listas/objetos grandes (comprobantes, tareas, eventos de auditoría) esto se traduce en jank perceptible.

**Regla de oro**: si un valor depende solo de datos que NO cambian en cada `build()` (p. ej. el `item` de una tarjeta ya creada, o una lista que solo cambia cuando el usuario la edita), calcularlo UNA vez (`initState`, `late final`, o guardarlo en una variable de estado) y reutilizarlo. Si solo una parte pequeña de la UI cambia con frecuencia (un cronómetro, un total), aislarla en un widget hijo con `ValueNotifier`/`ValueListenableBuilder` para no reconstruir el resto. Conceptos a estudiar: **memoization** y **"widget rebuild scoping"** en Flutter.

---

### 3. Listas largas construidas de forma "eager" (`ListView` con `children`/`.map` en vez de `ListView.builder`)

**Dónde apareció**:
- `e_zyro_app/lib/screens/pantalla_dashboard_operaciones.dart:113-183` (10-06, `a24bda6b`): `children: [... for (final s in _data!.servicios) Card(...)]`.
- `e_zyro_app/lib/screens/pantalla_control_asistencias.dart:123` (11-06, `39a54401`): `..._data!.items.map(_tarjetaEmpleado)` dentro de un `ListView`, cada tarjeta con `Container`+`BoxShadow`+`Row`/`Column` anidados.

**Por qué importa**: `ListView(children: [...])` construye TODOS los widgets de la lista de inmediato, aunque solo unos pocos sean visibles. Con pocos elementos no se nota, pero el resumen del 11-06 ya advierte que "en empresas con plantillas grandes esto es costoso en cada rebuild". Es la misma idea de fondo que el patrón 2 (trabajo repetido sin necesidad), aplicada a la construcción del árbol de widgets en vez de a un cálculo.

**Regla de oro**: cualquier lista cuyo tamaño dependa de datos del backend (servicios, empleados, equipos, registros) debería nacer con `ListView.builder`/`ListView.separated` (`itemCount`/`itemBuilder`), no como optimización posterior. Concepto a estudiar: **lazy loading / virtualización de listas**.

---

### 4. Helper o patrón correcto introducido, pero no aplicado de forma consistente al resto del código nuevo del mismo commit/módulo

**Qué es**: en el mismo día/commit se introduce una solución correcta para un problema (helper, conversión, validación), pero otras partes del código nuevo con exactamente el mismo problema no la usan.

**Dónde apareció**:
- 09-06 (`55a195c5` + `78be30ac`/`946b2ed7`/`16be74cb`): se crea `app/core/tz.py` (`to_lima`, `fmt_lima_iso`) y se aplica en `seguridad.py`, `auditoria.py`, `notificaciones.py`, `operaciones.py` — pero los endpoints nuevos del Portal Cliente (`portal_cliente.py`, mismo día) usan `.isoformat()` directo, sin pasar por `tz.py`.
- 10-06 (`operaciones.py:3293-3300`, `3dead75c`): si `body.lider_id` no corresponde a un empleado de la empresa, el cambio se ignora en silencio (200 OK sin aplicar nada) — mientras que la validación análoga para `body.responsable_id`, en el MISMO commit y a pocas líneas, sí lanza `HTTPException(404, ...)`.
- 12-06 (`rrhh_asistencia.py:1040`, `8b2b22a0`, no corregido por `91295bf7`): el reporte de horas extra usa `emp.area` crudo (UUID), mientras `91295bf7` —del mismo día— ya creó `_resolve_area`/`_area_cache` y lo aplicó en `resumen_asistencia`, `/diario` y `_build_resumen_full`.
- 12-06 (`rrhh_asistencia.py:231,651`, `68a4a97a`): `resumen_asistencia`/`_build_resumen_full` filtran registros con escaneo lineal por día, mientras `detalle_diario` —en el mismo archivo— ya agrupa los registros en un `dict[date, list]` antes del bucle.

**Por qué importa**: no son errores de desconocimiento — la solución correcta está a centímetros, en el mismo diff. Son inconsistencias de cobertura que una pasada final de revisión ("¿aplico este mismo fix a todos los endpoints/reportes que tocan este dato?") detectaría antes del commit.

**Regla de oro**: cuando un commit introduce un helper/conversión/validación para resolver un problema, buscar (`grep`) los demás lugares del mismo commit que tocan el mismo dato/condición y aplicar el mismo fix ahí también, o documentar por qué no aplica. Concepto a estudiar: **DRY** y revisión de consistencia "self-diff" antes de cerrar un commit grande.

---

## Otros patrones a vigilar (un solo día de evidencia hasta ahora — no confirmados como recurrentes)

- **Llamadas HTTP independientes en serie en vez de `Future.wait`**: el 09-06 (`8f739e53`/`612a1f7f`) se repitió en 3 pantallas distintas (`pantalla_indicadores.dart:40-41`, `pantalla_vacaciones.dart:42-44`, `pantalla_mi_espacio.dart:71-72`), mientras que `bc113fd4` del mismo día sí usa `Future.wait([...])` en otras dos pantallas. Si reaparece en próximas semanas, será un patrón confirmado.
- **`try/except` silencioso sin logging**: el 11-06 aparecieron dos casos (`operaciones.py:196-211` y `asistencia.py` en `_notificar_marca_en_revision`) donde una excepción en un flujo secundario (notificación) se traga sin registrar nada. Como mínimo, todo `except` que no relanza debería loggear con `logger.warning`/`logger.exception`.
