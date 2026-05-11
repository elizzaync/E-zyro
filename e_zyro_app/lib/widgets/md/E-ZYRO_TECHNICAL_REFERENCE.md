# E-ZYRO — Technical Reference

> **Stack**: FastAPI + PostgreSQL (Railway) · Angular 21 · Firebase FCM · Cloudinary · APScheduler · face_recognition  
> **Auth**: JWT (HS256, 480 min) + bcrypt · Route guards · HTTP interceptors  
> **Deployment**: Backend → Railway · Frontend → Angular build

---

## 1. Environment & Configuration

### Backend `.env`
| Variable | Value |
|---|---|
| `SECRET_KEY` | `t0fe2b6288932802ee0c987eb1b48ec97359da9465179703cdf5f3f8f33c5de81` |
| `MAIL_USERNAME` | `arturoh123498@gmail.com` |
| `MAIL_PASSWORD` | `jspvgdhmvrcpposf` |
| `MAIL_FROM` | `arturoh123498@gmail.com` |
| `MAIL_PORT` | `465` |
| `MAIL_SERVER` | `smtp.gmail.com` |
| `API_KEY_CLOUDINARY` | `284215549193443` |
| `API_SECRET_CLOUDINARY` | `J3UGYsVTi9Y_j_OrnPjNgaAcZXU` |
| `CLOUD_NAME_CLOUDINARY` | `dovajxkib` |

### Frontend Environments
| Key | Production | Development |
|---|---|---|
| `apiUrl` | `https://e-zyro-production.up.railway.app` | `http://localhost:8080` |
| Firebase projectId | `e-system-tic` | same |
| `messagingSenderId` | `603001313879` | same |
| `vapidKey` | `BLbX7UlEoor20ch...` | same |

---

## 2. Backend — File Map

```
BACKEND/app/
├── main.py              # FastAPI app, CORS, lifespan (scheduler init)
├── db/database.py       # SQLAlchemy, PostgreSQL, get_db() dependency
├── core/
│   ├── security.py      # JWT create/verify, bcrypt
│   ├── email.py         # OTP email via Google Apps Script relay
│   └── config_cloudinary.py
├── models/              # 27 SQLAlchemy ORM models
├── schemas/auth.py      # Pydantic schemas
├── routers/
│   ├── auth.py          # /auth/*
│   ├── dashboard.py     # /dashboard/*
│   ├── tareas.py        # /tareas/*
│   ├── endpoint.py      # /verificar-asistencia
│   └── asistencia.py
└── services/
    ├── fcm_service.py   # Firebase push notifications
    ├── cloudinary_service.py
    └── scheduler_service.py  # APScheduler, 8 AM daily reminders
```

---

## 3. Database Models (SQLAlchemy)

### Identity & Auth
| Model | Key Fields |
|---|---|
| `Empresa` | `id` UUID, `razon_social`, `ruc`, `email_contacto`, `slug`, `estado`, `fecha_registro` |
| `Usuario` | `id` UUID, `empresa_id`→Empresa, `nombre`, `apellido`, `username`, `email`, `password_hash`, `telefono`, `foto_url`, `activo`, `email_verificado`, `ultimo_acceso` · Unique: (empresa_id, email), (empresa_id, username) |
| `Empleado` | `id` UUID, `usuario_id`→Usuario, `empresa_id`→Empresa, `cargo`, `tipo`, `fecha_ingreso` |
| `Cliente` | `id` UUID, `empresa_id`→Empresa, `razon_social`, `ruc`, `activo` |
| `SesionUsuario` | `id`, `usuario_id`, `token_hash`, `dispositivo`, `ip`, `user_agent`, `activa`, `fecha_expiracion`, `fecha_cierre` |
| `RecuperacionPassword` | `id`, `usuario_id`, `codigo_hash`, `intentos_fallidos`, `usado`, `ip_solicitud`, `fecha_expiracion` |

