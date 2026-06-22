# Aprendizaje semanal — 2026-06-22

> Basado en los hallazgos de `docs/2026-06-15.md`, `docs/2026-06-16.md`, `docs/2026-06-17.md` y `docs/2026-06-18.md`.

---

## Patrones recurrentes esta semana

### 1. Problema N+1 en el backend (SQLAlchemy)

**Concepto:** *N+1 query problem*

**Qué es el patrón:** Dentro de un bucle que itera N filas ya cargadas, se lanza una query a la base de datos por cada elemento. El resultado son N+1 consultas en lugar de 1 o 2.

**Dónde apareció esta semana:**

| Fecha | Archivo | Función |
|-------|---------|---------|
| 2026-06-15 | `BACKEND/app/routers/epp.py` (~línea 264 y ~411) | `anular_entrega`, `crear_ingreso` — una query por ítem de entrega |
| 2026-06-15 | `BACKEND/app/routers/planilla.py` (~línea 248) | `listar_boletas` — una query por boleta para sus detalles |
| 2026-06-15 | `BACKEND/app/services/planilla_service.py` (~línea 82) | `calcular_planilla` — una query por planilla anulada |
| 2026-06-16 | `BACKEND/app/services/planilla_asistencia_service.py` (líneas 52-79) | `resumen_asistencia_periodo` — una query por cada día laborable (~23 queries/mes) |
| 2026-06-16 | `BACKEND/app/services/planilla_service.py` (~línea 260) | `_recompute_planilla` — carga todos los objetos `BoletaPago` para sumar con Python |
| 2026-06-17 | `BACKEND/app/routers/drive.py` | `_carpeta_out` — 2 `COUNT` queries por carpeta al listar |
| 2026-06-17 | `BACKEND/app/routers/usuarios.py` | `_SELECT_USUARIO` — 2 subqueries correlacionadas por usuario |
| 2026-06-18 | `BACKEND/app/routers/soporte.py` (~línea 755) | `reporte_dispositivos` — una query a `Usuario` por grupo |
| 2026-06-18 | `BACKEND/app/routers/soporte.py` (~línea 89) | `listar_sesiones` / `sesiones_activas` — una query `_nombre_usuario` por sesión |
| 2026-06-18 | `BACKEND/app/routers/operaciones.py` (~línea 4288) | `get_inspeccion_activa` — queries extra por inspección con padre |

**Por qué importa:** Cada round-trip a la base de datos tiene latencia de red + overhead del ORM. Con 50 empleados o 100 carpetas, lo que debería tardar 5 ms puede tardar 500 ms. El problema no se ve en desarrollo con datos pequeños pero aparece en producción.

**Regla de oro:** Si en un loop ves `db.query(...).filter(... == elemento_del_loop...)`, ese loop es casi siempre un N+1. La solución estándar:

```python
# Mal: una query por elemento
for item in items:
    obj = db.query(Modelo).filter(Modelo.id == item.id).first()

# Bien: una sola query con IN
ids = [item.id for item in items]
mapa = {str(o.id): o for o in db.query(Modelo).filter(Modelo.id.in_(ids)).all()}
for item in items:
    obj = mapa.get(str(item.id))
```

Para agregaciones (SUM, COUNT), reemplazar el loop Python por `func.sum`/`func.count` con `GROUP BY` o en una sola fila. Para subqueries correlacionadas, usar `joinedload` de SQLAlchemy o una CTE.

---

### 2. Llamadas a la API secuenciales en Flutter que deberían ser paralelas

**Concepto:** *Concurrent async requests / `Future.wait` pattern*

**Qué es el patrón:** Dos o más llamadas a la API que son completamente independientes entre sí se ejecutan con `await` en serie, por lo que cada una espera a que termine la anterior. El tiempo de carga de la pantalla es la suma de todas las latencias, cuando podría ser el máximo de ellas.

**Dónde apareció esta semana:**

