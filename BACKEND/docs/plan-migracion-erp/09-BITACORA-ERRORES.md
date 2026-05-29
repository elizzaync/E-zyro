# 09 · Bitácora de errores

> Cada error detectado al **arrancar el backend** (migraciones del `lifespan`), al correr la app
> (`flutter analyze`/runtime) o en revisión, se registra aquí ANTES de corregirlo. Esto crea el
> historial que pediste: "commitear para ver si el backend detecta un error y documentarlo".

## Plantilla (copiar por cada error)
```
### ERR-<n> · <fase/punto> · <fecha>
- **Síntoma:** (mensaje/exception exacto, primeras líneas del traceback)
- **Dónde:** archivo:línea / fase de arranque (_pre_create | create_all | _run_migrations | runtime)
- **Causa raíz:** (diagnóstico)
- **Solución:** (qué se cambió)
- **Verificación:** (arranque limpio / test que lo confirma)
- **Commit del fix:** <hash o rama>
- **Lección / regla para el plan:** (si aplica, se sube a 01-CONVENCIONES.md)
```

## Antecedente (caso de referencia ya resuelto)
```
### ERR-0 · pre-plan · 2026-05-29
- Síntoma: psycopg2.errors.CheckViolation: new row for relation "requerimiento" violates check constraint "chk_req_estado" (estado='listo'); el lifespan abortaba y el contenedor no arrancaba.
- Dónde: app/main.py:_run_migrations (UPDATE a 'listo') vs CHECK chk_req_estado desactualizado.
- Causa raíz: el CHECK no incluía los estados 'comprando' y 'listo' del modelo híbrido.
- Solución: ampliar el CHECK (DROP IF EXISTS + ADD con set completo) ANTES del UPDATE; sincronizar bd.txt y migrations/sync_schema_2026_05_20.sql.
- Verificación: arranque sin excepción.
- Lección: **todo CHECK de estado debe listar TODOS los valores que el código pueda escribir.** (Incorporado a 01-CONVENCIONES.md y a los checklists de cada subplan.)
```

## Registro

### ERR-1 · Fase 0 (verificación e2e) · 2026-05-29
- **Síntoma:** `sqlalchemy.exc.NoReferencedTableError: Foreign key associated with column 'ubicacion.empresa_id' could not find table 'empresa'`.
- **Dónde:** script e2e aislado (`e2e_fase0.py`), al construir el TestClient. **No** ocurre en el backend real.
- **Causa raíz:** el arnés importaba solo `ubicacion/zona/area`, así que `Base.metadata` no conocía la tabla `empresa` para resolver la FK. En `main.py` se importan TODOS los modelos, por eso allí no pasa.
- **Solución:** el arnés ahora importa todos los módulos de `app.models` (igual que main.py) antes de montar el router.
- **Verificación:** e2e Fase 0 completo en verde (CRUD + joins + validaciones + limpieza).
- **Lección:** cualquier prueba aislada que toque el ORM debe cargar el set completo de modelos para resolver FKs. (Aplicado también al e2e de Fase 1.)

### Gate de verificación usado (nota de método)
Como el árbol de dependencias del backend incluye libs pesadas (firebase-admin, opencv) que solo importan en Docker, el "arranque limpio" se validó de forma equivalente y fiel al riesgo real:
1. **Aplicar el espejo SQL a Railway dos veces** (idempotencia) — cubre la clase de error `chk_req_estado`/CheckViolation.
2. **`py_compile`** de todo archivo nuevo + `main.py` — sintaxis.
3. **Importación dirigida** de los módulos nuevos (modelos/schemas/router) — cableado.
4. **e2e con TestClient** montando solo el router nuevo contra Railway, con datos marcados y limpieza garantizada.
