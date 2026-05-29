# 02 · Cloudinary unificado + Galería Global (Fase 1 — transversal)

## Problema actual (verificado en código)
Las carpetas en Cloudinary son **inconsistentes**. Convenciones encontradas hoy en `routers/`+`services/`:
- `e-zyro/perfiles`, `e-zyro/firmas`  (raíz con guion)
- `e_zyro/{empresa_id}/mantenimiento/{equipo_id}`  (raíz con guion bajo)
- `evidencias/{empresa_id}/{proyecto_id}`  (sin raíz)
- `asistencia/{empresa_id}/{empleado_id}`  (sin raíz)
- `biometrico/{empresa_id}/{usuario_id}`  (sin raíz)

Tres raíces distintas (`e-zyro`, `e_zyro`, ninguna) → imposible navegar/auditar la nube y no hay índice consultable. Esto bloquea la **Galería Global**.

## Objetivo
1. **Taxonomía única** de carpetas, generada por un helper central (nadie escribe `folder=` a mano).
2. **Índice `recurso_cloudinary`** que registra cada asset subido → fuente de datos de la galería y de la limpieza de huérfanos.
3. **Galería Global** (backend + pantalla) con filtros por entidad, tipo, fecha y búsqueda.
4. **Backfill** no destructivo de lo ya subido (re-indexar; re-carpetar es opcional y diferido).

## Taxonomía propuesta (raíz única `e-zyro/`)
```
e-zyro/{empresa_id}/perfiles/{usuario_id}
e-zyro/{empresa_id}/firmas/{contexto}/{entidad_id}
e-zyro/{empresa_id}/biometrico/{usuario_id}
e-zyro/{empresa_id}/asistencia/{empleado_id}/{aaaa-mm}
e-zyro/{empresa_id}/evidencias/{proyecto_id}/{servicio_id}
e-zyro/{empresa_id}/mantenimiento/{equipo_id}
e-zyro/{empresa_id}/epp/{epp_id}
e-zyro/{empresa_id}/epp-entregas/{entrega_id}
e-zyro/{empresa_id}/calibraciones/{equipo_id}
e-zyro/{empresa_id}/itse/{inspeccion_id}
e-zyro/{empresa_id}/planos/{plano_id}
e-zyro/{empresa_id}/documentos/{carpeta_id}
e-zyro/{empresa_id}/galeria/{aaaa}/{mm}    # subidas libres a la galería
```
Regla: **raíz siempre `e-zyro` + `empresa_id` como segundo nivel** (aislamiento multiempresa también en la nube).

## Punto 1.1 — Helper central de carpetas
Nuevo `app/services/cloudinary_paths.py`:
```python
ROOT = "e-zyro"
def _emp(empresa_id: str) -> str: return f"{ROOT}/{empresa_id}"
def carpeta_perfil(empresa_id, usuario_id):        return f"{_emp(empresa_id)}/perfiles"
def carpeta_firma(empresa_id, contexto, ent_id):    return f"{_emp(empresa_id)}/firmas/{contexto}"
def carpeta_asistencia(empresa_id, empleado_id, ym): return f"{_emp(empresa_id)}/asistencia/{empleado_id}/{ym}"
def carpeta_evidencia(empresa_id, proyecto_id, servicio_id): return f"{_emp(empresa_id)}/evidencias/{proyecto_id}/{servicio_id}"
def carpeta_mantenimiento(empresa_id, equipo_id):  return f"{_emp(empresa_id)}/mantenimiento/{equipo_id}"
def carpeta_epp(empresa_id, epp_id):               return f"{_emp(empresa_id)}/epp/{epp_id}"
def carpeta_epp_entrega(empresa_id, entrega_id):   return f"{_emp(empresa_id)}/epp-entregas/{entrega_id}"
def carpeta_calibracion(empresa_id, equipo_id):    return f"{_emp(empresa_id)}/calibraciones/{equipo_id}"
def carpeta_itse(empresa_id, inspeccion_id):       return f"{_emp(empresa_id)}/itse/{inspeccion_id}"
def carpeta_galeria(empresa_id, aaaa, mm):         return f"{_emp(empresa_id)}/galeria/{aaaa}/{mm}"
```
- Refactor de los call-sites actuales para usar estos helpers (cambio de bajo riesgo, no rompe URLs ya guardadas; solo afecta subidas futuras).

