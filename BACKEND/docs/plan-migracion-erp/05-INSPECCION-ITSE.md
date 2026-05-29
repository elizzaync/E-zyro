# 05 · Inspección ITSE (Fase 5 — el más grande, va al final)

> Reutiliza TODO lo anterior: empresa/ubicación/zona (Fase 0), galería+Cloudinary+PDF (Fase 1),
> patrón de evidencias y CRUD (Fases 2-4). Se parte en sub-puntos para controlar el tamaño.

## Mapeo desde el ERP (sección 23)
Flujo observado:
- Seleccionar **empresa solicitante + ubicación + zona**.
- Dos modos: **POR TABLERO** (inspección específica de tableros eléctricos) o **POR ZONA** (inspección general).
- Crear/gestionar **tableros** (nombre, ambiente, descripción) y **equipos** asociados.
- **Tomar fotos / seleccionar de galería** como evidencia.
- **Generar PDF** entregable al cliente.
- Catálogos de apoyo: alta rápida de empresa, ubicación, zona (ya cubiertos en Fase 0).

## Ubicación en la app
**Operaciones** (entregable a cliente) con acceso también desde "Más". Pantalla propia por su tamaño.

## Modelo de datos
Reutiliza `empresa`(solicitante), `ubicacion`, `zona` (Fase 0), `recurso_cloudinary` (fotos).

### `inspeccion_itse`
| col | tipo | nota |
|-----|------|------|
| id | String(36) PK | |
| empresa_id | FK empresa | NOT NULL (empresa dueña del sistema) |
| cliente_id | FK empresa_solicitante | empresa inspeccionada |
| ubicacion_id | FK ubicacion | |
| zona_id | FK zona | nullable |
| modo | String(20) | CHECK in ('tablero','zona') |
| fecha | Date | |
| estado | String(20) | CHECK in ('borrador','en_proceso','finalizada','anulada') |
| pdf_url | Text | nullable |
| observaciones | Text | nullable |
| registrado_por_id | FK empleado | |
| created_at/updated_at | | |

### `inspeccion_tablero`
| id, inspeccion_id (FK), nombre, ambiente, descripcion, created_at | (solo modo 'tablero') |

### `inspeccion_item` (hallazgos/equipos revisados)
| id, inspeccion_id (FK), tablero_id (FK, nullable), descripcion, resultado String(20) (conforme/observado/no_conforme), observacion, created_at |

> Las **fotos** no llevan tabla propia: se suben con el servicio indexado (`recurso_cloudinary`, `entidad_tipo='itse'`, `entidad_id=inspeccion_id` o `tablero_id`). La galería ya las lista/filtra.

- Migración: todas con FK uuid → `_pre_create`. CHECKs completos. Espejo SQL.
- Permisos: `itse.ver/crear/editar/finalizar/eliminar`.

## API `app/routers/itse.py` (prefix `/itse`)
- `GET /itse` (filtros: cliente, ubicación, modo, estado, fechas) · `POST` (crea borrador) · `PUT/{id}` · `DELETE/{id}`.
- Tableros: `POST /itse/{id}/tableros` · `PUT/tableros/{tid}` · `DELETE/tableros/{tid}`.
- Ítems: `POST /itse/{id}/items` · `PUT/items/{iid}` · `DELETE/items/{iid}`.
- Fotos: `POST /itse/{id}/fotos` (sube a `carpeta_itse` + index; opcional `tablero_id`).
- `POST /itse/{id}/finalizar` — genera **PDF de inspección** (datos cliente/ubicación, tableros, ítems con resultados, fotos) y marca `finalizada`.
- Schemas en `app/schemas/itse.py`.

## PDF entregable
Plantilla de informe ITSE en `pdf_service`: portada (cliente, ubicación, fecha, inspector), por tablero/zona los ítems con resultado, galería de fotos, conclusiones. Es el entregable al cliente → cuidar formato.

## App móvil
- `models/itse_models.dart` (Inspeccion, Tablero, Item).
- `services/itse_service.dart`.
- `screens/`:
  - `pantalla_itse.dart` — lista de inspecciones + filtros + alta.
  - `pantalla_itse_detalle.dart` — wizard: 1) datos (cliente/ubicación/zona/modo) → 2) tableros (si modo tablero) → 3) ítems + **fotos (cámara/galería)** → 4) finalizar y ver PDF.
- Reutilizar `pantalla_camara_evidencia.dart` y el flujo de subida ya existente.
- **Offline-first recomendado** (inspecciones en sitio sin señal): encolar fotos/ítems y sincronizar (`repositories/itse_local_repo.dart`).

## Sub-puntos (para controlar tamaño)
5.1 Modelos + migración + permisos → arranque limpio.
5.2 API inspección (CRUD cabecera) → arranque + commit.
5.3 API tableros + ítems → arranque + commit.
5.4 API fotos (galería) → arranque + commit.
5.5 API finalizar + PDF → arranque + commit.
5.6 App: lista + wizard datos/tableros.
5.7 App: ítems + fotos + finalizar/PDF (+ offline si aplica).

## Checklist anti-errores
- [ ] CHECK de `modo`, `estado`, `resultado` completos.
- [ ] Modo 'zona' no exige tableros; modo 'tablero' valida al menos uno.
- [ ] cliente/ubicación/zona validados contra empresa del token.
- [ ] Fotos indexadas con `entidad_id` correcto (inspección o tablero).
- [ ] Finalizar es idempotente (no regenera/duplica PDF ni recurso).

## Definition of Done
- [ ] Inspección completa (datos → tableros → ítems → fotos → PDF) por ambos modos.
- [ ] PDF entregable correcto.
- [ ] App con wizard y captura de fotos (offline si se decide).
- [ ] Backend arranca limpio; revisión OK; PROGRESO actualizado.
