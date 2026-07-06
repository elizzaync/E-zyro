# Patrones recurrentes esta semana (30 jun – 3 jul 2026)

Basado en los hallazgos de `docs/2026-06-29.md`, `docs/2026-06-30.md`, `docs/2026-07-01.md`, `docs/2026-07-02.md` y `docs/2026-07-03.md`.

---

## 1. Consultas N+1 a la base de datos

**Concepto:** *N+1 query problem*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-06-29 | `vacaciones.py:112-125`, `389-398` | `_saldos_todos()` llama a `_saldo()` por cada empleado; dentro ejecuta 3 queries independientes (`_nombre`, `_ajuste`, `_gozado_detalle`) → ~3N+1 round-trips |
| 2026-06-29 | `rrhh_asistencia.py:276-288`, `941-954`, `1135-1144` | `_parse_dias_lab()` se llama una vez por empleado por día dentro de un bucle anidado (hasta 3 000 invocaciones para 100 empleados × 30 días) |
| 2026-07-02 | `logistica.py` (`items_pendientes_retorno_servicio`) | `db.query(Material).filter(Material.id == d.material_id).first()` dentro de un bucle → 1 query por ítem |
| 2026-07-03 | `epp.py:445`, `502` | `db.query(EppEntregaDetalle).filter(...).all()` dentro de un bucle de entregas → 1 query por entrega |

### Por qué importa

Cada round-trip a PostgreSQL tiene latencia fija (red + parser + planner). Con 20 ítems o 100 empleados la diferencia es de ms vs. segundos. El problema escala linealmente: una empresa grande que hoy tarda 2 s tardará 20 s cuando tenga 10× más datos.

### Regla a interiorizar

**Nunca emitir queries dentro de bucles.** El patrón correcto es:
1. Recolectar todos los IDs antes del bucle.
2. Hacer **una sola** consulta con `.filter(Modelo.id.in_(lista_ids))`.
3. Convertir el resultado en un diccionario `{id: objeto}`.
4. Acceder al diccionario dentro del bucle (`mapa.get(item.id)`).

Para cálculos repetidos sobre el mismo objeto (ej. `_parse_dias_lab` del mismo turno), **memoizar** el resultado con un `dict` calculado fuera del bucle, indexado por `turno.id`.

---

## 2. Filtrado y paginación en memoria en lugar de en SQL

**Concepto:** *push predicates into the database / database-side filtering*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-06-30 | `operaciones.py` (`get_proyectos`, `get_servicios_proyecto`) | Parámetros `q` y `estado` se aplican en Python sobre `.all()`, cargando todos los proyectos/servicios de la BD primero |
| 2026-07-03 | `logistica.py:1626` (`historial_requerimientos`) | `total = base.count()` se calcula **antes** del filtro `q` en Python → el paginador devuelve un total incorrecto cuando hay búsqueda activa |
| 2026-07-03 | `logistica.py:4087-4155` (`historico-legacy`) | Todos los registros se cargan sin `LIMIT` en SQL, luego se filtra y pagina con slices de Python |

### Por qué importa

Cargar toda la tabla en memoria para filtrar en Python:
- Desperdicia memoria proporcional al tamaño total de la tabla, no al resultado.
- El bug de `total` incorrecto provoca que el frontend muestre páginas fantasma o cuente mal los resultados.
- Con 1 750 registros históricos es manejable hoy, pero cualquier reingesta romperá el endpoint.

### Regla a interiorizar

**El filtro va antes del `.all()`.** Toda cláusula `WHERE`, `ILIKE`, `IN` o `ORDER BY` debe expresarse como `.filter()` / `.order_by()` de SQLAlchemy antes de materializar la query. El `COUNT` para paginación debe calcularse sobre la query **ya filtrada**, no sobre la base sin filtros.

