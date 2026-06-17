# Contexto — Seguridad de Inicios de Sesión (Multi-Dispositivo)

> Documento de trabajo para no perder contexto entre sesiones.
> Fecha de análisis: 2026-06-16
> Backend: `C:\E-zyro\BACKEND` · Frontend: `C:\E-zyro-frontend`

## 1. Qué pidió el usuario

> "REVISA LA SEGURIDAD QUE TENEMOS EN BASE A LOS INICIOS DE SESIÓN, ESTÁN
> SIENDO UN POCO LENTOS. Si inicio sesión en una computadora y después en mi
> celular (app móvil o web), debe **avisarme al equipo donde inicié primero**
> que otro equipo inició sesión, siendo **más específico del equipo (si fue
> celular y tal lugar)** por seguridad. Y **si pongo cerrar sesión, NO LE DEJE
> ENTRAR Y ENTRAR**."

## 2. Decisiones tomadas (confirmadas con el usuario)

| Tema | Decisión |
|------|----------|
| **Ubicación ("tal lugar")** | **Solo IP, sin ciudad** (mostrar la dirección IP cruda, sin traducir a ciudad/país). |
| **Velocidad del aviso** | **WebSocket en tiempo real** (no polling de 60s). |

## 3. Diagnóstico — sistema actual (lo que YA existe)

Ya hay un sistema multi-dispositivo: tabla `SesionUsuario` + endpoints
`/auth/sesiones` + modal "nuevo dispositivo" en el front con polling cada 60s.
Pero tiene **3 fallas reales**:

### 🔴 FALLA 1 (CRÍTICA) — "Cerrar sesión" NO expulsa de verdad
- `verificar_token()` en `app\core\security.py` **solo valida el JWT** (firma +
  expiración). **Nunca consulta `SesionUsuario.activa`.**
- Al cerrar remotamente (`DELETE /auth/sesiones/{id}` pone `activa=False`), el
  equipo expulsado **sigue funcionando hasta 4 h** (lo que dura el JWT) en todos
  los endpoints. **Solo `/auth/refresh` revisa la BD.**
- → Esto es exactamente el "entra y entra".

### 🟠 FALLA 2 — Dispositivo poco específico + sin ubicación
- En `/login` se guarda `dispositivo = user_agent[:100]` (User-Agent crudo,
  ilegible). No hay parseo a "Celular / Computadora", ni navegador, ni IP legible.
- La IP real SÍ se puede sacar (lógica `X-Forwarded-For` ya existe en
  `app\core\audit_context.py`, líneas 76-80). Hoy `/login` usa solo
  `request.client.host` (que detrás del proxy de Railway es el proxy, no el cliente).

### 🟡 FALLA 3 — Lentitud / aviso tardío + botón roto
- Aviso por **polling cada 60s** (hasta 1 min de retraso).
- `logoutAllDevices()` del front llama a `/auth/password-recovery/logout-all`,
  que **NO existe** (404) → botón roto.

## 4. Plan de implementación

### Backend (`C:\E-zyro\BACKEND`)

1. **Falla 1 — expulsión real.** En `app\core\security.py`, `verificar_token`
   debe validar que exista `SesionUsuario` con ese `token_hash` (sha256 del
   token) y `activa=True`. Para no meter una consulta BD en CADA request (y no
   empeorar la lentitud): **caché en memoria con TTL corto (~30s)** por
   token_hash + invalidación instantánea al cerrar sesión. El WS da la expulsión
   instantánea de UX; la verificación en `verificar_token` es el respaldo.
   - Nota multi-worker (Railway): la caché es por proceso; con TTL 30s el peor
     caso entre workers es 30s, y el WS cubre lo instantáneo.

2. **Falla 2 — dispositivo legible + IP real.** Helper
   `_describir_dispositivo(user_agent)` → "📱 Celular Android · Chrome" /
   "💻 Windows · Edge" (parseo de strings, SIN dependencias nuevas). Usar IP real
   vía `X-Forwarded-For` (primer salto) como en `audit_context.py`. Guardar en
   `dispositivo` e `ip` de `SesionUsuario`.