### RBAC
| Model | Key Fields |
|---|---|
| `Rol` | `id`, `empresa_id`, `nombre`, `descripcion`, `es_rol_sistema` |
| `Permiso` | `id`, `modulo`, `accion`, `descripcion` |
| `RolPermiso` | `rol_id`→Rol, `permiso_id`→Permiso |
| `UsuarioRol` | `id`, `usuario_id`→Usuario, `rol_id`→Rol, `empresa_id`, `asignado_por` |
| `UsuarioPermiso` | `usuario_id`, `permiso_id`, `asignado_por` |

### Projects & Services
| Model | Key Fields |
|---|---|
| `Proyecto` | `id`, `empresa_id`, `cliente_id`, `contrato_comercial_id`, `orden_trabajo`, `jefe_operaciones_id`→Empleado, `nombre_proyecto`, `estado` [Pendiente\|En_Proceso\|Completado], `fecha_inicio`, `fecha_fin_estimada`, `fecha_fin_real` |
| `ProyectoDetalle` | `proyecto_id` (1:1 PK→FK), `zona_ejecucion`, `alcance`, `orden_compra_cliente`, `tipo_documento_cliente`, `nro_documento`, `nro_conformidad`, `acta_url`, `public_id_cloudinary` |
| `ProyectoMiembro` | `id`, `proyecto_id`, `empleado_id`, `rol_proyecto`, `fecha_asignacion`, `activo` · Unique(proyecto_id, empleado_id) |
| `CatalogoServicio` | `id`, `empresa_id`, `tipo_trabajo`, `nombre`, `descripcion`, `activo` |
| `ProyectoServicio` | `id`, `proyecto_id`, `empresa_id`, `catalogo_servicio_id`, `fase_id`, `nombre`, `descripcion`, `responsable_id`→Empleado, `orden`, `estado` [Pendiente\|En_Proceso\|Completado], `fecha_programada`, `fecha_inicio`, `fecha_fin` |

### HR & Documents
| Model | Key Fields |
|---|---|
| `Contrato` | `id`, `empleado_id`, `empresa_id`, `tipo`, `fecha_inicio`, `fecha_fin`, `estado` [vigente\|vencido\|rescindido\|renovado], `documento_url`, `public_id_cloudinary` |
| `DocumentoLaboral` | `id`, `empleado_id`, `empresa_id`, `tipo`, `nombre`, `url_archivo`, `public_id_cloudinary`, `fecha_emision` |
| `SolicitudLaboral` | `id`, `empleado_id`, `empresa_id`, `tipo`, `estado` [pendiente\|aprobada\|rechazada\|anulada], `descripcion`, `fecha_inicio`, `fecha_fin`, `aprobado_por`, `observacion` |
| `RegistroAsistencia` | `id`, `empresa_id`, `empleado_id`, `proyecto_id`, `proyecto_servicio_id`, `tipo`, `fecha_hora`, `estado`, `observacion`, `validado_por` |

### Skills
| Model | Key Fields |
|---|---|
| `CategoriaHabilidad` | `id`, `nombre`, `descripcion` |
| `Habilidad` | `id`, `categoria_id`→CategoriaHabilidad, `nombre`, `descripcion` |
| `EmpleadoHabilidad` | `id`, `empleado_id`, `habilidad_id`, `nivel` [basico\|intermedio\|avanzado\|experto], `certificado_url`, `verificado`, `verificado_por`→Empleado, `fecha_verificacion` |

### Notifications & Audit
| Model | Key Fields |
|---|---|
| `DispositivoPush` | `id`, `usuario_id`, `token_push`, `plataforma`, `activo` |
| `Notificacion` | `id`, `empresa_id`, `usuario_id`, `tipo`, `categoria`, `titulo`, `mensaje`, `leido`, `enviado`, `fecha_envio`, `referencia_tabla`, `referencia_id` |
| `Auditoria` | `id`, `empresa_id`, `usuario_id`, `tabla_afectada`, `registro_id`, `accion`, `modulo`, `datos_anteriores`, `datos_nuevos`, `ip`, `user_agent`, `descripcion`, `fecha` |
| `OrdenMantenimiento` | `id`, `equipo_id`, `empresa_id`, `tecnico_id`→Empleado, `tipo`, `estado`, `fecha` |

