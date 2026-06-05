# Plan de integración — Almacén unificado (Logística)

> Objetivo: unir **Solicitudes (materiales)** + **Préstamos (equipos/herramientas)** en
> una sola pantalla con el diseño del prototipo `flutter_almacen`, **sin perder lógica
> ni funciones**. Y en **Compras**, añadir **solo** una pantalla de "carta de costo
> total / estimado" tras completar el registro.

## Decisiones tomadas
- **Paleta**: estructura/diseño del prototipo, pero acento **Material = verde de marca `#8FD11B`**;
  Equipo = índigo, Compra = ámbar (del prototipo). Fuente Plus Jakarta (`google_fonts`, ya en deps).
- **Procedimiento**: guardar el plan y arrancar por **Fase 0 (diseño) + Fase 1 (adaptador)**;
  pausa de revisión antes de tocar el panel.

## Estado actual (real)
- Panel `pantalla_inventario_panel.dart`: dos tarjetas separadas → **Solicitudes** y **Préstamos**.
- `pantalla_solicitudes_logistica.dart` + `requerimiento_service`: materiales; filtros
  todos/pendiente/aprobado/entregado/rechazado; acciones aprobar/rechazar/**entregar (firma)**.
- `pantalla_prestamos_logistica.dart` + `prestamo_service`: equipos; filtros
  solicitado/por_recibir/devuelto/confirmado/rechazado; **entregar (firma)**/rechazar/confirmar devolución.
- Compras: `procesarCompra` completa el registro; el ticket ya trae `items[precioUnitario]`,
  `totalReal`, `totalEstimado`. Falta la vista de "carta de costo total" tras procesar.

## Estrategia
Adoptar el **diseño** del prototipo como módulo nuevo y conectarlo a los **servicios reales
mediante un adaptador (view-model)**. Cambio **aditivo**: no se borran modelos ni endpoints.

### Fase 0 — Sistema de diseño (scoped) ✅ (esta entrega)
`lib/screens/logistica/almacen/es_tokens.dart` + `es_widgets.dart` portados del prototipo,
con Material en `#8FD11B`. Sin nuevas dependencias.

### Fase 1 — Adaptador de datos ✅ (esta entrega)
`lib/screens/logistica/almacen/req_unificado.dart`: view-model `ReqUnificado` que unifica
`SolicitudGestion` (material) y `Prestamo` (equipo) con estado normalizado para los tabs,
**guardando referencia al objeto original** para que cada acción siga llamando su endpoint real.

### Fase 2 — Pantalla unificada (pendiente)
`PantallaRequerimientosLogistica`: carga ambos servicios en paralelo, `ESSegmented`
Todos/Materiales/Equipos + `ESPills` de estado, tarjetas → detalle material o equipo
(porta la lógica real de las dos pantallas actuales). Conserva realtime/FCM y refresh.

### Fase 3 — Conmutar el panel (pendiente)
Reemplazar las 2 tarjetas por una sola "Requerimientos". Pantallas viejas deprecadas hasta validar.

### Fase 4 — Compras: carta de costo total (pendiente)
`PantallaResumenCompra(ticket)` con ítems (nombre · cantidad · P.unit · subtotal) y
**TOTAL = `totalReal ?? totalEstimado`** (etiqueta Real/Estimado). Enganche: tras
`procesarCompra` exitoso → `Navigator.push`. No se toca el resto de compras.

## Garantías
- Cero borrado de servicios/modelos; adaptador additivo.
- Mismos endpoints y acciones (aprobar/entregar/rechazar/devolución/firma). Realtime/FCM intactos.

## Notas / pendientes detectados
- **Stock por ítem** (StockChip de materiales): `SolicitudDetalle` no trae flag de stock;
  se enriquecerá en Fase 2 cruzando con el catálogo. En Fase 1 queda `enStock = null`.
- **Fecha de devolución/vencido** de préstamos: el backend `Prestamo` no modela una fecha
  límite; el "Vencido/Devolver" del prototipo no aplica aún (posible mejora de backend).