3. **Falla 3 — WebSocket de sesiones.** Nuevo router `app\routers\session_ws.py`
   con endpoint `/ws/sesiones?token=<JWT>` (mismo patrón que `chat_ws.py`):
   - `ConnectionManager` por `usuario_id` → {token_hash: [WebSocket]}.
   - En **login de nuevo dispositivo**: push a las conexiones existentes del
     usuario → `{tipo:"nuevo_dispositivo", dispositivo, ip, ...}`.
   - En **cierre remoto/logout**: push a la conexión de ESA sesión →
     `{tipo:"sesion_cerrada"}` → el front cierra sesión al instante.
   - Manager global en `app\core\session_events.py` para que `auth.py` (login,
     DELETE /sesiones) pueda emitir. Como los endpoints HTTP son `def` (sync) y
     el WS es async: capturar el event loop y usar
     `asyncio.run_coroutine_threadsafe`.
   - Registrar el router en `app\main.py` (junto a `chat_ws_router`, línea ~1788).
   - Arreglar/retirar el `logout-all` roto (agregar endpoint real o quitar la
     llamada del front).

### Frontend (`C:\E-zyro-frontend`)

- `src\app\core\services\auth.service.ts`:
  - Reemplazar `startDevicePolling()` (60s) por conexión **WebSocket** a
    `/ws/sesiones?token=`. Patrón de URL ws/wss: ver componentes de
    `features\operaciones\components\operaciones-detalle` y
    `operaciones-cronograma` (ya usan WebSocket).
  - `nuevo_dispositivo` → mostrar `showNewDeviceWarning` al instante con
    `newDeviceInfo` (dispositivo + IP).
  - `sesion_cerrada` → **logout forzado** (limpiar token, redirigir a `/`,
    detener todo). Esto cierra el "entra y entra".
  - Reconexión con backoff si el WS cae.
  - Arreglar `logoutAllDevices()` (endpoint inexistente).

### Datos de entorno / wiring

- `environment.apiUrl = 'https://e-zyro-production-7f7d.up.railway.app'`
  (de `src\environments\environment.ts`). Derivar WS: `https→wss`.
- Backend: `SessionLocal` en `app\db\database.py` (línea 22). Routers se
  registran en `app\main.py` (~1781-1831). `chat_ws_router` en línea 1788.
- `device_id`: el front genera UUID persistente en localStorage
  (`ezyro_device_id`) y lo manda en login (`login.component.ts` ~línea 45).
  `SesionUsuario.device_id` está indexado; `token_hash` NO (considerar índice).

## 5. Archivos clave (ya leídos)

**Backend**
- `app\core\security.py` — `verificar_token` (NO chequea sesión activa). ← editar
- `app\routers\auth.py` — `/login`, `/logout`, `/refresh` (sí valida BD),
  `/sesiones` GET, `/sesiones/{id}` DELETE. ← editar
- `app\models\sesion_usuario.py` — id, usuario_id, token_hash(255),
  device_id(100, idx), dispositivo(100), ip(45), user_agent(255), activa,
  fecha_expiracion, fecha_cierre, created_at.
- `app\schemas\auth.py` — `LoginData(username, password, device_id?)`.
- `app\routers\chat_ws.py` — patrón ConnectionManager + auth por `?token=`. ← copiar
- `app\core\audit_context.py` (76-80) — extracción de IP real `X-Forwarded-For`.
- `app\db\database.py` — `SessionLocal`. `app\main.py` — include_router.

**Frontend**
- `src\app\core\services\auth.service.ts` — login, logout, polling 60s,
  newDeviceWarning, refresh, timers. ← editar
- `src\app\features\auth\login\login.component.ts` — `getOrCreateDeviceId()`.
- Componentes de `operaciones` con WebSocket (patrón de URL).

## 6. Estado

- [x] Diagnóstico completo (3 fallas identificadas).
- [x] Decisiones confirmadas: solo IP + WebSocket.
- [x] Leídos backend (security, auth, sesion_usuario, schema, chat_ws,
      audit_context, database, main) y frontend (auth.service, environment).
