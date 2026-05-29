# 04 · Garantías/Correctivos + Historial de Observaciones (Descargos) (Fase 4)

> **Acoplado al core de servicios.** Por eso va tras dominar el patrón en EPP/Calibraciones.
> Reutiliza `proyecto_servicio`, `operaciones`, `informe_tecnico`, generación de PDF y la galería.

## Mapeo desde el ERP
- **Garantías – Correctivos (3):** un correctivo es un trabajo asociado a un **servicio** existente, con su propio alcance, fechas inicio/fin, estado, **informe técnico** y descargo final ("Generar Descargo y Finalizar"). Flujo de aprobación de informe (Aprobar/Desaprobar/Corregir).
- **Historial de Observaciones (4):** por servicio, registro de **observaciones y recomendaciones** con fecha de descargo y quién lo registró.

## Decisión de diseño
**No alterar** el esquema de `proyecto_servicio`. Se añaden tablas que lo **referencian**:

### `servicio_correctivo`
| col | tipo | nota |
|-----|------|------|
| id | String(36) PK | |
| empresa_id | FK empresa | NOT NULL |
| servicio_id | FK proyecto_servicio | NOT NULL (servicio padre) |
| codigo | String(30) | correlativo tipo 'YYYY-NNN' (reusar generador de OT de operaciones.py) |
| alcance | String(500) | |
| fecha_inicio | Date | nullable |
| fecha_fin | Date | nullable |
| estado | String(20) | CHECK in ('registrado','en_proceso','en_revision','aprobado','desaprobado','finalizado','anulado') |
| informe_url | Text | nullable (PDF) |
| created_at/updated_at | | |

### `servicio_observacion` (descargos)
| id, empresa_id, servicio_id (FK proyecto_servicio), correctivo_id (FK servicio_correctivo, nullable), observaciones (Text), recomendaciones (Text), fecha_descargo (Date), registrado_por_id (FK empleado), created_at |

- Migración: tablas nuevas con FK uuid → `_pre_create`. CHECK de estado **completo** (lección `chk_req_estado`). Espejo SQL.
- Permisos: `correctivo.ver/crear/editar/aprobar/finalizar`, `observacion.ver/crear/editar/eliminar`.

## API `app/routers/correctivos.py` (prefix `/correctivos`)
- `GET /correctivos` (filtros: servicio_id, estado, fechas) · `POST` · `PUT/{id}` · `DELETE/{id}`.
- `POST /correctivos/{id}/informe` — sube PDF informe (Cloudinary + index).
- `POST /correctivos/{id}/revision` — aprobar/desaprobar/corregir (transición de estado, valida estado origen).
- `POST /correctivos/{id}/finalizar` — genera descargo final + estado `finalizado`.
- Observaciones (puede ir aquí o en `operaciones.py`):
  - `GET /servicios/{servicio_id}/observaciones` · `POST` · `PUT/{id}` · `DELETE/{id}`.
- Schemas en `app/schemas/correctivos.py`.
- **Filtrado por empresa + validación de que el servicio padre pertenece a la empresa del token.**

## PDF
- Informe técnico de correctivo y "Descargo y recomendaciones" (reusar `informe_tecnico` y `pdf_service`).

## App móvil
Dentro de **Operaciones** (`pantalla_operaciones.dart` / `pantalla_detalle_servicio.dart`):
- En el detalle de un servicio: pestaña/acción "Correctivos" → lista + alta + transición de estado + subir/ver informe + finalizar con descargo.
- Acción "Observaciones/Descargos": lista por servicio + alta (observaciones + recomendaciones).
- `models/correctivo_models.dart`, `services/correctivo_service.dart`, `screens/pantalla_correctivos.dart` (o secciones dentro de detalle de servicio).

## Orden interno
1. Modelos + migración (`_pre_create`) + seeds permisos → arranque limpio.
2. API correctivos CRUD + transiciones de estado → arranque + commit.
3. API observaciones + PDF descargo → arranque + commit.
4. App: integrar en detalle de servicio.

## Checklist anti-errores
- [ ] CHECK de `estado` del correctivo incluye TODOS los estados de las transiciones.
- [ ] Las transiciones validan el estado de origen (no saltar de 'registrado' a 'finalizado').
- [ ] `servicio_id`/`correctivo_id` validados contra la empresa del token (no IDOR).
- [ ] Informes/descargos indexados en galería (`entidad_tipo='correctivo'`).
- [ ] No se altera el esquema de `proyecto_servicio`.

## Definition of Done
- [ ] Correctivos con ciclo de vida completo (alta → revisión → finalizar) + informe PDF.
- [ ] Observaciones/descargos por servicio (CRUD).
- [ ] App integrada en el detalle de servicio.
- [ ] Backend arranca limpio; revisión OK; PROGRESO actualizado.
