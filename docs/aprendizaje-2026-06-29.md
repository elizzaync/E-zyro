# Aprendizaje semanal — 2026-06-29

> Período analizado: 2026-06-23 al 2026-06-27  
> Basado en los hallazgos de los archivos `docs/2026-06-23.md` al `docs/2026-06-27.md`.

---

## Patrones recurrentes esta semana

### Patrón 1 — Queries N+1 y consultas duplicadas a la base de datos dentro de bucles

**Concepto:** _N+1 query problem_, _bulk loading_, _precomputing lookup maps_.

**Dónde apareció:**

| Fecha | Archivo y línea | Descripción |
|-------|----------------|-------------|
| 2026-06-23 | `BACKEND/app/routers/evaluaciones.py` — `_eval_out` | Por cada evaluación con `plantilla_id` se hace un `db.query(PlantillaEvaluacion)` individual dentro del loop de serialización. Con 30 evaluaciones → 30 queries extra. |
| 2026-06-23 | `BACKEND/app/routers/evaluaciones.py` — `asignar_plantilla`, `crear_lote` | Por cada `emp_id` en el body: `db.query(Empleado).filter(Empleado.id == emp_id).first()`. Con 20 empleados → 20 queries. |
| 2026-06-25 | `BACKEND/app/routers/logistica.py` — `_material_out` (~línea 278) | `db.query(Marca).filter(Marca.id == mat.marca_id).first()` dentro del helper de serialización, inconsistente con la solución bulk que ya se implementó en `listar_materiales`. |
| 2026-06-26 | `BACKEND/app/routers/rrhh_asistencia.py:748` | `[r for r in regs if r.fecha_hora.date() == dia]` dentro de un doble bucle `empleado × día`. Para 100 empleados × 31 días → ~124 000 comparaciones. El mismo patrón aparece también en las líneas 272 y 946 del mismo archivo. |
| 2026-06-27 | `BACKEND/app/routers/rrhh_asistencia.py` — `_xlsx_mensual_gerencial` (~líneas 1502 y 1515) | Se re-consultan `Empleado+Usuario` y `RegistroAsistencia` del mes completo, aunque `_build_cronograma` (llamada justo antes) ya hizo exactamente esas mismas queries. |

**Por qué importa:** Cada query a la BD tiene latencia de red + I/O. Diez queries secuenciales pueden tardar 10× más que una sola query con `IN(...)`. En producción, con usuarios reales y datos acumulados, estos endpoints se vuelven notablemente lentos sin ninguna razón inherente a la complejidad del problema.

**Regla de oro para internalizar:**  
_Antes de cualquier bucle que toque la base de datos, preguntarte: ¿puedo traer todo lo que necesito en una sola query y guardarlo en un dict para lookup O(1)?_

```python
# Patrón correcto — bulk load + dict map
plantillas = {str(p.id): p for p in db.query(PlantillaEvaluacion)
              .filter(PlantillaEvaluacion.id.in_(ids_con_plantilla)).all()}

# Dentro del loop:
nombre_plantilla = plantillas.get(str(ev.plantilla_id), {}).nombre
```

Para el caso del filtro por fecha dentro de bucle, usar `defaultdict(list)` como índice:
```python
regs_por_dia = {}
for r in regs:
    regs_por_dia.setdefault(r.fecha_hora.date(), []).append(r)
# Lookup O(1) en el bucle:
regs_dia = regs_por_dia.get(dia, [])
```

---

### Patrón 2 — Imports de módulos dentro de funciones en lugar del encabezado del módulo

**Concepto:** _module-level imports_, _Python import system_.

**Dónde apareció:**

| Fecha | Archivo y ubicación | Qué se importa dentro de la función |
|-------|--------------------|------------------------------------|
| 2026-06-23 | `BACKEND/app/routers/evaluaciones.py` — `editar_plantilla` y `eliminar_plantilla` | `from datetime import datetime` (aparece dos veces, en dos funciones distintas del mismo archivo) |
| 2026-06-24 | `BACKEND/app/routers/usuarios.py` — bloque `if body.crear_ficha:` | `from datetime import date` |
| 2026-06-27 | `BACKEND/app/routers/rrhh_asistencia.py` — líneas 644, 830 y 2089 | `from app.models.turno import Turno, TurnoEmpleado` (con variantes de ruta y alias) repetido dentro de tres funciones distintas |

**Por qué importa:** Python cachea los módulos en `sys.modules`, por lo que el costo de rendimiento no es grave. El problema real es de legibilidad y mantenimiento: un lector que lee la función no espera encontrar imports ahí, y si se quiere refactorizar o mover el módulo, los imports locales son invisibles desde el encabezado. Es también una señal de que el código fue escrito de forma incremental sin revisar el encabezado del archivo.

**Regla de oro:** Los imports van siempre al inicio del módulo. La única excepción válida es evitar una dependencia circular — y si eso ocurre, es señal de que el diseño de módulos necesita revisión. Cuando añadas funcionalidad a un archivo existente, revisa primero los imports ya declarados y amplíalos si hace falta (ej. `from datetime import date` → `from datetime import date, datetime`).

---

### Patrón 3 — Iteraciones redundantes sobre listas dentro de `build()` en Flutter

**Concepto:** _widget rebuild scoping_, _memoización de cómputos derivados en el estado Flutter_.

**Dónde apareció:**