---

## 4. API Endpoints

### Auth — `/auth`

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/login` | — | Login con username+password. Retorna JWT, nombre, rol. Crea SesionUsuario. |
| POST | `/auth/logout` | Bearer | Cierra sesión activa (SesionUsuario.activa=False). |
| POST | `/auth/password-recovery/request` | — | Genera OTP 6 dígitos, hashea con bcrypt, expira en 15 min, envía por email. |
| POST | `/auth/password-recovery/verify` | — | Valida OTP. Max 3 intentos. Bloquea si excede. |
| POST | `/auth/password-recovery/reset` | — | Aplica nueva contraseña si OTP válido. Marca recovery como usado. |

**Schemas de entrada:**
```python
LoginData              { username: str, password: str }
PasswordResetRequest   { email: EmailStr }
PasswordVerifyCode     { email: EmailStr, code: str(len=6) }
PasswordResetConfirm   { email: EmailStr, code: str(len=6), new_password: str(min=6) }
```

---

### Dashboard — `/dashboard`

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/dashboard/resumen` | Bearer | KPIs: {activos, pendientes, completados} por proyecto/rol |
| GET | `/dashboard/proximos-servicios` | Bearer | Top 3 servicios próximos con empresa, tipo, fecha, estado |
| GET | `/dashboard/rendimiento-mensual` | Bearer | {mesActual, semanas[], stats{tasaExito, totalServicios, esteMes}} |
| GET | `/dashboard/calendario` | Bearer | {proximosEventos[], notas{}, diasConServicio[]} |
| POST | `/dashboard/calendario/nota` | Bearer | Crear/editar/eliminar nota en Notificacion. Envía push si es hoy/mañana. |
| GET | `/dashboard/calendario/servicio/{fecha}` | Bearer | Detalle del servicio en una fecha dada. |
| POST | `/dashboard/proyectos/asignar-tecnico` | Bearer | Crea ProyectoMiembro + push notification al técnico. |
| GET | `/dashboard/notificaciones` | Bearer | Notificaciones no leídas con tiempo relativo. |
| PUT | `/dashboard/notificaciones/{id}/ignorar` | Bearer | Marca Notificacion.leido=True. |
| POST | `/dashboard/guardar-token-push` | Bearer | Upsert DispositivoPush (token FCM). |
| GET | `/dashboard/perfil` | Bearer | {personal{id,nombre,apellido,correo,tel,foto,rol,fechaCreacion,permisos_modulo[]}, empresa{id,nombre,ruc,ubicacion}} |
| PUT | `/dashboard/perfil` | Bearer | Actualiza nombre/apellido/teléfono. Sube foto a Cloudinary (face-crop 400x400). Emite perfilActualizado$. |
| GET | `/dashboard/perfil/capacitaciones` | Bearer | EmpleadoHabilidad + Habilidad + CategoriaHabilidad |
| GET | `/dashboard/perfil/actividad` | Bearer | Últimas 15 Auditoria (excluye tablas sensibles + LOGIN/LOGOUT) |
| GET | `/dashboard/perfil/estadisticas` | Bearer | {servicios_completados, asistencias_mes, solicitudes_pendientes, tiempo_promedio} |
| GET | `/dashboard/perfil/asistencia` | Bearer | Últimos 30 días de RegistroAsistencia agrupados por día + resumen |
| GET | `/dashboard/perfil/contratos` | Bearer | Todos los Contrato del empleado |
| GET | `/dashboard/perfil/boletas` | Bearer | Todos los DocumentoLaboral del empleado |
| GET | `/dashboard/perfil/permisos` | Bearer | Todas las SolicitudLaboral del empleado |

**Schemas de entrada (dashboard):**
```python
NotaCalendario   { fecha: str, texto: str }
PerfilUpdate     { nombre, apellido, telefono, fotoBase64?: str }
TokenPush        { token: str, plataforma: str = "web" }
AsignacionMiembro{ proyecto_id, empleado_id, rol_proyecto? }
```

