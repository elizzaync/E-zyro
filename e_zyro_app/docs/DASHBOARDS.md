# Dashboards — fórmulas y fuentes de datos

Documentación de cada vista del módulo de analítica: qué muestra, **cómo se
calcula** y **de qué tabla sale**.

- **Backend:** `app/routers/analitica.py` (FastAPI, SQL sobre PostgreSQL).
- **App:** `lib/screens/pantalla_dashboards.dart` (`fl_chart`).
- **Acceso:** menú **Más → Administración → Dashboards**.
- **Permiso:** `tiene_permiso(reportes, ver)` — admin/superadmin pasan
  automático; Jefe de Operaciones lo tiene por rol. Si no hay permiso, el
  endpoint devuelve `{"sin_permiso": true}` y la app muestra el aviso.
- **Multi-empresa:** todas las consultas filtran por `empresa_id` del token.

## Tipos de gráfico (app)
- **KPI card:** número grande + etiqueta.
- **Donut (PieChart):** distribución; cada porción = `valor / Σvalores`.
- **Línea (LineChart):** evolución temporal.
- **Ranking (barras horizontales):** lista ordenada; el largo de la barra =
  `valor / valor_máximo` de la serie.

Cada serie viaja como `[{ "label": <texto>, "value": <número> }]`.

---

# 1. Operaciones y servicios
`GET /analitica/operaciones` — fuentes: `proyecto`, `proyecto_servicio`,
`cliente`.

### KPIs
| KPI | Fórmula | Fuente |
|---|---|---|
| Proyectos activos | `COUNT(proyecto WHERE estado='En_Proceso')` | `proyecto` |
| Servicios | `COUNT(proyecto_servicio)` | `proyecto_servicio` |
| Cumplimiento | `round(servicios_completados / servicios_total × 100)` | derivado |
| Clientes | `COUNT(cliente)` | `cliente` |

*(internos)* Completados = `estado='Completado'`; Pendientes = `estado IN
('Pendiente','En_Proceso')`.

### Gráficos
- **Servicios por estado** (donut): `GROUP BY proyecto_servicio.estado`.
- **Servicios por cliente** (ranking, top 6):
  `proyecto_servicio → proyecto → cliente`, `GROUP BY cliente.razon_social`.
- **Tendencia de servicios (6 meses)** (línea, 2 series): agrupado por mes de
  `COALESCE(fecha_programada, created_at)` en los últimos 6 meses; serie
  **Total** = `COUNT(*)`, serie **Completados** = `COUNT(*) FILTER (estado='Completado')`.

---

# 2. Logística e inventario
`GET /analitica/logistica` — fuentes: `material`, `stock`, `categoria_material`,
`equipo`.

> Base de stock (CTE): por cada material, `total = SUM(stock.cantidad)` y
> `minimo = MAX(stock.cantidad_minima)`. Solo materiales `activo=true` y
> `tipo='consumible'`.

### KPIs
| KPI | Fórmula | Fuente |
|---|---|---|
| Items | `COUNT(material activo, tipo='consumible')` | `material` |
| Unidades | `SUM(total)` sobre el CTE | `stock` |
| Bajo mínimo | `COUNT(total>0 AND minimo>0 AND total≤minimo)` | `stock`+`material` |
| Agotados | `COUNT(total≤0)` | `stock`+`material` |
| Equipos | `COUNT(equipo)` | `equipo` |
| Valor inv. | `SUM(stock.cantidad × material.precio)` | `stock`+`material` |

### Gráficos
- **Salud del stock** (donut): Con stock (`total>0`) · Bajo mínimo
  (`0<total≤minimo`) · Agotado (`total≤0`).
- **Equipos por clase** (donut): `GROUP BY equipo.clase` →
  Equipos / Herramientas / Activos TI.
- **Top materiales por stock** (ranking, top 8): consumibles con `total>0`,
  `ORDER BY total DESC`.