## Punto 1.2 — Servicio de subida indexada
Extender `services/cloudinary_service.py` con un wrapper que **sube + indexa**:
```python
def subir_e_indexar(*, db, empresa_id, base64_o_file, folder, public_id=None,
                    entidad_tipo, entidad_id, recurso_tipo="imagen", creado_por=None) -> RecursoCloudinary
```
Devuelve el registro indexado. Internamente reusa `subir_imagen_cloudinary` / `subir_archivo_cloudinary`, captura `public_id`, `secure_url`, `bytes`, `format` del resultado del SDK, y persiste en `recurso_cloudinary`.

## Punto 1.3 — Modelo / migración `recurso_cloudinary`
`app/models/recurso_cloudinary.py`:
| Columna | Tipo | Nota |
|---------|------|------|
| id | String(36) PK | uuid |
| empresa_id | String(36) FK empresa | NOT NULL |
| public_id | String(300) | id en Cloudinary (único por empresa) |
| secure_url | Text | URL https |
| folder | String(300) | carpeta lógica |
| recurso_tipo | String(20) | imagen \| pdf \| raw |
| entidad_tipo | String(40) | servicio \| equipo \| epp \| epp_entrega \| itse \| calibracion \| asistencia \| perfil \| galeria \| … |
| entidad_id | String(36) | id de la entidad asociada (nullable para subidas libres) |
| descripcion | String(300) | nullable |
| bytes | Integer | nullable |
| formato | String(10) | jpg/png/webp/pdf |
| creado_por_id | String(36) FK empleado/usuario | nullable |
| created_at | DateTime | default utcnow |

- Índices: `(empresa_id, entidad_tipo, entidad_id)` y `(empresa_id, created_at)`.
- Va en `_pre_create_migrations()` (FK uuid a `empresa`). Espejo en `migrations/`.
- `CHECK` para `recurso_tipo` y `entidad_tipo` listando valores válidos.

## Punto 1.4 — Backfill (re-indexar lo existente)
Script idempotente `migrations/backfill_recurso_cloudinary.py` (o función one-shot en `_run_migrations` protegida por "ejecutar solo si la tabla está vacía"):
- Recorre las columnas `*_url` existentes (foto perfil, firmas, evidencias, asistencia, mantenimiento) y crea filas en `recurso_cloudinary` derivando `public_id` de la URL (ya hay lógica de parseo en `eliminar_imagen_cloudinary`).
- **No** mueve archivos en la nube (re-carpetar es opcional y se difiere para no romper URLs guardadas).

## Punto 1.5 — API Galería Global
`app/routers/galeria.py` (prefix `/galeria`):
- `GET /galeria` — lista paginada con filtros: `entidad_tipo`, `entidad_id`, `recurso_tipo`, `fecha_desde`, `fecha_hasta`, `q` (busca en descripción/folder). Filtra por `empresa_id` del token.
- `GET /galeria/entidad/{tipo}/{id}` — recursos de una entidad concreta (para mostrar dentro de servicio/equipo/EPP).
- `POST /galeria` — subida libre a la galería (carpeta `galeria/{aaaa}/{mm}`), con `descripcion`, `entidad_tipo`/`entidad_id` opcionales.
- `DELETE /galeria/{id}` — borra en Cloudinary (`destroy(public_id)`) **y** la fila (permiso `galeria.eliminar`).
- Schemas en `app/schemas/galeria.py`.

## Punto 1.6 — App: Galería Global
- `models/galeria_models.dart` (RecursoCloudinary DTO).
- `services/galeria_service.dart` (list/upload/delete vía `api_client`).
- `screens/pantalla_galeria.dart`: grid de miniaturas (`cached_network_image`), barra de filtros (tipo, fecha, entidad), búsqueda, visor a pantalla completa, subir desde cámara/galería, borrar (según permiso).
- Acceso: `_MenuItem` "Galería" en `pantalla_mas.dart` + accesos contextuales (botón "Fotos" dentro de detalle de servicio/equipo/EPP que abre `pantalla_galeria` filtrada por esa entidad).

## Orden interno de la fase
1.1 helper → 1.3 modelo+migración → 1.2 servicio indexado → 1.4 backfill → 1.5 API → (arranque limpio + commit) → 1.6 app.

## Definition of Done
- [ ] Toda subida nueva cae en `e-zyro/{empresa_id}/...` vía helper.
- [ ] `recurso_cloudinary` poblada por subidas nuevas + backfill de las existentes.
- [ ] `/galeria` filtra y pagina; borrado elimina también en la nube (sin huérfanos).
- [ ] Pantalla de galería con filtros funcionando y accesos contextuales.
- [ ] Backend arranca limpio; commit en `feat/backend-cloudinary-galeria` y `feat/app-galeria`.
