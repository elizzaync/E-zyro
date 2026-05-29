# 10 · Integración y pruebas (qué pasa con los `feat/*` y cómo lo pruebas)

> Responde: ¿qué hago con las ramas de feature?, ¿cómo las subo a las ramas originales?,
> ¿qué deben cumplir?, y ¿cómo lo pruebo?

## Mapa de ramas (verificado)
| Repo | Rama de integración (deploy/build) | Notas |
|------|-----------------------------------|-------|
| Backend | **`Backend`** | Railway despliega desde aquí → `https://e-zyro-production-7f7d.up.railway.app`. `main` está obsoleta (1 commit). |
| App | **`e-zyro-app`** | de aquí se compila el APK. |
| Web | `frontend` / `loginWeb` | fuera de alcance de este plan. |

Trabajo en ramas `feat/*` por módulo y se integran por **Pull Request** a la rama base correspondiente.

## Ciclo de vida de una rama `feat/*`
```
feat/backend-*  ──PR──►  Backend     ──(Railway auto-deploy)──►  producción backend
feat/app-*      ──PR──►  e-zyro-app  ──(flutter build apk)────►  APK para probar
```

## Qué debe CUMPLIR una rama para mergear (Definition of Done de integración)
**Backend (`feat/backend-*` → `Backend`):**
- [ ] Migraciones idempotentes verificadas contra la BD real (Railway) — aplican 2× sin error.
- [ ] `py_compile` OK + importación de los módulos nuevos OK.
- [ ] e2e de los endpoints nuevos (TestClient contra Railway) en verde.
- [ ] Sin secretos en el diff. `empresa_id` NOT NULL + filtrado por empresa del token en todo endpoint.
- [ ] `/code-review` sin hallazgos altos abiertos.
- [ ] PR revisado y aprobado por ti.

**App (`feat/app-*` → `e-zyro-app`):**
- [ ] `flutter analyze` sin issues.
- [ ] Construye: `flutter build apk --debug` (o `--release`) sin errores.
- [ ] Contratos (`fromJson`) alineados con el `*Out` del backend ya desplegado.
- [ ] PR revisado y aprobado por ti.

## Orden OBLIGATORIO para poder probar
La app apunta a **producción**, así que **el backend va primero**:
1. **Merge backend** `feat/backend-fase0-catalogos-rbac` → `Backend`.
2. **Railway redepliega** automáticamente. El `lifespan` corre las migraciones (idempotentes; el esquema ya está aplicado en la BD → son no-ops). Healthcheck `/` debe responder.
3. **Verifica el backend en producción** (sin app):
   - `GET /docs` muestra los routers `catalogos` y `galeria`.
   - Con token válido: `GET /galeria` → 200; `GET /catalogos/ubicaciones` → 200.
4. **Merge app** `feat/app-fase1-galeria` → `e-zyro-app`.
5. **Compila el APK** desde `e-zyro-app` e instálalo.
6. **Prueba funcional**: *Más → Recursos → Galería* (ver grid, subir foto desde cámara/galería, abrir a pantalla completa, borrar).

> Si prefieres no tocar `e-zyro-app` aún: compila el APK directamente desde `feat/app-fase1-galeria` y pruébalo contra el backend ya desplegado; mergeas a `e-zyro-app` recién cuando estés conforme.

## Smoke-test extra por el refactor de Cloudinary (1.1)
El refactor cambió la carpeta destino de **subidas nuevas** a la raíz única `e-zyro/{empresa_id}/...`. Las URLs ya guardadas NO cambian. Tras desplegar, verifica que siguen funcionando:
- Foto de perfil (editar perfil), firma de permisos, foto de asistencia/selfie, foto biométrica, evidencias de servicio y de mantenimiento.
  (Solo cambia **dónde** se guardan las nuevas; la app las lee por la URL devuelta, así que no debería notarse salvo orden en Cloudinary.)

## Cómo creo los PRs (cuando me lo pidas)
```
gh pr create --base Backend     --head feat/backend-fase0-catalogos-rbac --title "Fase 0+1 backend: catálogos, RBAC, Cloudinary unificado + Galería" --body "..."
gh pr create --base e-zyro-app  --head feat/app-fase1-galeria             --title "Fase 1.6: capa Flutter Galería Global" --body "..."
```

## Rollback
- Backend: si un deploy falla el healthcheck, Railway reintenta (`restartPolicyMaxRetries=3`) y se puede revertir el merge (las migraciones son aditivas; no borran datos).
- App: el APK anterior sigue siendo válido (el backend es retrocompatible: solo agrega endpoints).

## Multiempresa (decisión de diseño confirmada)
Todas las tablas de negocio llevan **`empresa_id` NOT NULL**; los endpoints filtran por la empresa del token. Hoy el tenant por defecto es la **empresa de sistema (E-system)**; a futuro entran otras empresas sin cambios de esquema. Única excepción: la tabla **`permiso`** es un catálogo GLOBAL de tipos `(modulo, accion)` (sin `empresa_id`); lo que es por-empresa son los **roles** y su asignación. Detalle en `01-CONVENCIONES.md`.