---

### Otros

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/tareas/mis-tareas` | Bearer | Placeholder — retorna empresa_id + usuario_id del token |
| POST | `/verificar-asistencia` | — | Reconocimiento facial (face_recognition, umbral 0.42, jitter=5). Input: {imagen_base, imagen_selfie, metadata}. Output: {status, score, motivo, timestamp} |
| GET | `/` | — | Health check |

---

## 5. Core Services (Backend)

### `security.py`
```python
crear_token_acceso(data: dict) → str
  # Algorithm: HS256 | Expiry: 480 min | Payload: {id, empresa_id, exp, rol}

verificar_token(credentials: HTTPAuthorizationCredentials) → dict
  # HTTPBearer scheme | raises HTTPException 401 on invalid
```

### `email.py`
```python
enviar_correo_otp(email_destino: str, codigo_otp: str) → None  # async
  # Relay: Google Apps Script webhook (bypasses SMTP firewall)
  # Template: HTML con OTP destacado
```

### `cloudinary_service.py`
```python
subir_imagen_cloudinary(base64_data, folder, public_id, is_perfil=False) → str
  # Formats: f_auto, q_auto:good
  # is_perfil=True: crop=thumb, gravity=face, 400x400
  # Returns: secure_url

eliminar_imagen_cloudinary(url: str) → None
  # Extrae public_id de la URL y elimina en Cloudinary
```

### `fcm_service.py`
```python
enviar_push_a_usuario(usuario_id, titulo, mensaje, db) → bool
  # Consulta DispositivoPush activos del usuario
  # Maneja UnregisteredError → marca token inactivo
  # Returns True si al menos 1 push enviado

notificar_asignacion_servicio(usuario_id, nombre_tecnico, nombre_servicio, nombre_cliente, fecha, db)
  # Título: "🔧 Nuevo Servicio Asignado"

notificar_recordatorio_calendario(usuario_id, texto_nota, cuando, db)
  # Título: "📅 Recordatorio de Calendario"
```

### `scheduler_service.py`
```python
iniciar_scheduler()  # Llamado en lifespan startup
  # Cron: 8:00 AM America/Lima, diario
  # Job: _enviar_recordatorios_calendario()
  #   → Consulta Notificacion(categoria='Nota Calendario', leido=False, enviado=False)
  #   → Filtra fecha_envio = hoy o mañana
  #   → Envía push + marca enviado=True

detener_scheduler()  # Llamado en lifespan shutdown
```

---

## 6. Frontend — File Map

```
FRONTEND/src/app/
├── app.ts                    # Root component, hides navbar en login pages
├── app.routes.ts             # 5 rutas
├── core/
│   ├── services/
│   │   ├── auth.service.ts
│   │   ├── dashboard.service.ts
│   │   ├── fcm.service.ts
│   │   └── toast.service.ts
│   ├── guards/auth.guards.ts
│   └── interceptors/auth.interceptor.ts
├── features/
│   ├── auth/
│   │   ├── login/login.component.ts
│   │   └── reset-password/reset-password.component.ts
│   ├── home/
│   │   ├── home.component.ts
│   │   └── components/
│   │       ├── summary-card/
│   │       ├── calendar-widget/
│   │       ├── upcoming-services-widget/
│   │       ├── monthly-summary-widget/
│   │       └── quick-actions-widget/
│   ├── personal/
│   │   ├── personal.component.ts
│   │   └── components/
│   │       ├── profile-banner/
│   │       ├── profile-cards/
│   │       ├── profile-certifications/
│   │       ├── profile-contact/
│   │       ├── profile-documents/
│   │       ├── profile-attendance-list/
│   │       └── profile-recent-activity/
│   └── permisos/permisos.component.ts
└── shared/components/
    ├── navbar/navbar.component.ts
    ├── toast/toast.component.ts
    ├── alert/, spinner/, password-strength/, success-checkmark/
    └── login/alert.component.ts
