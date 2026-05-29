# Plan de Migración ERP → e-zyro (puntero)

> **La fuente de verdad del plan vive en el repo backend:**
> `e-zyro-backend/BACKEND/docs/plan-migracion-erp/`
>
> Este archivo es solo un puntero para el equipo móvil (la app y el backend son ramas distintas
> del mismo remoto `elizzaync/E-zyro.git`, por eso el plan completo no aparece en esta rama).

## Documentos del plan (en el repo backend)
- `README.md` — índice general.
- `00-MASTER-PLAN.md` — fases, **orden de implementación**, dependencias, Definition of Done.
- `01-CONVENCIONES.md` — **sección B = convenciones Flutter** (dónde va cada pantalla/servicio/model, navegación, offline-first).
- `02-CLOUDINARY-Y-GALERIA.md` — taxonomía de carpetas + Galería Global (incluye `pantalla_galeria.dart`).
- `03-EPP.md` · `04-…CORRECTIVOS…` · `05-…ITSE` · `06-CALIBRACIONES…` — subplanes (cada uno tiene su sección "App móvil").
- `07-ORQUESTACION-AGENTES.md` — pipeline y plantilla de prompt del Mobile Senior.
- `08-PROGRESO.md` — tracker vivo.
- `09-BITACORA-ERRORES.md` — registro de errores.

## Resumen de trabajo móvil por fase
| Fase | Pantallas/Servicios nuevos en `e_zyro_app/lib` | Enganche de navegación |
|------|-----------------------------------------------|------------------------|
| 1 | `pantalla_galeria.dart`, `galeria_service.dart`, `galeria_models.dart` | `_MenuItem` en `pantalla_mas.dart` + accesos contextuales |
| 2 | `pantalla_epp*.dart`, `epp_service.dart`, `epp_models.dart` | sección EPP en `pantalla_logistica.dart` |
| 3 | `pantalla_calibraciones.dart` + estado operativo, `calibracion_service.dart` | dentro de `pantalla_mantenimientos.dart`/`pantalla_equipos.dart` |
| 4 | `pantalla_correctivos.dart` + observaciones, `correctivo_service.dart` | dentro de `pantalla_detalle_servicio.dart` |
| 5 | `pantalla_itse*.dart`, `itse_service.dart`, `itse_models.dart` | `pantalla_operaciones.dart` + "Más" |

> Reglas Flutter completas en `01-CONVENCIONES.md` (sección B). No empezar una pantalla hasta que su API backend esté estable y el backend arranque limpio.
