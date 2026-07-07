# Cambios de API — Replanteo Equipos Intervenidos (2026-07-07)

Cambios de backend que el frontend Angular deberá acoplar. La app Flutter ya los tiene.
Contexto: todo mantenimiento es **preventivo**; el parque arranca de 0 (sin data legacy).

## 1. Crear equipo del servicio — tipo obligatorio

`POST /operaciones/servicio/{id}/equipos-intervenidos`

- `tipo_equipo_id` ahora es **obligatorio**. Sin él → `422 {"detail": "tipo_equipo_id requerido"}`.
- Si el id no existe (o es de otra empresa) → `404 "Tipo de equipo no encontrado"`.
- Acepta campo nuevo opcional `frecuencia_meses` (int 1–60, default 6).
- **Angular**: el selector "Tipo de equipo" debe ser requerido en el formulario de alta
  (quitar la opción "Sin tipo") y opcionalmente exponer la frecuencia.

## 2. Ya no se infiere el tipo por nombre

`GET /operaciones/servicio/{sid}/equipos-intervenidos/{eiId}/inspeccion`

- Se eliminó el fallback que adivinaba el tipo por el nombre del equipo
  ("pozo", "trafo", "ups"…). Un equipo sin tipo devuelve checklist vacío.
- Con el punto 1, los equipos nuevos siempre tienen tipo; no debería darse el caso.

## 3. Editar equipo — frecuencia editable

`PATCH /operaciones/servicio/{id}/equipos-intervenidos/{eiId}`

- Acepta campo nuevo `frecuencia_meses` (int 1–60; otro valor → 422).
- Si el equipo tiene `ultimo_mantenimiento`, recalcula `proximo_mantenimiento = ultimo + frecuencia`.
- La respuesta ahora incluye `frecuencia_meses` y `proximo_mantenimiento`.

## 4. Finalizar inspección — próxima fecha automática

`POST /operaciones/inspeccion/{id}/finalizar`

- Si NO se envía `proxima_fecha_mantenimiento`, el backend la calcula:
  **hoy + frecuencia_meses del equipo** (antes quedaba NULL).
- Enviarla explícita sigue funcionando y tiene prioridad.
- **Angular**: el campo puede quedar opcional; mostrar hint tipo
  "vacío = automático (hoy + frecuencia)".

## 5. Candado en entregables al cliente

Regla: los procedimientos deben estar completos para generar documentos al cliente.

- `POST /operaciones/servicio/{id}/informe/generar` — para roles que generan el
  **informe final** (no Técnico ni Jefe de Operaciones, que conservan su pre-informe
  de avance sin candado): si algún equipo del payload tiene
  `estado_intervencion != 'completado'` → `400` con los nombres pendientes.
- `POST /operaciones/servicio/{id}/carta-garantia/generar` — mismo candado, siempre.
- Certificados (`/certificado/pozo`, `/certificado/operatividad`) ya lo tenían (sin cambio).
- **Angular**: manejar el `400` mostrando el `detail` (viene legible) y/o deshabilitar
  el botón cuando haya seleccionados equipos sin completar.

## 6. Alertas y servicios automáticos (sin acción en Angular, informativo)

- El scheduler ahora emite alertas 30/15/7 días/vencido también para
  `equipo_intervenido.proximo_mantenimiento` (antes solo equipos de logística).
  Notificación categoría `mantenimiento`, referencia `eimant:{id}:{fecha}:{umbral}`.
- El servicio de mantenimiento auto-generado hereda `ubicacion_id`/`zona_id`
  cuando todos los equipos comparten sede.

## 7. Pantalla "Procedimientos Estándar" con plantillas por tipo de equipo

Sin cambio de API (los endpoints ya existían), pero la app ahora gestiona desde
"Procedimientos Estándar" DOS niveles en tabs:

- **Equipos intervenidos** (tab principal): checklist de mantenimiento por tipo de
  equipo — CRUD sobre `tipo_equipo.procedimientos_template` vía
  `GET /logistica/tipos-equipo`, `GET/PATCH /logistica/tipos-equipo/{id}/procedimientos`,
  `POST /logistica/tipos-equipo`. Los tipos con pasos genéricos "Procedimiento N"
  se marcan como placeholder (ámbar) para completar su redacción.
- **Tipos de servicio** (tab secundaria): lo que ya existía (plantilla_procedimiento
  por catálogo de servicio), sin cambios.

**Angular**: replicar la misma separación si se quiere paridad; formato del body
del PATCH: `{"procedimientos": [{"orden": 1, "nombre": "...", "descripcion": ""}]}`.

## Pendiente (no acoplado aún, avisaremos)

- Seed de `tipo_equipo` + plantillas de procedimientos (`procedimientos_template`).
- Disparo automático de certificados al registrar el mantenimiento (flujo del
  sistema PHP anterior: elegir foto representativa por procedimiento → PDFs por tipo).
