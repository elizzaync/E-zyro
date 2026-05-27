C:\dev\code\e-zyro-app\OFFLINE_FIRST_FASES.md
# E-Zyro — Offline-first (asistencia + evidencias) · Handoff

Documento de continuidad para retomar el trabajo en otra sesión/cuenta.
**Fecha:** 2026-05-27. **Estado:** Fases 0-4 implementadas, pasan `flutter analyze` sin errores, **no probadas en dispositivo**, **no commiteadas**.

App Flutter: `C:\dev\code\e-zyro-app\e_zyro_app`
Backend (FastAPI): `C:\dev\code\e-zyro-backend\BACKEND`

---

## Objetivo y rumbo

Que el técnico de campo pueda **marcar asistencia** y **capturar evidencias de procedimientos de servicios** sin internet, sincronizando al reconectar. Decisiones acordadas con el usuario:

- **Un solo app** (se descartó la idea de una app companion).
- **Lecturas cache-first**, **escrituras write-behind** (cola local + reenvío diferido).
- **Degradación elegante**: datos cacheados + `OfflineBanner`, en vez de muros "Sin conexión".
- Multi-empresa: aislar siempre por `empresa_id`. E-SystemTIC es la empresa principal actual.

---

## Qué ya existía (no reinventar)

- Sesión: JWT 7 días en SharedPreferences + SecureStorage; `AuthService.isStoredTokenValid()` valida expiración sin red; `/auth/refresh` renueva (hasta 30 días).
- Asistencia ya era offline-first: `AsistenciaService` + `AsistenciaLocalRepo` (tabla `registro_asistencia_local`) + `SyncLogger`/`SyncLogPanel` + sync periódico/al reconectar en `MainShell`.
- El backend ya aprueba marcación offline sin selfie (rama `es_sync_sin_selfie` en `asistencia.py`).
- Conectividad: `isOnlineNotifier`, `OfflineOverlay`, `OfflineBanner`.

---

## Fases implementadas

### Fase 0 — UX offline + marcar asistencia
- `lib/models/asistencia_models.dart`: `EstadoHoy` con `toJson()` + `copyWith()`.
- `lib/services/asistencia_service.dart`: `getEstadoHoy()` y `tieneFotoBase()` cache-first (SharedPreferences). Caché de estado por fecha (la foto base persiste entre días, la jornada se reinicia). Actualización optimista del caché al marcar.
- `lib/services/dashboard_service.dart`: `getResumen()` y `getProximosServicios()` cache-first; offline devuelven caché/vacío **sin lanzar** (salvo 401 → login).
- `lib/main.dart`: se quitó `OfflineOverlay` del Home (tab 0) y se ajustó `_onTabTappedWithOfflineCheck` (Inicio + Operaciones offline-capable).

### Fase 1 — Sesión offline
- `lib/screens/pantalla_splash.dart`: rutea con `isStoredTokenValid()` (token vigente + sin bio → Home offline; expirado → Login).
- `lib/main.dart`: `_refreshTokenSilencioso()` al reconectar (throttle 30 min) para extender la ventana de 7 días.
- El login ya manejaba offline (desbloqueo biométrico con fallback + bloque "Acceso rápido offline"); no se tocó.

### Fase 2 — Caché de servicios/procedimientos
- `lib/core/local_db.dart`: BD a **v3**, tabla genérica `cache_kv(clave, valor, updated_at)`.
- `lib/repositories/cache_repo.dart` *(nuevo)*: `put`/`get`/`clearAll` (no-op en web).
- `lib/services/proyecto_service.dart`: `getProyectos()`, `getServiciosProyecto(id)`, `getDetalleServicio(id)` read-through (guarda el body crudo, re-parsea offline). Claves `op_proyectos`, `op_servicios_<id>`, `op_detalle_<id>`.
- `lib/services/auth_service.dart`: `logout()` limpia claves de caché (asistencia/dashboard) **y** `CacheRepo().clearAll()`.

