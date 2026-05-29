# 08 · Progreso (tracker vivo)

> Se actualiza al cerrar cada punto. Estados: ⬜ pendiente · 🟦 en curso · ✅ hecho · ⛔ bloqueado.
> "Arranque" = el backend levantó limpio tras la migración del punto.

## Resumen por fase
| Fase | Módulo | Estado | % puntos |
|------|--------|--------|----------|
| 0 | Fundaciones (convenciones, catálogos Zona/Ubicación/Área, seeds RBAC) | 🟦 backend ✅ / app ⬜ | 70% |
| 1 | Cloudinary unificado + Galería Global | ✅ completa | 100% |
| 2 | EPP | 🟦 backend ✅ / app ✅ (core) | 85% |
| 3 | Calibraciones + Equipos Averiados | 🟦 backend ✅ / app ✅ (core) | 85% |
| 4 | Garantías/Correctivos + Observaciones | 🟦 backend ✅ / app ✅ (core) | 85% |
| 5 | Inspección ITSE | 🟦 backend ✅ / app ✅ (lista/alta) | 75% |

## Detalle de puntos

### Fase 0 — Fundaciones
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 0.1 | Catálogos Zona / Ubicación / Área (modelo+API) | ✅ backend / ⬜ app | ✅ Railway | `feat(catalogos)` | API `/catalogos` (12 endpoints) verificada e2e. UI de gestión en app: pendiente (se hará cuando EPP/ITSE consuman los selects). |
| 0.2 | Seeds RBAC base + helper de verificación de permiso | ✅ | ✅ Railway | `feat(catalogos)` | `core/permisos.py` + `db/rbac_seed.py`; permisos 'catalogos' sembrados (minúsculas, ON CONFLICT). |

### Fase 1 — Cloudinary + Galería
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 1.1 | Helper `cloudinary_paths` + refactor call-sites | ✅ | ✅ Railway | `refactor(cloudinary)` | Helper + `carpeta_biometrico`. Refactorizados 6 call-sites (dashboard/perfil, permisos/firma, asistencia bio+selfie, operaciones evidencia+mantenimiento) a la raíz única. py_compile OK. |
| 1.2 | Servicio `subir_e_indexar` (+ `registrar_recurso`, borrado) | ✅ | ✅ Railway | `feat(galeria)` | en `cloudinary_service.py` |
| 1.3 | Modelo+migración `recurso_cloudinary` | ✅ | ✅ Railway | `feat(galeria)` | _pre_create; CHECK solo en recurso_tipo |
| 1.4 | Backfill re-indexado | ✅ | ✅ Railway | `feat(galeria)` backfill | `migrations/backfill_recurso_cloudinary.py` (17 tablas, idempotente). Ejecutado en Railway: indexó los assets existentes (firma+biométrico). `foto_asistencia` omitido (sin empresa_id directo). |
| 1.5 | API `/galeria` | ✅ | ✅ Railway | `feat(galeria)` | listar/filtrar/entidad/subir/borrar; e2e OK |
| 1.6 | App `pantalla_galeria` + accesos contextuales | ✅ | n/a (front) | `feat(galeria)` app | model+service+pantalla (grid/visor/subida image_picker/borrado, modo global y contextual). `flutter analyze`: sin issues. Rama `feat/app-fase1-galeria`. |

### Fase 2 — EPP
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 2.1 | Modelos + migración + seeds permisos | ⬜ | — | — | |
| 2.2 | API catálogo + imagen | ⬜ | — | — | |
| 2.3 | API entregas (stock+firma+PDF+index) | ⬜ | — | — | |
| 2.4 | API ingresos (stock) | ⬜ | — | — | |
| 2.5 | App catálogo/entregas/ingresos | ⬜ | — | — | |

### Fase 3 — Calibraciones + Equipos Averiados
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 3.A1 | Modelo+migración `calibracion` | ⬜ | — | — | |
| 3.A2 | API calibraciones + certificado | ⬜ | — | — | |
| 3.A3 | Aviso de vencimiento (scheduler) | ⬜ | — | — | |
| 3.B1 | ALTER equipo + `equipo_estado_mov` | ⬜ | — | — | |
| 3.B2 | API estado operativo | ⬜ | — | — | |
| 3.C | App (calibraciones + estado) | ⬜ | — | — | |

### Fase 4 — Correctivos + Observaciones
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 4.1 | Modelos + migración + permisos | ⬜ | — | — | |
| 4.2 | API correctivos + transiciones | ⬜ | — | — | |
| 4.3 | API observaciones + PDF descargo | ⬜ | — | — | |
| 4.4 | App en detalle de servicio | ⬜ | — | — | |

