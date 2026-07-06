# Cambios de backend del 2026-07-06 — impacto en la app móvil

> Continuación de `CAMBIOS-BACKEND-2026-07-05-PARA-MOVIL.md`. Igual que la vez pasada:
> **no se tocó ni una línea de Flutter** y ningún endpoint que consume la app cambió su
> contrato. Este documento existe para que sepas qué hay de nuevo del lado servidor y
> qué mejoras opcionales podrías hacer en la app.

## Qué se implementó en el backend (contexto)

Se agregó a Gestión de TIC (web) un sistema de **auditoría de eventos + monitoreo de
seguridad + archivo centralizado de documentos**:

- Tabla `audit_log`: ahora se registran logins exitosos y **fallidos**, logout, accesos
  denegados (403), descargas y exportaciones — de web Y de la app móvil (automático,
  vía middleware; la app no tiene que hacer nada).
- Motor de alertas de seguridad cada 5 min (fuerza bruta, fallos repetidos, descargas
  masivas) que notifica al rol **Soporte** por el mismo FCM de siempre.
- Registro central de documentos en Cloudinary con deduplicación por hash.
- Pantallas web nuevas (solo Soporte/TI): Monitoreo de Seguridad, Auditoría de Eventos,
  Documentos.

## Lo que SÍ te toca saber (3 puntos)

### 1. `/auth/login` ahora puede devolver HTTP 429 (rate limit)

Si una misma IP hace **más de 10 intentos de login por minuto**, el backend responde:

```
HTTP 429
{"detail": "Demasiados intentos de inicio de sesión. Espera un momento e inténtalo de nuevo."}
```

- En uso normal nunca se alcanza (10/min por IP es holgado).
- Escenario real posible: muchos usuarios detrás del mismo NAT corporativo entrando a
  la misma hora, o alguien reintentando en loop tras un error.
- **Mejora sugerida (opcional):** en el manejo de errores del login, capturar el status
  429 y mostrar un mensaje tipo "Demasiados intentos, espera un minuto" en vez del
  error genérico. La app NO crashea sin esto — solo muestra un mensaje menos claro.

### 2. Dos categorías nuevas de notificación push: `"seguridad"` y `"backups"`

Los usuarios con rol **Soporte** ahora reciben push FCM con estas categorías:

| categoria    | cuándo llega                                                    | tipo      |
|--------------|-----------------------------------------------------------------|-----------|
| `backups`    | backup diario/semanal/manual completado, o CUALQUIER backup fallido | info / warning |
| `seguridad`  | alerta de seguridad (fuerza bruta, fallos repetidos, descarga masiva, accesos denegados repetidos) | warning |

- Llegan por el mismo mecanismo de siempre (`enviar_push_a_usuario`, payload igual:
  titulo, mensaje, tipo, categoria, referencia_tabla).
- Se muestran como cualquier notificación — **no rompen nada**.
- **Mejoras sugeridas (opcionales):**
  - Si la app tiene pantalla de preferencias por categoría, registrar `backups` y
    `seguridad` para que el usuario Soporte pueda silenciarlas/activarlas.
  - Si la app hace deep-link al tocar una notificación según categoría, estas dos no
    tienen pantalla destino en el móvil (son de gestión web): basta con abrir el centro
    de notificaciones como fallback.
  - El campo `referencia_tabla` trae claves tipo `backup:{job_id}:ok:{empresa_id}` o
    `seguridad:{alerta_id}:{empresa_id}` — es solo idempotencia del backend, no hace
    falta parsearlo.

### 3. La app queda auditada automáticamente (nada que hacer)

Todo lo que la app ya hace (login, logout, 403 por permisos, descargas de PDF) ahora
queda en `audit_log` con IP y user-agent. Es transparente: cero cambios de contrato,
cero campos nuevos requeridos. Solo tenlo presente al depurar: si Soporte ve eventos
"raros" en el panel, pueden venir de pruebas con la app.

## Endpoints nuevos (por si algún día los quieres consumir — hoy son solo web)

Todos exigen rol Soporte/TI (403 para el resto):

- `GET /seguridad-tic/metricas` · `GET /seguridad-tic/eventos` · `GET /seguridad-tic/alertas`
- `POST /seguridad-tic/alertas/{id}/revisar`
- `GET /audit-log` · `GET /audit-log/export` (CSV)
- `GET /documentos`

## Recordatorio del 2026-07-05 (sigue vigente)

- Módulo Backups en Gestión TIC (web): los backups de BD ahora se descargan como
  `.sql` plano y la programación es configurable desde la pantalla.
- Préstamos también visible en web Logística; firma digital global reutilizable.
- El flujo borrador de préstamo en la app aún no descuenta `stock_minimo` de la
  disponibilidad (pendiente conocido).