### Fase 3 — Cola de evidencias offline
- `lib/core/local_db.dart`: BD a **v4**, tabla `evidencia_pendiente`.
- `lib/models/evidencia_pendiente.dart` *(nuevo)*: reusa enum `EstadoSync`.
- `lib/repositories/evidencia_local_repo.dart` *(nuevo)*.
- `lib/utils/app_notifiers.dart`: `pendientesEvidenciaNotifier`.
- `lib/services/proyecto_service.dart`: `encolarEvidencia()` (copia foto a `evidence_photos/` → cola → intento inmediato), `sincronizarEvidencias()` (retry<5, borra fila+archivo al subir), `contarEvidenciasPendientes()`.
- `lib/screens/pantalla_detalle_servicio.dart`: `_EvidenciaSheet` usa la cola (verde "subida" / ámbar "se subirá al reconectar", checkmark optimista).
- `lib/main.dart`: `_triggerSync()` drena asistencia + evidencias con un solo probe `canReachServer`.

### Fase 4 — Pulido / panel unificado
- `lib/repositories/evidencia_local_repo.dart`: `contarAbandonadas()`, `obtenerAbandonadas()`, `resetParaReintentar()`.
- `lib/services/proyecto_service.dart`: `contarEvidenciasAbandonadas()`, `resetEvidenciasParaReintentar()`, `descartarEvidenciasAbandonadas()`.
- `lib/widgets/sync_log_panel.dart`: panel unificado (chip "Evidencias", alerta de abandonadas con Reintentar/Descartar, "Forzar sync" drena ambas colas).

---

## Backend (repo aparte) — PENDIENTE redeploy a Railway

En `C:\dev\code\e-zyro-backend\BACKEND\app\routers\asistencia.py` se aplicaron (fuera de las fases offline) dos fixes que **deben desplegarse**:
1. Los 3 lookups de `Empleado` ya no filtran por `empresa_id` (solo `usuario_id` [+ `activo` en marcar]) → arregla el 404 "Empleado no encontrado".
2. Reordenado el bloque de "fuente de tiempo" en `marcar` (usaba `ahora`/`timestamp_servidor`/`motivo` antes de definirlos → `NameError`/HTTP 500).

NOTA: el bypass de admin en `dashboard.py` fue **revertido por el usuario**; no re-aplicar salvo que lo pida.

---

## Pendiente / próximos pasos

1. **QA en dispositivo** (ver matriz abajo). No se pudo probar UI desde la sesión de desarrollo.
2. **Redeploy del backend** a Railway (fixes de `asistencia.py`).
3. **Mejora opcional "precalentar caché" (Fase 2):** al estar online, descargar en segundo plano el detalle (`getDetalleServicio`) de todos los servicios asignados del técnico, para que estén offline aunque no los haya abierto uno por uno. Hoy el detalle solo se cachea si se abrió online al menos una vez.
4. (Opcional) `git commit` de todo este trabajo (actualmente sin commitear).

## Limitaciones conocidas

- Usuario que **nunca** se conectó no puede configurar foto base offline (1er setup requiere red).
- Detalle de servicio cacheado solo si se abrió online (→ lo resuelve la mejora "precalentar").
- `sqflite` no corre en web → el caché local es no-op en web (la app de campo es móvil).
- Evidencia que falla 5× online queda "abandonada"; se recupera/descarta desde el panel de sync.

## Matriz de QA (probar en dispositivo)

| # | Escenario | Esperado |
|---|---|---|
| 1 | Token vigente + avión → reabrir | Entra a Home sin login |
| 2 | Token expirado → reabrir | Va a Login |
| 3 | Reconectar dentro de la app | Token se renueva (≤1 cada 30 min) |
| 4 | Home en avión | KPIs cacheados/cero + Acciones Rápidas, sin muro |
| 5 | Avión → Asistencia → marcar | "GUARDADO OFFLINE"; reconectar → sincroniza |
| 6 | Abrir proyecto/servicio online → avión | Ve proyectos/servicios/detalle+procedimientos |
| 7 | Avión → detalle → capturar evidencia | "se subirá al reconectar"; reconectar → sube |
| 8 | Evidencia rechazada 5× | Abandonada → panel: Reintentar/Descartar |
| 9 | Panel sync (desde banner asistencia) | Chips Pendientes/Abandonados/Error perm./Evidencias; Forzar sync drena ambas |
| 10 | Logout + otro usuario | No ve datos cacheados del anterior |
| 11 | Transición online↔offline | Banner aparece/desaparece; al volver, drena colas |