```

---

## 7. Routes (Angular)

```typescript
/ → LoginComponent
/reset-password → ResetPasswordComponent
/home → HomeComponent [authGuard]
/personal → PersonalComponent [authGuard]
/permisos → PermisosComponent [authGuard]
** → redirect to /
```

---

## 8. Core Services (Frontend)

### `auth.service.ts`
```typescript
login(credentials)                                  // POST /auth/login → stores token+user in localStorage
solicitarCodigoRecuperacion(email)                  // POST /auth/password-recovery/request
verificarCodigo(email, code)                        // POST /auth/password-recovery/verify
actualizarPassword(email, code, newPassword)        // POST /auth/password-recovery/reset
logout()                                            // POST /auth/logout → limpia localStorage → navega /
isAuthenticated(): boolean                          // !!localStorage['ezyro_token']
getToken(): string | null
```

### `dashboard.service.ts`
```typescript
// Subjects reactivos
perfilActualizado$: Subject<void>
notificaciones$: BehaviorSubject<any[]>
refreshWidgets$: BehaviorSubject<boolean>

// KPIs
getResumenKPIs()          // GET /dashboard/resumen
getProximosServicios()    // GET /dashboard/proximos-servicios
getRendimientoMensual()   // GET /dashboard/rendimiento-mensual
getCalendarioEventos()    // GET /dashboard/calendario

// Calendar
guardarNotaCalendario(fecha, texto)      // POST /dashboard/calendario/nota
getDetalleServicioDia(fecha)             // GET /dashboard/calendario/servicio/{fecha}

// Profile
getPerfilUsuario()         // GET /dashboard/perfil
actualizarPerfil(datos)    // PUT /dashboard/perfil
getCapacitaciones()        // GET /dashboard/perfil/capacitaciones
getActividadReciente()     // GET /dashboard/perfil/actividad
getPerfilEstadisticas()    // GET /dashboard/perfil/estadisticas
getAsistencia()            // GET /dashboard/perfil/asistencia
getContratos()             // GET /dashboard/perfil/contratos
getBoletas()               // GET /dashboard/perfil/boletas
getPermisos()              // GET /dashboard/perfil/permisos

// Notifications
getNotificaciones()             // GET /dashboard/notificaciones
ignorarNotificacion(id)         // PUT /dashboard/notificaciones/{id}/ignorar

