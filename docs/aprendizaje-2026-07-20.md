# Patrones recurrentes esta semana

> Análisis de los Hallazgos en `docs/2026-07-13.md`, `docs/2026-07-15.md` y `docs/2026-07-17.md`.
> Fecha de generación: 2026-07-20.

---

## Patrón 1 — Problema N+1: múltiples queries por ítem dentro de un bucle

**Concepto:** *N+1 query problem*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-07-15 | `BACKEND/app/routers/programacion_campo.py` (~líneas 43–57 y 142–148) | `_to_out(pc, db)` emite 2 queries SQL por cada `ProgramacionCampo` devuelta (una JOIN triple para empleados y otra para `Proyecto.nombre_proyecto`). Con N filas → 1 + 2N queries totales. |
| 2026-07-17 | `BACKEND/app/routers/formatos.py` (~líneas 336–352 y 404) | `_out()` emite 2 queries extra por cada formato listado: una para la versión vigente y otra para el conteo de versiones. Con 13 formatos actuales → 26 queries adicionales por petición. |

### Por qué importa

Cada query tiene overhead de red y de parsing en PostgreSQL. El coste puede parecer insignificante con pocos registros, pero **escala linealmente con los datos** y colapsa en producción cuando el volumen crece. Es además difícil de detectar sin un profiler de queries porque el código "funciona" correctamente.

### Regla a internalizar

**Nunca abras una sesión de BD dentro de un bucle sobre resultados ya obtenidos.** Antes del bucle, trae todos los datos relacionados de una sola vez: construye un diccionario `{id: objeto}` y úsalo dentro del loop. En SQLAlchemy esto equivale a usar `joinedload` / `selectinload` en el ORM, o bien una sola query con `WHERE id IN (...)` seguida de un `{r.id: r for r in resultado}`.

```python
# Mal: query dentro del loop
for pc in filas:
    proyecto = db.query(Proyecto).filter_by(id=pc.proyecto_id).first()  # N queries

# Bien: batch lookup
ids = [pc.proyecto_id for pc in filas]
proyectos = {p.id: p for p in db.query(Proyecto).filter(Proyecto.id.in_(ids)).all()}
for pc in filas:
    proyecto = proyectos[pc.proyecto_id]  # O(1), 1 sola query total
```

---

## Patrón 2 — Filtrado en código de aplicación en lugar de en la base de datos

**Concepto:** *Predicate pushdown* / *Early filtering*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-07-15 | `BACKEND/app/routers/equipos_intervenidos.py` (~líneas 495–526) | El endpoint `antecedente_procedimiento` carga **todas** las filas de `HistorialInspeccion` del equipo y luego itera en Python buscando el `"orden"` solicitado. Para equipos con historial largo, trae a memoria cientos de filas JSON para quedarse con una. |
| 2026-07-15 | `e_zyro_app/lib/screens/pantalla_principal.dart` (~líneas 113–124) | `getMiProgramacion` descarga todas las asignaciones futuras del empleado desde hoy en adelante; el cliente filtra `where((p) => p.fecha == _hoyIso)`. Transfiere datos innecesarios en cada apertura de la pantalla principal. |

### Por qué importa

Mover el filtro al nivel de la aplicación (Python o Dart) en lugar de a la capa de datos:
- Aumenta el tráfico de red (en el caso Flutter, en cada carga de pantalla).
- Aumenta el uso de memoria en el servidor o en el dispositivo.
- Hace que el rendimiento empeore exactamente cuando más datos hay, justo cuando el usuario más lo nota.

Ambas instancias comparten la misma causa raíz: se escribe primero "dame todo" y luego se filtra, en lugar de pensar qué datos realmente necesita el flujo.

### Regla a internalizar

**El filtro más barato es el que nunca viaja por la red.** Pregúntate siempre: ¿puede la cláusula `WHERE` (o el parámetro de query) resolver esto antes de que los datos lleguen a tu código? En PostgreSQL puedes usar operadores JSONB (`@>`, `jsonb_path_exists`) para filtrar dentro de columnas JSON sin traerlas a memoria. En el API, expone parámetros como `?fecha=` para que el cliente pida solo lo que necesita.

---

## Patrón 3 — Fallos silenciosos: el código "parece funcionar" pero no hace nada (o lo hace mal)

**Concepto:** *Silent failure* / *Swallowed exceptions*

### Dónde apareció

| Fecha | Archivo | Descripción |
|---|---|---|
| 2026-07-13 | `e_zyro_app/lib/services/mantenimiento_service.dart` (~línea 64) | `catch (_) { return {}; }` — cualquier error de red, timeout o parsing queda completamente oculto. La cola no se drena y nadie sabe por qué. |
| 2026-07-17 | `BACKEND/migrations/migrate_formatos_erp.py` (~línea 1178–1236) | El script llama a `db.flush()` en cada iteración pero nunca hace `db.commit()`. Imprime mensajes de éxito pero al cerrar la sesión SQLAlchemy hace rollback implícito y **ningún dato queda guardado**. |
| 2026-07-17 | `BACKEND/app/routers/formatos.py` (~líneas 543–551) | `PUT /formatos/{id}` recibe `{"nota": "…"}` sin `archivo_base64`, responde `200 OK` sin persistir nada. La nota se descarta en silencio. |

### Por qué importa

Los fallos silenciosos son los más peligrosos porque:
1. El código da señales de éxito (200, mensajes de "OK", ausencia de excepción) mientras el sistema está roto.
2. El diagnóstico posterior puede tardar horas o días porque no hay rastro del error.
3. En producción pueden significar datos irrecuperables (migración que no guardó nada) o bugs que llegan al usuario final como comportamiento misterioso.

Las tres instancias son variantes del mismo error de diseño: **no se cierra el ciclo entre "intenté hacer X" y "X quedó hecho"**.

### Regla a internalizar

- **En Dart/Flutter:** nunca uses `catch (_)` ni `catch (e)` vacío en código de servicio. Mínimo, registra el error con `debugPrint` o tu sistema de logs antes de retornar. Si el estado se debe preservar para diagnóstico, guarda el mensaje de error en un campo accesible.
- **En Python/SQLAlchemy:** `flush()` escribe al buffer de la sesión, `commit()` persiste en disco. Son conceptos distintos. Cada script de migración debe terminar con un `commit()` explícito — nunca asumas que el cierre de sesión lo hará.
- **En endpoints REST:** si una petición no produce ningún cambio observable (por validación o por datos insuficientes), devuelve `400 Bad Request` con un mensaje claro, no `200 OK`. Un 200 sin efecto es una mentira hacia el cliente.