- **Categorías con más items** (ranking, top 8):
  `material → categoria_material`, `GROUP BY categoria.nombre`.

---

# 3. Personal y asistencia
`GET /analitica/personal` — fuentes: `empleado`, `registro_asistencia`,
`usuario`.

### KPIs
| KPI | Fórmula | Fuente |
|---|---|---|
| Empleados | `COUNT(empleado WHERE activo=true)` | `empleado` |
| Asist. mes | `COUNT(registro_asistencia tipo='entrada' del mes actual)` | `registro_asistencia` |
| Asist. total | `COUNT(registro_asistencia)` | `registro_asistencia` |
| Áreas | nº de áreas distintas (excluye valores UUID/sin asignar) | `empleado` |

### Gráficos
- **Empleados por área** (donut): `GROUP BY empleado.area`. Los valores que son
  UUID (datos sucios de la migración) se agrupan como **"Sin asignar"**.
- **Asistencia diaria (30 días)** (línea): `COUNT` de registros `tipo='entrada'`
  por día (`fecha_hora::date`) en los últimos 30 días.
- **Top asistencia del mes** (ranking, top 8): por empleado,
  `COUNT(DISTINCT fecha_hora::date)` con `tipo='entrada'` en el mes actual;
  nombre vía `empleado → usuario`.

> Nota: "Asist. mes" es 0 si en el mes en curso aún no hay marcaciones; el resto
> de los datos históricos sí aparecen en la línea de 30 días.

---

# 4. Activos y mantenimiento
`GET /analitica/activos` — fuentes: `equipo`, `equipo_intervenido`,
`inspeccion_itse`, `epp_entrega`.

> **Concepto clave:** el tab separa dos cosas distintas:
> - **Activos propios** = inventario de la empresa (tabla `equipo`).
> - **Servicio a clientes** = equipos de clientes y trabajos realizados
>   (`equipo_intervenido`, `inspeccion_itse`, `epp_entrega`). **No** son activos
>   propios; por eso van en una sección aparte.

### KPIs — Activos propios (tabla `equipo`)
| KPI | Fórmula |
|---|---|
| Activos | `COUNT(equipo)` |
| Operativos | `COUNT(estado='operativo')` |
| Mantenim. | `COUNT(estado='en_mantenimiento')` |
| Fuera serv. | `COUNT(estado IN ('fuera_de_servicio','baja'))` |

### KPIs — Servicio a clientes
| KPI | Fórmula | Fuente |
|---|---|---|
| Equipos interv. | `COUNT(equipo_intervenido)` | `equipo_intervenido` |
| Inspecciones ITSE | `COUNT(inspeccion_itse)` | `inspeccion_itse` |
| Entregas EPP | `COUNT(epp_entrega)` | `epp_entrega` |

### Gráficos
- **Activos propios por clase** (donut): `GROUP BY equipo.clase`
  (Equipos / Herramientas / Activos TI).
- **Activos propios por estado** (donut): `GROUP BY equipo.estado`.
- **Equipos intervenidos por tipo** (donut): clasificación derivada del
  `nombre` del equipo del cliente con `CASE`:
  - contiene `ups` → **UPS**
  - `trafo`/`transformador` → **Transformadores**
  - empieza con `pt` o contiene `pozo` → **Pozos a tierra**
  - empieza con `td`/`tg` o contiene `tablero` → **Tableros**
  - resto → **Otros**
- **Inspecciones ITSE por mes** (línea): `COUNT` por mes de
  `inspeccion_itse.fecha`.

---

## Cómo extender un dashboard
1. Agregar/ajustar la consulta en el endpoint correspondiente de
   `app/routers/analitica.py` y devolver la nueva serie en el JSON.
2. Mapear el campo en `lib/models/analitica_models.dart`.
3. Renderizar con un helper existente en `pantalla_dashboards.dart`
   (`_donutCard`, `_trendCard`, `_rankCard`, `_kpiGrid`).