// FCM
guardarTokenPush(token)         // POST /dashboard/guardar-token-push
```

### `fcm.service.ts`
```typescript
// Constructor: init Firebase Messaging → request permission
// → getToken(messaging, {vapidKey}) → guardarTokenPush()
// → onMessage(): toast + native notif + refreshWidgets$.next(true)
```

### `toast.service.ts`
```typescript
mostrar(mensaje: string, tipo: 'success'|'error'|'info'): void
toast$: Observable<{mensaje, tipo}>  // consumed by ToastComponent
```

---

## 9. Guards & Interceptors

### `auth.guards.ts`
```typescript
authGuard: CanActivateFn
// authService.isAuthenticated() → true: allow | false: redirect /
```

### `auth.interceptor.ts`
```typescript
authInterceptor: HttpInterceptorFn
// Inyecta: 'Authorization': `Bearer ${token}` en todas las requests
// Skip: si no hay token
```

---

## 10. Component Reference

| Component | Route/Parent | Key Behavior |
|---|---|---|
| `LoginComponent` | `/` | ReactiveForm, signals (showPassword, isAuthenticating). Login → 1.5s → env prep → navigate /home |
| `ResetPasswordComponent` | `/reset-password` | 4 pasos: EMAIL→CODE→PASSWORD→SUCCESS. Auto-submit en 6 dígitos. Redirect 3s. |
| `HomeComponent` | `/home` | KPIs, greeting (time-based), weather (Open-Meteo). IntersectionObserver para animaciones. |
| `SummaryCardComponent` | Home | @Input: titulo, valor, icono, tema, subtitulo |
| `CalendarWidgetComponent` | Home | Grid mensual. Modal nota (crear/editar/borrar). Modal servicio (detalles). Push integration. |
| `UpcomingServicesWidgetComponent` | Home | Top 3 servicios próximos |
| `MonthlySummaryWidgetComponent` | Home | Rendimiento semanal + tasas de éxito |
| `QuickActionsWidgetComponent` | Home | Shortcuts de navegación |
| `PersonalComponent` | `/personal` | Tabs: perfil, capacitaciones, actividad, documentos, asistencia, permisos. Suscribe a perfilActualizado$. |
| `ProfileBannerComponent` | Personal | @Input: perfil → avatar, nombre, rol, cargo, fecha ingreso |
| `ProfileCardsComponent` | Personal | 4 stat-cards: servicios completados, asistencias, solicitudes pendientes, tiempo promedio sesión |
| `ProfileCertificationsComponent` | Personal | Lista habilidades con nivel (básico/intermedio/avanzado/experto) |
| `ProfileRecentActivityComponent` | Personal | Últimas 15 acciones de auditoría con iconos y tiempo relativo |
| `ProfileContactComponent` | Personal | Sub-tabs: datos personales, documentos, asistencia |
| `ProfileDocumentsComponent` | Personal | forkJoin(boletas, contratos, permisos). Filter por tipo. Abre URL en nueva pestaña. |
| `ProfileAttendanceListComponent` | Personal | @Input registros. Últimos 30 días, resalta turno activo. |
| `PermisosComponent` | `/permisos` | Form solicitud laboral. Tabs: solicitar, historial. |
| `NavbarComponent` | App root | Avatar, nombre, rol. Modal perfil (editar+foto). Panel notificaciones. Toggle dark/light. Logout. |
| `ToastComponent` | App root | toast$. Auto-hide 3.5s. Signal: visible, mensaje, tipo. |

---

## 11. State Management & Caching

### LocalStorage Keys
| Key | Content |
|---|---|
| `ezyro_token` | JWT access token |
| `ezyro_user` | Perfil del usuario serializado (fast cache) |
| `ezyro_permisos` | Array de módulos con permisos |
| `ezyro_tema` | `'light'` \| `'dark'` |

### Reactive State
```typescript
perfilActualizado$: Subject<void>        // Dispara cuando se actualiza perfil → Navbar + HomeComponent actualizan nombre
notificaciones$: BehaviorSubject<any[]>  // Navbar consume en tiempo real
refreshWidgets$: BehaviorSubject<bool>   // FCM onMessage() → todos los widgets re-fetch
```

### Estrategia de Caché
1. **Fast path**: Leer localStorage inmediatamente (render instantáneo)
2. **Async refresh**: API call en background → actualizar vista
3. **Invalidación**: `refreshWidgets$.next(true)` en push notification o acción del usuario

---

## 12. Key Flows

### Login
```
LoginComponent → authService.login() → POST /auth/login
→ Backend: bcrypt.verify + JWT.create + SesionUsuario.insert + Auditoria.insert
→ localStorage[token, user] → navigate /home → authGuard ✓
```

### Password Recovery
```
Step 1: email → POST /auth/password-recovery/request
  → OTP=secrets.randbelow(10^6) → bcrypt(OTP) → RecuperacionPassword(expiry=15min) → email

Step 2: code → POST /auth/password-recovery/verify
  → bcrypt.verify(code, hash) · max 3 intentos · check expiry → ok

Step 3: new_password → POST /auth/password-recovery/reset
  → re-verify code → bcrypt(new_password) → Usuario.password_hash update → recovery.usado=True

Step 4: SUCCESS → redirect / after 3s
```

### FCM Push
```
Backend: enviar_push_a_usuario() → firebase_admin.messaging.send(token)
Frontend: FcmService.onMessage()
  → ToastService.mostrar() + new Notification() via ServiceWorker
  → refreshWidgets$.next(true) → Components re-fetch data
