# 00 · Master Plan

## 1. Principios rectores
- **Backend primero, app después.** Ninguna pantalla Flutter se construye sin su contrato de API estable.
- **Transversal antes que vertical.** Cloudinary/Galería y convenciones se hacen primero porque todos los módulos suben fotos/archivos.
- **Reutilizar lo existente.** e-zyro ya tiene: `empresa`, `empleado`, `equipo`, `material`, `marca`, `unidad_medida`, `proveedor`, `carpeta_documental`, `plano` (inerte), `evaluacion` (inerte), RBAC (`rol/permiso/...`), auditoría firmada, Cloudinary, generación de PDF (`services/pdf_service.py`), offline-first móvil. **No reinventar.**
- **Multiempresa siempre.** Toda tabla nueva lleva `empresa_id` (FK `empresa.id`, tipo `uuid` en DB / `String(36)` en modelo) y todo endpoint filtra por la empresa del token.
- **Idempotencia en migraciones.** Las migraciones corren en cada arranque (`lifespan`), así que todo `CREATE/ALTER` usa `IF [NOT] EXISTS` y todo `UPDATE` de datos es repetible.
- **El arranque es el primer test.** Si el backend levanta limpio (migraciones OK) y `/docs` responde, la base está sana. Cada fallo se documenta.

## 2. Orden de implementación (secuencia global)
El orden está dirigido por **dependencias** (lo transversal desbloquea), **riesgo** (lo aislado antes que lo acoplado al core) y **reutilización** (cada fase reaprovecha la infraestructura de la anterior).

| Fase | Entregable | Por qué este orden | Doc |
|------|-----------|--------------------|-----|
| **0** | Fundaciones: convenciones, scaffolding, seeds RBAC, catálogos faltantes (Zona, Ubicación, Área) expuestos | Sin catálogos base (zona/ubicación) ni convenciones, EPP e ITSE no tienen dónde anclar selects. | `01-CONVENCIONES.md` |
| **1** | **Cloudinary unificado + Galería Global** | EPP, Calibraciones e ITSE suben fotos/certificados. Definir la taxonomía y el índice de recursos ANTES evita migrar carpetas dos veces. | `02-CLOUDINARY-Y-GALERIA.md` |
| **2** | **EPP** | Módulo autocontenido (catálogo + stock + entrega/firma/PDF). Ideal para validar el pipeline completo (DB→API→app→PDF→galería) con bajo acoplamiento. | `03-EPP.md` |
| **3** | **Calibraciones + Equipos Averiados** | Extiende `equipo`/`orden_mantenimiento` ya existentes; bajo riesgo, reutiliza el patrón de EPP. | `06-CALIBRACIONES-Y-EQUIPOS-AVERIADOS.md` |
| **4** | **Garantías/Correctivos + Observaciones (Descargos)** | Acoplado al core de servicios (`operaciones`/`proyecto_servicio`); se hace tras dominar el patrón porque toca flujo crítico. | `04-GARANTIAS-CORRECTIVOS-OBSERVACIONES.md` |
| **5** | **Inspección ITSE** | El más grande: reúsa empresa/ubicación/zona (Fase 0), galería+PDF (Fase 1), patrón de evidencias (Fases 2-4). Va al final para apoyarse en todo lo anterior. | `05-INSPECCION-ITSE.md` |

> **Dónde ubicar cada módulo en la app** (resumen; detalle en cada subplan):
> - EPP → pestaña **Logística** (es almacén/stock) con su propia sección.
> - Calibraciones / Equipos Averiados → dentro de **Equipos/Mantenimientos**.
> - Garantías-Correctivos + Observaciones → dentro de **Operaciones** (servicios).
> - ITSE → **Operaciones** (entregable a cliente) con acceso también desde "Más".
> - Galería Global → pestaña **"Más"** + accesos contextuales desde servicio/equipo/EPP.

## 3. Estructura de cada fase (micro-ciclo)
Cada fase se descompone en **puntos** (pasos atómicos revisables). El ciclo de un punto:

```
Analista valida subplan ─► Backend implementa ─► Arranque local (migraciones) ─►
        ▲                                                   │
        │                                          ¿arranca limpio?
        │                                          │ no → documentar en 09 + corregir
   Revisor (code-review) ◄── Mobile implementa ◄───┘ sí
        │
        └─► Documentador actualiza 08-PROGRESO ─► commit en rama del módulo ─► (push con confirmación)
```

Detalle de roles, prompts y gates: `07-ORQUESTACION-AGENTES.md`.

## 4. Estrategia de ramas y commits
- **Rama por módulo**, partiendo de la rama base de cada repo:
  - Backend (`Backend`): `feat/backend-epp`, `feat/backend-calibraciones`, …
  - App (`e-zyro-app`): `feat/app-epp`, …
- **Commits atómicos por punto** con prefijo convencional: `feat(epp): modelo + migración`, `feat(epp): endpoints CRUD`, `fix(epp): …`.
- **El commit del backend es el "detector de errores"**: se commitea SOLO tras arranque limpio. Si el arranque falla, se registra el traceback en `09-BITACORA-ERRORES.md`, se corrige, y recién entonces se commitea.
- **Push** al remoto compartido (`elizzaync/E-zyro.git`) **solo con confirmación explícita** (es acción saliente). Los commits locales se acumulan y se sincronizan por lotes.
- Mensaje de commit cierra con la coautoría estándar del repo.

## 5. Definition of Done (por módulo)
Un módulo está "hecho" cuando:
- [ ] Modelos creados y registrados en el bloque de imports de `main.py`.
- [ ] Migración idempotente en `_run_migrations()` (o `_pre_create_migrations()` si lleva FK uuid) **y** espejo SQL en `migrations/`.
- [ ] Schemas Pydantic en `app/schemas/<modulo>.py`.
- [ ] Router en `app/routers/<modulo>.py`, registrado con `include_router`, con RBAC y filtro por `empresa_id`.
- [ ] Subidas a Cloudinary usando el helper centralizado (carpeta correcta) e indexadas en `recurso_cloudinary`.
- [ ] PDF/constancia (si aplica) vía `pdf_service`.
- [ ] **Backend arranca limpio** y endpoints visibles en `/docs`.
- [ ] App: model Dart + service + (repo offline si aplica) + pantalla + navegación + acceso desde el apartado correcto.
- [ ] Revisión `/code-review` sin hallazgos abiertos de severidad alta.
- [ ] `08-PROGRESO.md` actualizado; errores en `09-BITACORA-ERRORES.md`.

## 6. Riesgos y mitigaciones
| Riesgo | Mitigación |
|--------|------------|
| Migración rompe el arranque (como el `chk_req_estado`) | Idempotencia + arranque local antes de commitear + bitácora. |
| Carpetas Cloudinary divergentes | Helper único `cloudinary_paths` (Fase 1); prohibido pasar `folder=` literal en routers. |
| Acoplamiento al core de servicios (Fase 4) | Tablas nuevas que **referencian** servicio sin alterar su esquema; feature-flag si hace falta. |
| Alcance ITSE muy grande | Se parte en sub-puntos (catálogo → inspección → fotos → PDF) y va al final. |
| Trabajo móvil sin API estable | Backend de cada módulo se cierra y arranca antes de tocar Flutter. |

## 7. Métricas de avance
Se miden en `08-PROGRESO.md`: % de puntos cerrados por fase, nº de errores detectados/resueltos, módulos con arranque limpio, pantallas integradas.
