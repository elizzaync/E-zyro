# 01 · Convenciones (dónde va cada cosa)

> Reglas verificadas contra el código real de ambos repos. Respetar estas convenciones es lo que
> hace que el plan sea ejecutable sin fricción.

## A. Backend (FastAPI) — `D:\e-zyro-backend\BACKEND\app`

### Estructura
```
app/
 ├─ models/<modulo>.py      # SQLAlchemy. PK String(36) uuid, default _uuid(). empresa_id obligatorio.
 ├─ schemas/<modulo>.py     # Pydantic (Create / Update / Out).
 ├─ routers/<modulo>.py     # APIRouter con prefix y tags; RBAC + filtro empresa_id.
 ├─ services/<x>_service.py # Lógica reutilizable (cloudinary, pdf, fcm, scheduler).
 ├─ core/                   # config, seguridad (JWT), audit_context, cloudinary config.
 ├─ db/database.py          # engine, Base, get_db.
 └─ main.py                 # imports de modelos, include_router, migraciones (lifespan).
```

### Reglas de modelo
- PK: `id = Column(String(36), primary_key=True, default=_uuid)` con `def _uuid(): return str(uuid.uuid4())`.
- **`empresa_id = Column(String(36), ForeignKey("empresa.id"), nullable=False)`** en toda tabla de negocio.
- Timestamps: `created_at` (default `datetime.utcnow`), `updated_at` nullable.
- Estados como `String(n)` + **CHECK constraint** que liste TODOS los valores del flujo (lección del incidente `chk_req_estado`: el CHECK debe incluir cada estado que el código pueda escribir).
- **Registrar el nuevo módulo en el bloque de imports de modelos de `main.py`** (`from app.models import (... )`) o `Base.metadata.create_all` no lo creará.

### Reglas de migración (críticas)
Dos puntos de enganche en `main.py`:
- `_pre_create_migrations()` — corre **antes** de `create_all`. Úsalo SOLO para tablas con **FK de tipo `uuid`** (p. ej. que referencian `empresa(id)` que es `uuid`), creándolas con `uuid` explícito para evitar el choque `VARCHAR(36)` vs `uuid`.
- `_run_migrations()` — corre **después** de `create_all`. Úsalo para `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, recrear CHECKs (`DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT`), e `UPDATE` de datos (siempre idempotentes).
- **Espejo SQL**: además, dejar el SQL equivalente en `BACKEND/migrations/<fecha>_<modulo>.sql` para crear DB desde cero y para DBAs.
- Toda migración: `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS`. Nunca asumas estado previo.

### Reglas de router
- `router = APIRouter(prefix="/<modulo>", tags=["<Modulo>"])`.
- Inyectar `db: Session = Depends(get_db)` y el usuario/empresa del token (patrón de seguridad existente en `core/security.py`).
- **Filtrar SIEMPRE por `empresa_id` del token**; nunca confiar en un `empresa_id` del body.
- Validaciones de negocio devuelven `HTTPException` con `status_code` y `detail` claros (patrón de `operaciones.py`).
- Registrar en `main.py`: `from app.routers import <modulo> as <modulo>_router` + `app.include_router(<modulo>_router.router)`.

### RBAC / permisos
- Existe RBAC (`rol`, `permiso`, `rol_permiso`, `usuario_rol`, `usuario_permiso`). Cada módulo nuevo define sus **permisos** (`epp.ver`, `epp.entregar`, `itse.crear`, …) y se siembran (seed idempotente) en la migración. Endpoints sensibles verifican permiso.

### Cloudinary (ver detalle en `02`)
- **Prohibido** pasar `folder="..."` literal en routers. Usar `services/cloudinary_paths.py` (Fase 1) → `carpeta_epp(empresa_id, epp_id)`, etc.
- Toda subida se **indexa** en `recurso_cloudinary` (alimenta la Galería Global).

## B. App móvil (Flutter) — `D:\e-zyro-app\e_zyro_app\lib`

### Estructura
```
lib/
 ├─ screens/pantalla_<x>.dart   # UI.
 ├─ models/<x>_models.dart       # DTOs (fromJson/toJson).
 ├─ services/<x>_service.dart    # Llamadas API vía core/api_client.dart → ApiResult.
 ├─ repositories/<x>_local_repo.dart  # SOLO si el módulo necesita offline (usa core/local_db.dart).
 ├─ core/                        # api_client, api_result, app_constants, local_db, connectivity, sync.
 ├─ widgets/                     # Reutilizables (stat_card, paper, etc.).
 └─ main.dart                    # MaterialApp + rutas nombradas + MainShell (5 tabs).
```

### Navegación
- `MainShell` tiene 5 pestañas: **Home(0) · Operaciones(1) · Logística(2) · Personal(3) · Más(4)**.
- Módulos nuevos se enganchan así:
  - Si pertenece a un tab existente → se agrega como sección/acción dentro de esa pantalla (p. ej. EPP dentro de Logística, Calibraciones dentro de Mantenimientos).
  - Si es transversal o secundario → `_MenuItem` en `screens/pantalla_mas.dart` con `Navigator.push(MaterialPageRoute(builder: (_) => const PantallaX()))`.
  - Si necesita deep-link (push notification) → añadir **ruta nombrada** en `main.dart` `_routes()`.
- Patrón de `_MenuItem` (icono + título + onTap) ya existe en `pantalla_mas.dart`; reutilizarlo.

### Servicios y datos
- Las llamadas pasan por `core/api_client.dart` y devuelven `ApiResult` (manejo uniforme de error/éxito).
- Base URL / endpoints centralizados en `core/app_constants.dart`.
- **Offline-first** (cuando aplica, p. ej. registrar entrega EPP en campo sin señal): encolar en `repositories/*_local_repo.dart` + `core/local_db.dart` y sincronizar con `services/sync_service.dart`. Para módulos puramente administrativos (catálogos), no es necesario.

### UI
- Reutilizar tema, `widgets/` y estilo existentes. Soporte modo oscuro (hay `ValueNotifier` de tema en `pantalla_mas.dart`).
- Imágenes desde Cloudinary con caché (`cached_network_image`, ya usado).

## C. Formato de commits
```
<tipo>(<modulo>): <resumen breve en imperativo>

<cuerpo opcional: qué y por qué>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```
Tipos: `feat`, `fix`, `refactor`, `docs`, `chore`. Un commit por punto del subplan.

## D. Checklist anti-errores (revisar en CADA punto)
- [ ] ¿El modelo nuevo está importado en `main.py`?
- [ ] ¿La migración es idempotente y el CHECK lista TODOS los estados posibles?
- [ ] ¿Tipos de FK coinciden (`uuid` en DB)? ¿Va en `_pre_create` si referencia `empresa(id)` uuid?
- [ ] ¿El endpoint filtra por `empresa_id` del token y valida permiso RBAC?
- [ ] ¿La subida a Cloudinary usa el helper de carpetas y se indexa en `recurso_cloudinary`?
- [ ] ¿Se elimina el recurso viejo en Cloudinary al reemplazar (evitar huérfanos)?
- [ ] ¿El backend arranca limpio tras la migración?
- [ ] ¿El modelo Dart `fromJson` cubre todos los campos del schema `Out`?
- [ ] ¿La pantalla maneja estados loading/empty/error?
