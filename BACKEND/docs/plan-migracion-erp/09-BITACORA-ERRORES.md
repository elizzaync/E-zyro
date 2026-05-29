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
_(vacío — se llena durante la ejecución)_
