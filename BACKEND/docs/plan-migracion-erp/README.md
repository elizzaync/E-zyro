# Plan de Migración ERP → e-zyro (App móvil + Backend)

> **Fuente de verdad** de la planificación. Todos trabajamos sobre estos `.md`.
> Ubicación canónica: `e-zyro-backend/BACKEND/docs/plan-migracion-erp/`.
> Espejo de referencia para el equipo móvil: `e-zyro-app/e_zyro_app/docs/PLAN-MIGRACION-ERP.md` (puntero).

## Objetivo
Portar al ecosistema e-zyro (FastAPI + Flutter) las funcionalidades de **prioridad ALTA** que
existen en el ERP anterior (`almacen.esystemtic.com`) y **aún no** están en la app móvil, sin
perder ninguna función operativa, con calidad de equipo senior y trazabilidad total.

## Alcance (prioridad ALTA)
1. **Cloudinary + Galería Global** (transversal — base de los demás): taxonomía única de carpetas en la nube, servicio centralizado, índice de recursos y pantalla de galería con filtros.
2. **EPP** — catálogo, ingreso, entrega con firma + constancia PDF, stock, historiales.
3. **Calibraciones + Equipos Averiados** — extiende el módulo de equipos/mantenimiento.
4. **Garantías / Correctivos + Historial de Observaciones (Descargos)** — extiende servicios/operaciones.
5. **Inspección ITSE** — inspección por tablero/zona, fotos, PDF entregable.

## Índice de documentos
| Archivo | Contenido |
|---------|-----------|
| `00-MASTER-PLAN.md` | Visión, fases, **orden de implementación**, dependencias, modelo de orquestación, Definition of Done, flujo revisión→commit→arranque→documentación. |
| `01-CONVENCIONES.md` | Convenciones backend + Flutter. **Dónde va cada cosa.** RBAC, multiempresa, offline-first, migraciones, formato de commits. |
| `02-CLOUDINARY-Y-GALERIA.md` | Taxonomía de carpetas, servicio centralizado, índice `recurso_cloudinary`, backfill y módulo Galería Global. |
| `03-EPP.md` | Subplan EPP (DB → API → app → PDF). |
| `04-GARANTIAS-CORRECTIVOS-OBSERVACIONES.md` | Subplan correctivos + descargos. |
| `05-INSPECCION-ITSE.md` | Subplan ITSE. |
| `06-CALIBRACIONES-Y-EQUIPOS-AVERIADOS.md` | Subplan calibraciones + inoperativos. |
| `07-ORQUESTACION-AGENTES.md` | Roles de agentes, pipeline por punto, prompts plantilla, gates de calidad. |
| `08-PROGRESO.md` | Tracker vivo: checklist por fase/punto, estado, commits, errores. |
| `09-BITACORA-ERRORES.md` | Registro de cada error detectado al arrancar/commitear y su resolución. |

## Cómo se usa este plan
1. Se ejecuta **fase por fase** en el orden de `00-MASTER-PLAN.md` (las fases tempranas desbloquean a las tardías).
2. Cada **punto** pasa por el pipeline de `07-ORQUESTACION-AGENTES.md`: Analista → Backend → Mobile → Revisor → Documentador.
3. **Ningún commit** se hace si el backend no arranca limpio (las migraciones corren en el `lifespan`). Cada error de arranque se documenta en `09-BITACORA-ERRORES.md`.
4. El estado se refleja siempre en `08-PROGRESO.md`.

## Backlog — fuera de este ciclo (NO perder de vista)
Módulos del ERP detectados como faltantes pero **diferidos** (prioridad Media/Baja). Se abordarán en un ciclo posterior; documentados aquí para no perderlos:
- **Equipos Tecnológicos / TI** — inventario de activos informáticos (CPU, RAM, IP, MAC, garantía, asignado a). _Media._
- **Tickets / Sugerencias TIC** — mesa de ayuda con prioridad, estados y SLA. _Baja._
- **Gestión documental** — Formatos / Registros / Manuales (subida a Cloudinary; reusa la Galería de Fase 1). _Baja._
- Otros pendientes del análisis: Evaluaciones + Indicadores de Desempeño (modelo ya existe, inerte), Planos (modelo ya existe, inerte), catálogos editables (Marca, Categorías, Unidades), reseteo de contraseña por admin, bandeja de justificaciones de tardanza.

> Decisión 2026-05-29: este ciclo cubre solo las 5 fases de prioridad alta. Cuando se quiera, estos entran como Fases 6+ sin alterar lo ya hecho.

## Insumos de referencia (análisis previo)
- `D:\e-zyro-analisis\COMPARATIVA_ERP_vs_EZYRO.md` — comparativa de los 58 módulos.
- `D:\e-zyro-analisis\inventory.json` / `resumen-erp.md` — inventario crudo (campos, columnas, formularios) por sección del ERP.
- `D:\e-zyro-analisis\shots\*.png` — capturas de cada pantalla del ERP.
