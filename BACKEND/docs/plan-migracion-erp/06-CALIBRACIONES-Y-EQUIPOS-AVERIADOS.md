# 06 · Calibraciones + Equipos Averiados (Fase 3)

> Extiende el módulo de equipos ya existente (`models/equipo.py`, `orden_mantenimiento`, `plan_mantenimiento`,
> router `operaciones`/pantalla `mantenimientos`). Bajo riesgo, reutiliza el patrón de EPP.

## Mapeo desde el ERP
- **Calibraciones (27):** por equipo → última/próxima calibración, empresa responsable, **archivo de certificado (PDF)**.
- **Equipos Averiados / Inoperativos (28):** marcar un equipo (o cantidad) como inoperativo con motivo, y reactivarlo. Tabs "Operativos / Inoperativos", reporte PDF.

## Ubicación en la app
Dentro de **Equipos/Mantenimientos** (`pantalla_mantenimientos.dart` / `pantalla_equipos.dart`): dos acciones nuevas — "Calibraciones" y "Estado operativo".

---

## Parte A — Calibraciones

### Modelo `calibracion`
| col | tipo | nota |
|-----|------|------|
| id | String(36) PK | |
| empresa_id | FK empresa | NOT NULL |
| equipo_id | FK equipo | NOT NULL |
| fecha_ultima | Date | |
| fecha_proxima | Date | |
| empresa_responsable | String(200) | quien calibra |
| certificado_url | Text | nullable (Cloudinary raw PDF) |
| observacion | String(500) | nullable |
| created_at/updated_at | | |
- Índice `(empresa_id, equipo_id, fecha_proxima)` para alertas de vencimiento.
- Va en `_pre_create_migrations()` (FK uuid). Espejo SQL.
- Permisos: `calibracion.ver`, `calibracion.crear`, `calibracion.editar`, `calibracion.eliminar`.

### API `app/routers/calibraciones.py` (prefix `/calibraciones`)
- `GET /calibraciones` (filtros: equipo, vencidas, por_vencer<=30d) · `POST` · `PUT/{id}` · `DELETE/{id}`.
- `POST /calibraciones/{id}/certificado` — sube PDF a `carpeta_calibracion(empresa_id, equipo_id)` + indexa (`entidad_tipo='calibracion'`).
- Integración con **scheduler** (`services/scheduler_service.py`): notificación push (FCM) cuando `fecha_proxima` esté próxima (reusar el scheduler existente).

---

## Parte B — Equipos Averiados (estado operativo)

### Enfoque: tabla de movimientos de estado (no romper `equipo`)
`equipo` gana (vía `ALTER ADD COLUMN IF NOT EXISTS`) dos campos derivados/cacheados:
- `cantidad_inoperativa Integer DEFAULT 0`
- `estado_operativo String(20) DEFAULT 'operativo'` (CHECK in 'operativo','parcial','inoperativo').

Nueva tabla **`equipo_estado_mov`** (bitácora, fuente de verdad del cambio):
| id, empresa_id, equipo_id (FK), accion String(20) CHECK in ('inoperativo','reactivar'), cantidad Integer, motivo String(300), fecha (Date), registrado_por_id, created_at |

- Al insertar un movimiento, **en la misma transacción** recalcular `equipo.cantidad_inoperativa` y `estado_operativo`.
- Migración: `ALTER` idempotente + `CREATE TABLE IF NOT EXISTS` (tabla nueva con FK uuid → `_pre_create`).
- Permisos: `equipo.marcar_inoperativo`, `equipo.reactivar`, `equipo.ver_estado`.

### API (puede ir en `routers/operaciones.py` o nuevo `routers/equipos_estado.py`)
- `GET /equipos/estado` (filtros: operativos | inoperativos, q).
- `POST /equipos/{id}/inoperativo` — body: cantidad, motivo. Valida cantidad <= disponible.
- `POST /equipos/{id}/reactivar` — body: cantidad. Valida <= inoperativa.
- `GET /equipos/{id}/historial-estado`.
- Reporte PDF de inoperativos (`pdf_service`).

## App móvil
- `models/calibracion_models.dart`, ampliar `mantenimiento_models.dart` o nuevo `equipo_estado_models.dart`.
- `services/`: `calibracion_service.dart`; ampliar `mantenimiento_service.dart` para estado operativo.
- `screens/`:
  - En `pantalla_mantenimientos.dart`/`pantalla_equipos.dart`: botón "Calibraciones" → `pantalla_calibraciones.dart` (lista + alta + subir certificado + alertas de vencimiento).
  - "Estado operativo": acción para marcar inoperativo/reactivar (con motivo) + filtro operativos/inoperativos + historial en `pantalla_historial_equipo.dart`.

## Orden interno
A1 calibracion modelo+migración → A2 API+certificado → A3 scheduler aviso → (arranque+commit) →
B1 ALTER equipo + tabla mov → B2 API estado → (arranque+commit) → App ambas partes.

## Checklist anti-errores
- [ ] `estado_operativo`/`cantidad_inoperativa` siempre consistentes con la bitácora `equipo_estado_mov`.
- [ ] No marcar inoperativa más cantidad que la disponible; no reactivar más que la inoperativa.
- [ ] CHECKs de `accion` y `estado_operativo` completos.
- [ ] Certificado PDF indexado en galería.
- [ ] Alertas de vencimiento no duplican notificaciones (idempotencia en scheduler).

## Definition of Done
- [ ] Calibraciones: CRUD + certificado + alerta de próxima.
- [ ] Estado operativo: marcar/reactivar con motivo, historial y reporte.
- [ ] App integrada en Mantenimientos/Equipos.
- [ ] Backend arranca limpio; revisión OK; PROGRESO actualizado.