### Fase 5 — ITSE
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 5.1 | Modelos + migración + permisos | ⬜ | — | — | |
| 5.2 | API inspección (CRUD) | ⬜ | — | — | |
| 5.3 | API tableros + ítems | ⬜ | — | — | |
| 5.4 | API fotos (galería) | ⬜ | — | — | |
| 5.5 | API finalizar + PDF | ⬜ | — | — | |
| 5.6 | App lista + wizard datos/tableros | ⬜ | — | — | |
| 5.7 | App ítems + fotos + finalizar | ⬜ | — | — | |

## Bitácora de hitos
| Fecha | Hito | Detalle |
|-------|------|---------|
| 2026-05-29 | Plan creado | Set de planificación inicial generado. |
| 2026-05-29 | Fase 0 backend ✅ | Catálogos (ubicación/zona/área) + RBAC. Migración idempotente verificada x2 en Railway + e2e CRUD. Rama `feat/backend-fase0-catalogos-rbac`. |
| 2026-05-29 | Fase 1 backend ✅ | Cloudinary unificado + índice `recurso_cloudinary` + API `/galeria`. Migración idempotente x2 + e2e listar/borrar. Mismo branch. |
| 2026-05-29 | Fase 1 galería app ✅ | `pantalla_galeria` (grid/visor/subida/borrado, modo global+contextual). `flutter analyze` limpio. Rama `feat/app-fase1-galeria`. Backend pusheado a origin. |
| 2026-05-29 | Fase 1 cierre fino ✅ | Refactor de 6 call-sites Cloudinary a raíz única (1.1) + backfill ejecutado (1.4). **Fase 1 al 100%.** Doc `10-INTEGRACION-Y-PRUEBAS.md` agregado. |

| 2026-05-29 | Fases 2-5 backend ✅ | EPP, Calibraciones+Estado, Correctivos+Observaciones, ITSE. Todas las migraciones idempotentes x2 en Railway + py_compile + import de routers. Rama `feat/backend-fases-2-5`. |
| 2026-05-29 | Fases 2-5 app (core) ✅ | models+services + pantallas (EPP, Calibraciones, Correctivos, ITSE) en `Más>Módulos`. `flutter analyze` limpio. Rama `feat/app-fases-2-5`. |

## Ramas creadas
- `feat/backend-fase0-catalogos-rbac` (Fase 0+1 backend) · `feat/app-fase1-galeria` (galería app)
- `feat/backend-fases-2-5` (Fases 2-5 backend, stack sobre fundaciones) · `feat/app-fases-2-5` (Fases 2-5 app, stack sobre galería)

## Refinamiento — hecho
- ✅ **Informes de servicio (PDF)**: pre-informe (procedimientos + evidencias) e informe final (al cerrar). Backend `feat/backend-refinamiento` + App `feat/app-refinamiento` (`PantallaInformesServicio` desde el detalle).
- ✅ **PDFs de módulos**: constancia de entrega EPP, informe de correctivo, informe ITSE entregable (con fotos). Módulo `services/pdf_docs.py` (reusa `pdf_informe_servicio`). Endpoints `POST /epp/entregas/{id}/constancia`, `/correctivos/{id}/generar-informe`, `/itse/{id}/informe` (+ auto al finalizar ITSE). App: botón PDF por fila (copia el enlace). Verificado: 3 PDFs válidos + import.

## Pendientes (refinamiento — "commits paso a paso")
- **Flujos avanzados de app**: entrega EPP con empleado+ítems+firma; detalle ITSE (tableros/ítems/fotos/finalizar); alta de calibración/correctivo con picker de equipo/servicio; subir certificado/informe desde la app.
- **`url_launcher`**: abrir los PDFs directo (hoy se copia el enlace).
- **Fase 0 app**: UI de gestión de catálogos.
- **backfill foto_asistencia** (vía join).
- **Flujos avanzados de app**: entrega EPP con selección de empleado+ítems+firma; detalle ITSE (tableros/ítems/fotos/finalizar); alta de calibración/correctivo con picker de equipo/servicio; subir certificado/informe desde la app.
- **Fase 0 app**: UI de gestión de catálogos (ubicación/zona/área) y selects reutilizables.
- **backfill foto_asistencia** (sin empresa_id directo; vía join).
- **Integración/pruebas**: ver `10-INTEGRACION-Y-PRUEBAS.md`. Orden por fase: mergear backend→`Backend` (deploy Railway) → smoke en `/docs` → mergear app→`e-zyro-app` → APK → probar.