- [x] Creado este MD de contexto.
- [x] Backend: verificar_token con chequeo de sesión + caché TTL.
- [x] Backend: `_describir_dispositivo` + IP real en `/login`.
- [x] Backend: `session_events.py` + `session_ws.py` + registro en main + fix logout-all.
- [x] Frontend: WS de sesiones (aviso instantáneo + logout forzado) + fix logout-all.

## 7. Implementación final (2026-06-17)

### Backend (`C:\E-zyro\BACKEND`) — rama `Backend`

- **`app/core/session_cache.py` (NUEVO).** Caché en memoria por `token_hash`
  con TTL de 30s. `sesion_activa()` (HIT O(1), MISS = 1 consulta a BD por token
  cada 30s), `marcar_activa()` (pre-cachea tras login/refresh), `invalidar()`
  (revoca al instante en logout/cierre). Tope de 100k entradas con poda.
  `fail-open` si la BD falla (no tumba el backend). Pensado para 10k usuarios:
  evita golpear BD en cada request.
- **`app/core/security.py`.** `verificar_token` ahora exige `sesion_activa(...)`;
  el JWT revocado se rechaza aunque no haya expirado → **arregla FALLA 1**.
- **`app/routers/auth.py`.**
  - `_ip_real()` (X-Forwarded-For, primer salto) y `_describir_dispositivo()`
    (📱 Celular / 💻 Computadora · SO · navegador) → **arregla FALLA 2**.
  - `/login`: guarda IP real + dispositivo legible; detecta equipo nuevo (por
    `device_id`); `marcar_activa()`; emite `nuevo_dispositivo` por WS a las
    sesiones ya abiertas (con dispositivo, IP y `sesion_id`).
  - `/logout` y `/refresh`: `invalidar()` del hash viejo + `marcar_activa()` del
    nuevo (rotación de token coherente).
  - `DELETE /sesiones/{id}`: `invalidar()` + `notificar_sesion_cerrada` por WS.
  - **`POST /auth/logout-all` (NUEVO):** cierra todas las demás sesiones, las
    revoca y empuja `sesion_cerrada` a cada equipo → **arregla FALLA 3** (botón).
- **`app/core/session_events.py` (NUEVO).** `SessionEventManager` global
  (usuario_id → token_hash → [WebSocket]). Emisión thread-safe desde endpoints
  síncronos vía `asyncio.run_coroutine_threadsafe` sobre el loop capturado.
- **`app/routers/session_ws.py` (NUEVO).** Endpoint `/ws/sesiones?token=<JWT>`
  (mismo patrón de auth que `chat_ws`).
- **`app/main.py`.** Registro de `session_ws_router` + índice
  `ix_sesion_usuario_token (usuario_id, token_hash)` en `_run_migrations`.

### Frontend (`C:\E-zyro-frontend`) — rama `frontend`

- **`auth.service.ts`.** Eliminado el polling de 60s. Nuevo WebSocket
  `/ws/sesiones` (`connectSessionSocket` / `disconnectSessionSocket`) con
  reconexión por backoff exponencial (techo 30s). `nuevo_dispositivo` →
  aviso instantáneo; `sesion_cerrada` → `forceLogout()`. `logoutAllDevices()`
  apunta a `/auth/logout-all`. `cerrarSesionDesconocida()` usa `sesion_id`.
- **`app.ts`.** `connectSessionSocket()` al iniciar (en vez de polling).

### Notas de escalabilidad / seguridad (10k usuarios)

- La **seguridad de expulsión NO depende del WebSocket**: la garantiza
  `session_cache` + `verificar_token` (funciona cross-worker en ≤30s contra BD
  compartida). El WS es solo la capa de UX instantánea (igual arquitectura que
  `chat_ws`, manager por proceso).
- **Mejora futura opcional:** Redis pub/sub para expulsión/aviso instantáneo
  cross-worker sin cambiar la interfaz de `session_cache` / `session_events`.