| Fecha | Archivo | Función | Llamadas en serie |
|-------|---------|---------|-------------------|
| 2026-06-15 | `e_zyro_app/lib/screens/pantalla_documentos_sst.dart` (~línea 46) | `_init` | `getClientes()` → `getDocumentos()` |
| 2026-06-17 | `e_zyro_app/lib/screens/pantalla_gestion_usuarios.dart` | `_cargar` | `listar()` → `roles()` |
| 2026-06-17 | `e_zyro_app/lib/screens/pantalla_prestamos_servicio.dart` | `_enviar` | un `await` por ítem del carrito dentro del loop |
| 2026-06-18 | `e_zyro_app/lib/screens/pantalla_mi_espacio.dart` (~línea 37) | `_cargar` | `getResumenSemanal()` → `misSolicitudes()` → `getHistorial()` |

**Por qué importa:** Si cada llamada tarda 300 ms y hay tres en serie, el usuario espera ~900 ms. Ejecutadas en paralelo, esperaría ~300 ms. Esto afecta directamente la experiencia de usuario en pantallas de carga inicial.

**Regla de oro:** Antes de escribir `await a(); await b();`, preguntarse: ¿b necesita el resultado de a? Si la respuesta es no, usar `Future.wait`:

```dart
// Mal: tiempo total = latencia(a) + latencia(b)
final resultA = await svc.a();
final resultB = await svc.b();

// Bien: tiempo total = max(latencia(a), latencia(b))
final results = await Future.wait([svc.a(), svc.b()]);
final resultA = results[0] as TipoA;
final resultB = results[1] as TipoB;
```

Para loops con `await` secuencial (carrito de ítems, batch de operaciones), reemplazar por `Future.wait` sobre el iterable mapeado:

```dart
// Mal: N awaits en serie
for (final e in carrito.entries) {
  if (await svc.enviar(e.key, e.value)) ok++;
}

// Bien: N futures en paralelo
final resultados = await Future.wait(
  carrito.entries.map((e) => svc.enviar(e.key, e.value)),
);
final ok = resultados.where((r) => r).length;
```

---

### 3. Overfetching: filtrar o paginar en el cliente después de cargar todos los datos

**Concepto:** *Overfetching / push filters to the database*

**Qué es el patrón:** Se traen todos los registros del servidor (o de la BD) y luego se aplica un filtro o un `limit` en el cliente (Python o Dart). El resultado es correcto pero se transfieren y procesan datos innecesarios. Peor aún: cuando hay paginación SQL antes del filtro Python, la página devuelta puede quedar vacía aunque existan datos relevantes más allá del límite.

**Dónde apareció esta semana:**

| Fecha | Archivo | Qué se hace en cliente | Debería hacerse en |
|-------|---------|------------------------|---------------------|
| 2026-06-15 | `BACKEND/app/routers/documentos_sst.py` (~línea 133) | El filtro `estado` (vencida/vigente/por_vencer) se aplica en Python *después* del `LIMIT` SQL | SQL `WHERE` antes del `LIMIT` |
| 2026-06-16 | `BACKEND/app/routers/cuentas_por_cobrar.py` (~línea 121) | `if str(ps.id) in facturados` filtra en Python todos los servicios cargados | Subconsulta `NOT IN` / `.notin_()` en el `WHERE` de SQLAlchemy |
| 2026-06-18 | `e_zyro_app/lib/screens/pantalla_mi_espacio.dart` (~línea 37) | `.take(6)` en Dart después de descargar el historial completo | Pasar `limit=6` al endpoint |
| 2026-06-18 | `e_zyro_app/lib/screens/pantalla_asistencia.dart` (~línea 130) | Filtra solicitudes por `tipo == 'justificacion_tardanza'` en Dart | Pasar `?tipo=justificacion_tardanza` como query param al endpoint |

**Por qué importa:** Más allá del ancho de banda desperdiciado, el caso de `documentos_sst.py` es un bug de corrección: pedir `estado=vencida&limit=100` puede devolver 0 resultados aunque existan documentos vencidos, porque el `LIMIT` SQL ya recortó la lista antes de filtrar. El patrón rompe la semántica de la paginación.

**Regla de oro:** Los filtros siempre van al SQL (o al query param del endpoint), nunca al bucle Python/Dart posterior. Para paginación, el orden es: `WHERE` → `ORDER BY` → `OFFSET` → `LIMIT`. Para exclusiones, usar subconsultas (`.notin_()`) en lugar de un `set` Python. Para `limit` en la app, pasarlo como parámetro al backend en lugar de tomar solo los primeros N del JSON.