```python
# Mal
rows = base_q.all()
if q:
    rows = [r for r in rows if q in r.nombre]

# Bien
if q:
    base_q = base_q.filter(Modelo.nombre.ilike(f"%{q}%"))
total = base_q.count()   # sobre la query filtrada
rows = base_q.offset(skip).limit(limit).all()
```

---

## 3. Código muerto y cómputo redundante

**Concepto:** *dead code / redundant computation*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-06-29 | `vacaciones.py:1078-1104` | La variable `ficha` (una `Table` completa con `Paragraph` objetos) se construye, se descarta y se reconstruye en la siguiente línea dentro de un bucle por empleado |
| 2026-06-30 | `operaciones.py:668`, `813` | `db.query(func.count(Procedimiento.id)).scalar()` se ejecuta antes de cargar `procs`; más adelante `sin_proc_estandar` se recalcula con `not procs` (en memoria) — el COUNT inicial nunca se usa |
| 2026-07-01 | `apertura_service.py:162` | `(total_db if diferencia <= CERO else total_db)` — ambas ramas del ternario retornan el mismo valor; la condición no tiene efecto |
| 2026-07-03 | `catalogo_navegacion.dart:300-305` (Flutter) | `pantallasParaLlm()` llama a `catalogoNavegacion()` internamente, reconstruyendo el catálogo de >40 pantallas en cada mensaje enviado, cuando `_catalogo` ya existe como campo del widget |

### Por qué importa

El código muerto oculta la intención real, hace el código más difícil de mantener y, cuando está dentro de bucles (como `ficha` en el loop de empleados o el catálogo del chatbot en cada mensaje), introduce trabajo innecesario proporcional al número de iteraciones.

### Regla a interiorizar

Antes de añadir un cálculo, preguntarse: **¿ya tenemos este resultado disponible más adelante en la función?** Si sí, no calcularlo dos veces — pasarlo como parámetro o guardarlo en una variable local compartida. Si el resultado de la primera construcción se va a sobreescribir de inmediato, es señal de que el primer bloque no debería existir.

---

## 4. Gestión incorrecta del estado asíncrono en Flutter

**Concepto:** *async state management / race conditions with `mounted`*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-07-01 | `pantalla_finanzas.dart` (`_cargar`) | El primer `setState` se llama sin comprobar `mounted` antes del `await`. La guarda `if (!mounted) return` solo aparece después del `await`. Si el widget se destruye antes de que `_cargar` corra, se lanza `setState` sobre un widget desmontado |
| 2026-07-02 | `pantalla_detalle_servicio.dart` (`_verificarRetornoPendiente`) | La bandera de reentrada `_chequeandoRetorno = true` se asigna **después** del primer `await getRetornoService()`. Si la función es invocada dos veces antes de que el `await` devuelva, ambas invocaciones pasan el guard inicial y la función se ejecuta en paralelo |

### Por qué importa

- Llamar a `setState` sobre un widget desmontado lanza una excepción en debug y puede causar comportamiento indefinido en release.
- Asignar un flag de reentrada después de un `await` anula su propósito: la sección que debía proteger ya fue ejecutada dos veces para cuando el flag se activa.

### Regla a interiorizar

**Toda función `async` en un `State` sigue este esqueleto:**

```dart
Future<void> _cargar() async {
  if (!mounted) return;        // 1. guarda antes de cualquier setState
  setState(() { _cargando = true; });

  // Si hay un flag de reentrada, activarlo ANTES del primer await:
  if (_corriendo) return;
  _corriendo = true;

  try {
    final resultado = await servicio.obtener();
    if (!mounted) return;      // 2. guarda después de cada await
    setState(() { _data = resultado; _corriendo = false; });
  } catch (e) {
    _corriendo = false;
    if (!mounted) return;
    setState(() { _error = e.toString(); });
  }
}
```

La regla mnemotécnica: **`!mounted` antes del primer `setState`, y después de cada `await`**. Los flags de reentrada van **antes** de cualquier `await`, no después.