| Fecha | Archivo y línea | Descripción |
|-------|----------------|-------------|
| 2026-06-24 | `e_zyro_app/lib/screens/pantalla_mi_espacio.dart` — `_MisEvaluacionesTabState.build()` | `_items.where((e) => e.esAsignada).toList()` y `.where((e) => !e.esAsignada).toList()` calculados en cada `build()`, incluyendo scrolls y rebuilds del padre. |
| 2026-06-25 | `e_zyro_app/lib/screens/pantalla_evaluaciones.dart` (~líneas 219-222) | `_empleados.where((e) => e.id == pre.id)` se evalúa dos veces seguidas con el mismo predicado para decidir `_sel` y si insertar en la lista. |
| 2026-06-25 | `e_zyro_app/lib/screens/pantalla_privilegios.dart` (~líneas 762-763) — `_ModuloCard.build()` | `permisos.where((p) => p.directo).length` y `permisos.where((p) => p.viaRol && !p.directo).length` en cada rebuild de la tarjeta (triggered por scroll, setState padre, etc.). |

**Por qué importa:** En Flutter, `build()` se puede llamar decenas de veces por segundo. Una iteración O(n) dentro de `build()` es O(n × frecuencia_de_rebuild). Para listas pequeñas es irrelevante hoy; pero el patrón escala mal y cuando la lista crezca el problema ya estará en producción.

**Regla de oro:**  
_Cualquier valor derivado de la lista de datos (`_items`, `permisos`, etc.) que no dependa de parámetros del `build()` mismo debe calcularse en `setState()` al cargar los datos, no en `build()`._

```dart
// MAL — dentro de build():
final asignadas = _items.where((e) => e.esAsignada).toList();

// BIEN — dentro de setState(), guardado en el estado:
setState(() {
  _items = data;
  _asignadas = data.where((e) => e.esAsignada).toList();
  _historial = data.where((e) => !e.esAsignada).toList();
});
```

Para el caso del doble `.where()` con el mismo predicado en la misma expresión: guardar el resultado intermedio en una variable local antes de usarlo dos veces.

---

### Patrón 4 — Re-inicialización repetida de objetos costosos (SharedPreferences / ApiClient)

**Concepto:** _singleton pattern_, _service locator_, _initState lifecycle in Flutter_.

**Dónde apareció:**

| Fecha | Archivo | Descripción |
|-------|---------|-------------|
| 2026-06-24 | `e_zyro_app/lib/screens/pantalla_evaluaciones.dart` y `pantalla_personal_hub.dart` | `getEvaluacionService()` (que llama `SharedPreferences.getInstance()` y construye `EvaluacionService(ApiClient(prefs))`) se invoca en cada pull-to-refresh, cada creación de evaluación y cada apertura del diálogo de asignación. |
| 2026-06-25 | `e_zyro_app/lib/screens/pantalla_camara_campo.dart` — `_restaurarSeleccion` (~línea 102) y `_guardarSeleccion` (~línea 124) | `SharedPreferences.getInstance()` llamado dos veces en el mismo flujo de inicialización secuencial en lugar de obtenerse una vez en `_inicializar` y pasarse a los métodos que lo necesitan. |

**Por qué importa:** `SharedPreferences.getInstance()` es una llamada de plataforma asíncrona (channel call). Aunque la implementación cachea la instancia internamente, invocarlo en cada operación de UI añade latencia innecesaria, aumenta el riesgo de condiciones de carrera y dificulta el razonamiento sobre el ciclo de vida del widget. Construir un `ApiClient` nuevo en cada carga también descarta cualquier estado de conexión reutilizable.

**Regla de oro:**  
_Los servicios y objetos de infraestructura (clientes HTTP, preferences, controladores) se inicializan **una sola vez** en `initState()` y se guardan como campos del `State`. Las acciones de UI los reutilizan._

```dart
EvaluacionService? _svc;

@override
void initState() {
  super.initState();
  getEvaluacionService().then((s) {
    if (!mounted) return;
    setState(() { _svc = s; });
    _cargar();
  });
}

Future<void> _cargar() async {
  if (_svc == null) return;
  // usa _svc directamente sin volver a llamar getEvaluacionService()
}
```

---

## Nota sobre los hallazgos descartados

Los siguientes hallazgos aparecieron en un único día y **no** constituyen un patrón recurrente esta semana:

- Bug de validación de estado en `cambiar_estado` (2026-06-23)
- `_activo_cache` sin límite de tamaño (2026-06-24)
- Cache no actualizado al reactivar cuenta (2026-06-24)
- `getattr` innecesario que enmascara errores de esquema (2026-06-24)
- `DateTime.now()` invocado dos veces en el mismo statement (2026-06-24)
- Almacén no determinístico por falta de `ORDER BY` (2026-06-25)
- Bugs corregidos el mismo día (ValueError por overflow de minutos, lookup de turno con tipo erróneo, UUID/username en columna wrong-typed) (2026-06-27)
- Colisión silenciosa de nombres en `emp_id_map` (2026-06-27)
- Inconsistencia de cálculo de tardanza entre `dashboard.py` y `rrhh_asistencia.py` (2026-06-26 y 2026-06-27) — aunque aparece dos días seguidos, ambas menciones se refieren al mismo archivo y función no corregida, no a un patrón de diseño que se repite en distintos lugares.
