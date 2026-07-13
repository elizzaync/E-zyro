# Aprendizaje semanal — 2026-07-13

Patrones observados en los hallazgos de los resúmenes diarios del **2026-07-06 al 2026-07-10**.

---

## Patrones recurrentes esta semana

### Patrón 1 — Búsqueda lineal dentro de un bucle donde un diccionario daría O(1) (Backend)

**Qué es.**
Se usa una comprensión de lista del tipo `[r for r in regs if r.atributo == valor]` *dentro* de un bucle externo, de modo que por cada iteración del bucle se recorre la lista completa. El costo total es O(días × |lista|) en lugar de O(|lista|) para construir el índice + O(1) por consulta.

**Dónde apareció.**
- `BACKEND/app/services/planilla_asistencia_service.py`, ~líneas 163–175 — `[r for r in regs if r.fecha_hora.date() == dia]` dentro del loop por días. Reportado el **2026-07-06** (Hallazgo H1) y de nuevo el **2026-07-07** (Hallazgo 2) porque el problema seguía presente tras el primer reporte.
- `BACKEND/app/routers/operaciones.py` — `_notificar_servicio_pendiente_a_jefes` cargaba todos los usuarios activos de la empresa desde la BD y aplicaba `"jefe" in _norm_rol(...)` en Python en lugar de filtrar en la query SQL. Reportado el **2026-07-07** (Hallazgo 3).

**Por qué importa.**
En el primer caso, con 30 días y 120 registros/empleado son 3.600 comparaciones por empleado; con 100 empleados, 360.000 comparaciones por cálculo de planilla. En el segundo, cada notificación cargaba filas de empleados que el backend descartaba inmediatamente, consumiendo memoria y tiempo de red/BD sin necesidad.

**Regla de oro.**
Antes de escribir `[x for x in lista if x.campo == valor]` dentro de un bucle, pregúntate: ¿puedo construir un `dict` o `set` de `lista` *una sola vez* antes del bucle y luego hacer `.get(valor, [])` en O(1)? En el 90 % de los casos la respuesta es sí.

```python
# Antes (O(n × m))
for dia in dias:
    regs_dia = [r for r in regs if r.fecha_hora.date() == dia]

# Después (O(n + m))
regs_por_dia: dict[date, list] = {}
for r in regs:
    regs_por_dia.setdefault(r.fecha_hora.date(), []).append(r)

for dia in dias:
    regs_dia = regs_por_dia.get(dia, [])
```

Para los filtros sobre BD, la misma lógica aplica: empujar el predicado a SQL (`.filter(Rol.nombre.ilike('%jefe%'))`) siempre que sea posible en lugar de traer todas las filas y filtrar en Python.

**Concepto a estudiar:** *lookup tables / hash maps*, complejidad amortizada, diferencia entre O(n²) y O(n) en la práctica.

---

### Patrón 2 — Recálculo costoso o `setState` demasiado amplio en Flutter dentro de builders y listeners (Flutter)

**Qué es.**
Se ejecuta trabajo costoso (agrupaciones, filtros, construcción de mapas) o se llama a `setState(() {})` en lugares que Flutter invoca con alta frecuencia: dentro de `itemBuilder` de un `ListView`, dentro de un listener de `TabController` en cada tick de animación, o una vez por ítem dentro de un bucle `async`. El efecto es que el árbol de widgets se reconstruye más veces de lo necesario, degradando la fluidez y el rendimiento.

**Dónde apareció.**
- `e_zyro_app/lib/screens/pantalla_equipos_intervenidos.dart` — `porZona` se construía *dentro de* `itemBuilder`, recalculándose en cada frame de scroll. Reportado el **2026-07-07** (Hallazgo 1).
- `e_zyro_app/lib/screens/pantalla_plantillas_procedimiento.dart` — `addListener(() => setState(() {}))` disparaba un rebuild completo en *cada tick* de la animación de transición entre tabs, no solo al terminar. Reportado el **2026-07-07** (Hallazgo 2).
- `e_zyro_app/lib/screens/pantalla_camara_campo.dart`, línea 1065 — `setState(() => _resultado[i] = r)` dentro de un bucle `for`, un rebuild por foto subida en lugar de uno al terminar. Reportado el **2026-07-08** (Hallazgo 1).
- `e_zyro_app/lib/screens/finanzas/pantalla_planilla.dart` — listener de `TabController` con `setState(() {})` vacío que reconstruía el árbol completo de la pantalla (con cuatro tabs y lógica pesada) solo para actualizar el `FloatingActionButton`. Reportado el **2026-07-10** (Hallazgo 4).
- `e_zyro_app/lib/screens/pantalla_legajo_detalle.dart` y `pantalla_legajo_lista.dart` — getters `_documentosFiltrados` / `_filtrados` que iteran la lista completa en cada llamada a `build()`. Reportado el **2026-07-10** (Hallazgo 3).

**Por qué importa.**
Flutter llama a `build()` e `itemBuilder` decenas de veces por segundo durante animaciones y scroll. Un `setState` que reconstruye el `Scaffold` completo cuando solo cambió un botón es trabajo de layout innecesario que puede causar jank (caídas por debajo de 60 fps). Con listas grandes, un getter que filtra en cada `build()` acumula tiempo de CPU en el hilo de UI.

**Reglas de oro.**

1. **Sacar el trabajo del builder.** Todo lo que no depende del índice o del estado de la animación (agrupaciones, filtros, cálculos derivados) debe calcularse *fuera* del `itemBuilder` / `build()` y almacenarse en una variable de estado. Recalcular solo cuando cambian los datos de origen, no en cada frame.

2. **Guardar el `setState` al mínimo.** En listeners de `TabController`, comprobar `if (_tabCtrl.indexIsChanging) return;` para disparar el rebuild solo cuando la animación termina, no en cada frame intermedio. En bucles async, mutar el estado directamente y llamar a `setState(() {})` una sola vez al salir del bucle.

3. **Usar `AnimatedBuilder` o `ValueListenableBuilder` para widgets que solo dependen de una animación/notifier.** En lugar de `setState` global, envuelve solo el widget que cambia:
   ```dart
   // Mal: reconstruye todo el Scaffold
   _tabs.addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });

   // Mejor: solo reconstruye el FAB
   floatingActionButton: AnimatedBuilder(
     animation: _tabs,
     builder: (_, __) => _buildFab(),
   ),
   ```

4. **Cachear filtros derivados.** Si tienes un getter que filtra una lista, conviértelo en una variable calculada en `initState`, en el callback de búsqueda, o en el método de carga de datos — no en el getter mismo:
   ```dart
   // En onChanged / _cargar:
   _filtrados = _todos.where((e) => e.nombre.contains(_busqueda)).toList();
   setState(() {});
   // En build():
   ListView(children: _filtrados.map(...).toList())
   ```

**Concepto a estudiar:** *widget rebuild scoping en Flutter*, `AnimatedBuilder`, `ValueListenableBuilder`, memoización de valores derivados, separación entre estado de datos y estado de UI.