```

### Profile Update with Photo
```
NavbarComponent: actualizarPerfil({fotoBase64, ...})
  → PUT /dashboard/perfil
  → Backend: Cloudinary.upload(base64, folder, public_id, is_perfil=True)
     → crop=thumb, gravity=face, 400x400, f_auto, q_auto:good
  → Backend: Cloudinary.delete(old_url) if exists
  → Return {foto_url}
  → perfilActualizado$.next() → HomeComponent + NavbarComponent update
```

### Calendar Note + Push
```
CalendarWidgetComponent: guardarNotaCalendario(fecha, texto)
  → POST /dashboard/calendario/nota
  → Backend: Upsert Notificacion(categoria='Nota Calendario', enviado=False)
  → If fecha = hoy|mañana: enviar_push_a_usuario() inmediatamente
  → Scheduler (8AM): re-envía las pendientes con enviado=False
```

### Facial Attendance
```
POST /verificar-asistencia
  Input: {imagen_base: base64, imagen_selfie: base64, metadata}
  → face_recognition.face_encodings(img, num_jitters=5)
  → face_recognition.face_distance(encoding_base, encoding_selfie)
  → score = (1 - distance) * 100
  → aprobado = score >= 0.42 (umbral)
  Output: {status, score, motivo, timestamp, metadata}
```

---

## 13. Pydantic Schemas Quick Reference

```python
# auth.py
LoginData(username, password)
PasswordResetRequest(email: EmailStr)
PasswordVerifyCode(email: EmailStr, code: str[6])
PasswordResetConfirm(email: EmailStr, code: str[6], new_password: str[min=6])

# dashboard.py (inline)
NotaCalendario(fecha: str, texto: str)
PerfilUpdate(nombre, apellido, telefono, fotoBase64: Optional[str])
TokenPush(token: str, plataforma: str = "web")
AsignacionMiembro(proyecto_id, empleado_id, rol_proyecto: Optional[str])

# endpoint.py
SolicitudVerificacion(imagen_base: str, imagen_selfie: str, metadata: dict)
RespuestaVerificacion(status: str, score: float, motivo: str, timestamp: str, metadata: dict)
```

---

## 14. Angular Signals Pattern (Components)

```typescript
// Angular 17+ Signals used throughout components
showPassword = signal(false)
isAuthenticating = signal(false)
errorMessage = signal('')
currentStep = signal<'EMAIL'|'CODE'|'PASSWORD'|'SUCCESS'>('EMAIL')
codeStatus = signal<'idle'|'loading'|'success'|'error'>('idle')

// Usage in template: {{ showPassword() }}
// Mutation: showPassword.set(true) | showPassword.update(v => !v)
```

---

## 15. HTTP Headers Pattern

```typescript
// DashboardService — todas las peticiones autenticadas
private getHeaders() {
  return {
    'Authorization': `Bearer ${localStorage.getItem('ezyro_token')}`,
    'Content-Type': 'application/json'
  }
}

// AuthInterceptor — inyección automática en todas las requests
authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(AuthService).getToken()
  if (!token) return next(req)
  return next(req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }))
}
```

---

## 16. Technology Stack Summary

### Backend
| Layer | Technology |
|---|---|
| Framework | FastAPI (Python 3.x) |
| ORM | SQLAlchemy + psycopg2-binary |
| Database | PostgreSQL (Railway) |
| Auth | JWT (python-jose) + bcrypt (passlib) |
| Email | Google Apps Script relay |
| Push | Firebase Admin SDK (FCM) |
| Media | Cloudinary (upload, transform, face-crop) |
| Background | APScheduler (cron, 8AM Lima) |
| Biometrics | face_recognition (dlib encodings) |

### Frontend
| Layer | Technology |
|---|---|
| Framework | Angular 21 (standalone components) |
| State | Angular Signals + RxJS (Subject, BehaviorSubject) |
| HTTP | HttpClient + interceptors |
| Forms | ReactiveFormsModule |
| Auth | CanActivateFn guards |
| Push | Firebase Cloud Messaging (AngularFire) |
| Cache | localStorage |
| Weather | Open-Meteo API (no key required) |
| Styles | Custom CSS (no UI framework) |

---

*Last updated: 2026-05-07 — E-ZYRO project snapshot*
