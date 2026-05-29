# 07 · Orquestación de agentes

> Cómo se ejecuta cada **punto** del plan con un equipo de agentes especializados, con revisión de
> errores, commits y documentación. Yo (Claude) actúo como **orquestador/PM**: coordino, decido y
> mantengo el estado; delego trabajo acotado en subagentes cuando conviene aislarlo.

## Roles (subagentes)
| Rol | Tipo de agente | Responsabilidad | Herramientas |
|-----|----------------|-----------------|--------------|
| **Analista / Arquitecto** | `Plan` o `Explore` | Validar el subplan contra el código real; fijar el contrato de datos/API ANTES de codificar; detectar choques (tipos FK, CHECKs, RBAC, multiempresa). | Solo lectura/búsqueda. |
| **Backend Senior** | `general-purpose` (worktree) | Implementar modelo + migración + schema + router + Cloudinary + PDF. | Lectura/escritura, Bash. |
| **Mobile Senior** | `general-purpose` (worktree) | Implementar model Dart + service + repo offline + pantalla + navegación. | Lectura/escritura, Bash. |
| **Revisor / QA** | `/code-review` (skill) | Revisar el diff por correctness, RBAC, multiempresa, idempotencia de migración, fugas Cloudinary. | Review. |
| **Documentador** | (lo hace el orquestador) | Actualizar `08-PROGRESO.md` y `09-BITACORA-ERRORES.md`; registrar arranque/commit. | Escritura. |

> **Aislamiento:** Backend y Mobile trabajan en **git worktrees** separados (`isolation: "worktree"`) para no pisarse y poder descartar trabajo sin afectar el árbol principal. Los subagentes arrancan "en frío": se les pasa el subplan + convenciones como contexto.

## Pipeline por punto (gate de calidad)
```
1) Analista          → contrato validado (o lista de choques a resolver)
2) Backend Senior    → implementa en worktree
3) ARRANQUE LOCAL    → uvicorn levanta; corren _pre_create + create_all + _run_migrations
        ├─ falla     → Documentador registra traceback en 09; Backend corrige; repetir 3
        └─ OK        → seguir
4) Revisor (/code-review) sobre el diff
        ├─ hallazgos altos → Backend corrige; volver a 3
        └─ limpio          → seguir
5) Commit en rama del módulo (mensaje convencional)
6) Documentador        → 08-PROGRESO actualizado
7) Mobile Senior       → implementa contra la API ya estable; análisis estático (flutter analyze)
8) Revisor app + commit app
9) (Push al remoto SOLO con confirmación del usuario)
```

## "El commit como detector de errores"
- El **arranque del backend es el test de humo**: si una migración es inválida (p. ej. un CHECK que no cubre un estado, como pasó con `chk_req_estado`), el `lifespan` lanza la excepción y NO se commitea.
- Procedimiento exacto de verificación de arranque (local):
  ```
  # en el worktree del backend
  uvicorn app.main:app --port 8099   # observar logs del lifespan
  # éxito = "Application startup complete" + /docs responde
  ```
  Si hay base de datos local/contenedor, se usa esa; si no, se valida contra una DB de staging desechable. El criterio es: **migraciones sin excepción**.
- Solo tras arranque limpio → `git add` + `git commit`. El hash del commit y el resultado se anotan en `08-PROGRESO.md`.

## Plantilla de prompt para el Backend Senior
```
Contexto: Implementa el PUNTO <id> del subplan docs/plan-migracion-erp/<archivo>.md.
Lee también 01-CONVENCIONES.md y 02-CLOUDINARY-Y-GALERIA.md.
Reglas no negociables:
- empresa_id en toda tabla; filtrar por empresa del token.
- Migración idempotente; CHECK lista TODOS los estados; tablas con FK uuid van en _pre_create_migrations.
- Registrar el modelo en el bloque de imports de main.py y el router con include_router.
- Subidas a Cloudinary SOLO vía services/cloudinary_paths + indexar en recurso_cloudinary.
Entregable: diff + confirmación de que el backend arranca sin excepción en el lifespan.
NO hagas push. NO toques otros módulos.
```

## Plantilla de prompt para el Mobile Senior
```
Contexto: Implementa la parte móvil del PUNTO <id> (subplan <archivo>.md), contra la API ya estable.
Lee 01-CONVENCIONES.md (sección B).
Reglas:
- model fromJson/toJson cubre el schema Out del backend.
- service vía core/api_client.dart → ApiResult.
- Navegación: engancha en el apartado indicado por el subplan (tab o _MenuItem en pantalla_mas).
- Estados loading/empty/error en la UI; reusar widgets existentes y tema (modo oscuro).
Entregable: diff + `flutter analyze` sin errores. NO push.
```

## Reglas de delegación (cuándo SÍ uso subagentes)
- Se delega trabajo **acotado y paralelizable** (un módulo backend completo, un módulo app completo).
- El **Revisor** siempre es un paso aparte del implementador (cuatro ojos).
- La **decisión de arquitectura, el orden y los commits** los mantengo yo (orquestador), no se delegan.
- Si dos puntos no comparten archivos, sus subagentes pueden correr en **paralelo** (worktrees distintos).

## Cadencia de sincronización con el usuario
- Al cerrar cada **fase** (no cada punto): resumen de lo hecho, errores documentados y siguiente fase.
- Cualquier decisión que cambie el contrato de datos o el alcance se consulta antes de codificar.
- Push al remoto compartido: siempre con confirmación explícita.
