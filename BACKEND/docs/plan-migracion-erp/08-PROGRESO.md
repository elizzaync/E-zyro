# 08 · Progreso (tracker vivo)

> Se actualiza al cerrar cada punto. Estados: ⬜ pendiente · 🟦 en curso · ✅ hecho · ⛔ bloqueado.
> "Arranque" = el backend levantó limpio tras la migración del punto.

## Resumen por fase
| Fase | Módulo | Estado | % puntos |
|------|--------|--------|----------|
| 0 | Fundaciones (convenciones, catálogos Zona/Ubicación/Área, seeds RBAC) | ⬜ | 0% |
| 1 | Cloudinary unificado + Galería Global | ⬜ | 0% |
| 2 | EPP | ⬜ | 0% |
| 3 | Calibraciones + Equipos Averiados | ⬜ | 0% |
| 4 | Garantías/Correctivos + Observaciones | ⬜ | 0% |
| 5 | Inspección ITSE | ⬜ | 0% |

## Detalle de puntos

### Fase 0 — Fundaciones
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 0.1 | Catálogos Zona / Ubicación / Área (modelo+API+app) | ⬜ | — | — | base de selects de EPP/ITSE |
| 0.2 | Seeds RBAC base + helper de verificación de permiso | ⬜ | — | — | |

### Fase 1 — Cloudinary + Galería
| Punto | Descripción | Estado | Arranque | Commit | Notas |
|-------|-------------|--------|----------|--------|-------|
| 1.1 | Helper `cloudinary_paths` + refactor call-sites | ⬜ | — | — | |
| 1.2 | Servicio `subir_e_indexar` | ⬜ | — | — | |
| 1.3 | Modelo+migración `recurso_cloudinary` | ⬜ | — | — | _pre_create |
| 1.4 | Backfill re-indexado | ⬜ | — | — | no mueve archivos |
| 1.5 | API `/galeria` | ⬜ | — | — | |
| 1.6 | App `pantalla_galeria` + accesos contextuales | ⬜ | — | — | |

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
