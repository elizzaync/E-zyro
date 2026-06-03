# Resumen de cambios — E-zyro (junio 2026)

Documento de referencia de todo lo implementado en esta etapa. Cubre app móvil
(Flutter, rama `e-zyro-app`) y backend (FastAPI, rama `Backend` → Railway).

> Empresa de datos: `dbfed7ef-9768-4dd0-86fc-917c6f4b1aea` (Esystemtic S.A.C.)

---

## 1. Catálogos — jerarquía Ubicación › Zona › Área

**Problema:** las zonas existían pero no estaban conectadas a sus ubicaciones
(91 zonas sin `ubicacion_id`); las áreas se mostraban sueltas.

**Hecho:**
- Migración de datos: se reconectaron todas las zonas a su ubicación y se
  generaron las zonas estándar por ubicación. **0 zonas huérfanas**.
- App (`pantalla_catalogos.dart`): árbol interactivo Ubicación → Zona con
  editar / eliminar / agregar hijo inline. Se removió el nivel "Área" de la
  vista (las áreas quedan como entidad organizacional aparte).

## 2. Informe ITSE en PDF — texto sobrepuesto

**Problema:** las tablas largas del informe se escribían encimadas.

**Hecho (`pdf_docs.py`):** todas las celdas se envuelven en `Paragraph` (wrap
real), uso de ancho completo de página, `splitByRow=True` para salto de página
y anchos de columna correctos (Descripción 112 mm, Tablero 90 mm).

## 3. "Mis conexiones" — sesiones duplicadas

**Problema:** cada login creaba una sesión nueva (se acumulaban ~30).

**Hecho:**
- BD: `sesion_usuario.device_id` (UUID persistente por dispositivo) + índice.
- Backend `/auth/login`: **upsert por `device_id`** (reutiliza la sesión del
  mismo equipo) + limpieza de sesiones cerradas > 30 días.
- App: genera y guarda un `device_id` por instalación y lo envía en el login.
- Se consolidaron las 58 sesiones existentes a 3 (una por usuario).

## 4. Login Git — cuenta por defecto

`git config --global credential.https://github.com.username CrewHH` para que
Git Credential Manager deje de pedir selección de cuenta en cada push.

---

## 5. Fase 1 — Logística: buscar y filtrar rápido

Para manejar miles de ítems sin listas planas infinitas.

**Backend (`/requerimientos/catalogo`):**
- Filtros `estado_stock` (todos | con_stock | bajo | agotado), `orden`
  (nombre | stock_asc | stock_desc | reciente), `almacen_id`.
- Devuelve `stock_minimo` (antes faltaba → los badges de mínimo no servían).
- Nuevo `/requerimientos/catalogo/resumen`: conteos {total, con_stock, bajo,
  agotado} para el header.

**App:**
- **Materiales** (`pantalla_materiales_logistica.dart`): header de chips con
  conteos que filtran, chips de categoría, menú de orden, **scroll infinito**
  (30/página) y badges de color por nivel de stock.
- **Equipos** (`pantalla_equipos_logistica.dart`): se corrigió el truncado a
  200 (había 579 herramientas). Paginación por clase con scroll infinito; los
  tabs muestran el total real del backend; chips de filtro por estado operativo.

## 6. Migración de stock e inventario

- **Herramientas** movidas de `material` (tipo='herramienta', 579) a la tabla
  `equipo` con su cantidad real del ERP anterior. Las filas viejas en `material`
  quedaron inactivas.
- **Stock de consumibles** poblado desde el ERP anterior (tabla `materiales`):
  1.645 ítems, ~60.000 unidades, con su `cantidad_minima`.

## 7. Fase 2 — Dashboards / KPIs ejecutivos

Módulo de analítica tipo Power BI. Ver detalle de fórmulas en
[`DASHBOARDS.md`](./DASHBOARDS.md).

**Backend:** nuevo router `/analitica` (solo lectura, gated por `reportes:ver`,
admin pasa automático) con 4 endpoints: `/operaciones`, `/logistica`,
`/personal`, `/activos`.

**App:** pantalla **Dashboards** (Más → Administración) con `fl_chart`:
KPI cards, donut charts, líneas de tendencia y rankings de barras horizontales.
4 tabs: Operaciones · Logística · Personal · Activos.

## 8. Fase 3 — Planos tipo Drive (híbrido)

**Backend (`/planos`):**
- Carpetas recursivas (`carpeta_documental`, `padre_id`): listar/crear/
  renombrar/eliminar (solo vacías).
- Planos con versionado (`plano` + `version_plano`): crear con archivo, subir
  nueva versión (activa la última), detalle con historial, eliminar (limpia
  Cloudinary).
- Subida a Cloudinary carpeta `planos`: imágenes→`image`, PDF/DWG/DXF→`raw`,
  guarda `formato` y `bytes`.
- Híbrido: `plano.proyecto_id` opcional (global o ligado a proyecto).
- Lectura: cualquier usuario; escritura: admin/jefe/supervisor/logística.

**App:** pantalla **Planos** (Más → Recursos) con `file_picker`:
navegador con breadcrumb, botón + (crear carpeta / subir plano), tarjetas con
ícono por tipo, detalle con abrir/descargar, nueva versión, eliminar e
historial. Back de sistema sube un nivel.

## 9. Clasificación de activos (taxonomía de `equipo`)

Se definió y aplicó la clasificación de los 596 activos propios:

| Clase (`equipo.clase`) | Qué es | Ejemplos | Cant. |
|---|---|---|---|
| `equipo` | Herramienta **tecnológica/eléctrica** que suele requerir **calibración o mantenimiento** | multímetro, pinza amperimétrica, aspiradora, taladro, amoladora, cámara termográfica | 73 |
| `herramienta` | Herramienta **manual** no tecnológica; rara vez con mantenimiento (pero puede) | alicate, martillo, llave, destornillador dieléctrico, broca | 504 |
| `equipo_tecnologico` (mostrado como **"Activos TI"**) | Activo **TI / de cómputo** | PC, laptop, impresora, monitor, cámara IP, router | 19 |

Reclasificación por palabras clave (con excepciones: "cámara termográfica" =
instrumento de medición → `equipo`; accesorios como "estuche de taladro" →
`herramienta`). Re-ajustable ítem por ítem desde la app (selector de 3 chips).

> **Importante:** `equipo` (activos propios) es **distinto** de
> `equipo_intervenido` (equipos **de clientes** atendidos en servicio: tableros,
> UPS, pozos a tierra, transformadores). Son tablas e indicadores separados.

---

## Despliegue

- **Backend**: push a rama `Backend` → Railway redeploy automático.
- **App**: requiere **reconstruir el APK** (`flutter run`/build). Dependencias
  nuevas: `fl_chart` (gráficos), `file_picker` (subida de planos).
