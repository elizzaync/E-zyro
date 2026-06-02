# Informe Técnico — Módulo `Operaciones / Servicio` (Web Angular)
### Guía completa de lógica, pantallas, funciones, botones y estados para replicar en el App Móvil (Flutter)

> **Fuente:** `E-zyro-frontend` (Angular 21 standalone).
> **Objetivo:** documentar *absolutamente toda* la lógica del flujo de servicio de operaciones para guiar la implementación/modificación del app móvil. Cada botón, cada función, cada estado, cada precaución de concurrencia y cada llamada al backend está aquí.
> **Fecha de levantamiento:** 2026-05-28.

---

## 0. Mapa de rutas del módulo

Definido en `src/app/app.routes.ts`. Todas protegidas por `authGuard` (requieren JWT en `localStorage.ezyro_token`).

| Ruta | Componente | Propósito |
|---|---|---|
| `/operaciones` | `OperacionesComponent` | Dashboard de operaciones + lista de proyectos |
| `/operaciones/proyecto/:id` | `OperacionesServiciosListaComponent` | Lista de **servicios** de un proyecto (tarjetas con stepper de fases) |
| **`/operaciones/servicio/:id`** | **`OperacionesDetalleComponent`** | **★ Pantalla central: detalle y ejecución de un servicio** |
| `/operaciones/servicio/:id/equipos` | `EquiposIntervenidosComponent` | Zonas / equipos intervenidos (hoy con datos MOCK) |
| `/operaciones/servicio/:id/equipos/:zonaId` | `EquiposZonaComponent` | Equipos de una zona específica |
| `/operaciones/cronograma/:proyectoId` | `OperacionesCronogramaComponent` | Diagrama de Gantt del proyecto (servicios + tareas) |

**Jerarquía conceptual:**
```
Proyecto  ──►  Servicio (proyecto_servicio)  ──►  Procedimientos/Tareas
                     │
                     ├─► Equipo de trabajo (técnicos asignados)
                     ├─► Materiales / Herramientas / Equipos (requerimientos)
                     ├─► Evidencias (fotos por etapa: antes/durante/después)
                     ├─► Chat en tiempo real (WebSocket)
                     ├─► Comunicados (nivel proyecto)
                     └─► Notas (nivel servicio)
```

---

## 1. Ciclo de vida del servicio: las 4 FASES

**Fuente única de verdad:** `src/app/features/operaciones/fase-servicio.ts`. La usan el detalle y las tarjetas de la lista para no desincronizarse.

### 1.1 Las 4 fases (en orden)

| N° | Nombre | Subtítulo | Significado |
|----|--------|-----------|-------------|
| 1 | **Preparación** | Equipo y materiales | Se arma equipo, se reparten tareas, se eligen materiales |
| 2 | **En sitio** | Inspección y medición | Equipo en campo (servicio iniciado, 0–49% progreso) |
| 3 | **Ejecución** | Aplicación y pruebas | Servicio iniciado con ≥50% progreso |
| 4 | **Cierre** | Informe y firma | Servicio completado |

### 1.2 Estados del servicio (backend)

`EstadoServicio = 'Pendiente' | 'En_Proceso' | 'Completado' | 'Cancelado'`

### 1.3 Función `faseActiva(estado, progreso)` — cálculo de la fase activa

```
Pendiente   → fase 1 (Preparación)
En_Proceso  → progreso >= 50 ? fase 3 (Ejecución) : fase 2 (En sitio)
Completado  → fase 4 (Cierre)
default     → fase 1
```

### 1.4 Función `faseClase(n, estado, progreso)` — pintado del stepper

Devuelve `'done' | 'active' | 'muted'`:
- Si estado = `Completado` → **todos** los pasos `done`.
- `n < faseActiva` → `done`
- `n === faseActiva` → `active`
- `n > faseActiva` → `muted`

> **Para móvil:** replicar este archivo como una utilidad pura (`fase_servicio.dart`) — es matemática de presentación, sin estado. El stepper debe consumir exactamente esta misma función para que web y móvil muestren la misma fase.

---

## 2. PANTALLA CENTRAL — `OperacionesDetalleComponent` (`/operaciones/servicio/:id`)

Archivos: `operaciones-detalle.component.ts` (1691 líneas) + `.html` (1455 líneas).
Es la pantalla más compleja del sistema. Se compone de **cabecera + stepper + checklist de preparación + grid de 3 columnas + footer + 5 modales**.

### 2.1 Carga inicial (`ngOnInit` → `cargarDetalle`)

1. Lee `servicioId` del parámetro de ruta.
2. Lee el usuario logueado de `localStorage.ezyro_user`:
   - `_nombreUsuario`, `_usuarioId`, `_usuarioFoto`.
   - **`soyJefeOperaciones = true`** si `rol === 'jefe_operaciones'` o `rol === 'administrador'`. ← **flag de permisos clave**.
3. `cargarDetalle()` llama `GET /operaciones/servicio/{id}` y mapea (`_mapServicio`) a `ServicioDetalle`.
4. Tras cargar, dispara en cascada:
   - `_conectarChat(id)` — abre WebSocket.
   - `_checkDeepLink()` — si viene `?abrirTareaId=...` en query, abre el modal de evidencia de esa tarea (usado por el Gantt).
   - `cargarBorrador()` — `GET /operaciones/servicio/{id}/borrador`.
   - `cargarComunicados()` — `GET /comunicados/proyecto/{proyectoId}`.
   - `cargarNotas()` — `GET /operaciones/servicio/{id}/notas`.
   - `cargarReqsListos()` — requerimientos aprobados/listos (HU-16, firma).

### 2.2 Modelo de datos `ServicioDetalle` (lo que devuelve el detalle)

```ts
{
  id, proyectoId, cliente, tipoServicio, ubicacion,
  fechaStr, horaStr, descripcion,
  estado: 'Pendiente'|'En_Proceso'|'Completado'|'Cancelado',
  progreso: number,                  // 0-100
  equipo: MiembroEquipo[],           // {id, nombre, apellido, fotoUrl, cargo, rolProyecto}
  procedimientos: Procedimiento[],   // tareas (ver abajo)
  itemsAsignados: ItemMaterial[],    // materiales+herramientas asignados originalmente
  itemsSolicitados: ItemMaterial[],  // materiales+herramientas solicitados después
}
```

- **`Procedimiento`** = `{ id, nombre, descripcion, orden, estado: 'pendiente'|'en_proceso'|'completado'|'bloqueado', evidencias[], responsableId }`.
- **`EvidenciaProcedimiento`** = `{ id, urlCloudinary, descripcion, fechaCaptura, etapa: 'antes'|'durante'|'despues' }`.
- **`ItemMaterial`** = `{ id, requerimientoId, nombre, unidad, cantidad, estadoReq: 'pendiente'|'aprobado'|'rechazado'|'entregado'|'anulado', clase: 'material'|'herramienta'|'equipo', estadoEquipo }`.

**Mapeo backend→front importante:** el backend usa snake_case (`proyecto_id`, `foto_url`, `estado_req`, `url_cloudinary`). El front separa los materiales en dos baldes y mezcla materiales + herramientas:
```
itemsAsignados   = materiales_asignados + herramientas_asignadas
itemsSolicitados = materiales_solicitados + herramientas_solicitadas
```

### 2.3 CABECERA (`.svc-headbar`)

**Muestra:**
- Botón **Volver** (`volver()` → `location.back()`).
- Pills: tipo de servicio (marca), estado (color según `Pendiente`/`En_Proceso`/`Completado`), referencia `Servicio · <id 8 chars>`.
- Título = cliente. Meta: ubicación, fecha · hora, N° técnicos, N° materiales.
- **Barra de progreso** (`servicio.progreso %`).

**Botones de acción (`.hb-actions`):**

| Botón | Visible cuando | Acción | Lógica/candado |
|---|---|---|---|
| **Equipos** | siempre | `irAEquiposIntervenidos()` → navega a `/equipos` | — |
| **Pre-Informe** | siempre | `abrirModalPreInforme()` | Genera PDF con pdf-lib (ver §2.13) |
| **Iniciar** | `estado === 'Pendiente'` | `iniciarServicio()` | **Bloqueado** si `!puedeIniciar`. Icono candado cuando bloqueado |
| **Finalizar** | `estado === 'En_Proceso' && soyJefeOperaciones` | `finalizarServicio()` | `disabled` si `!todasCompletadas` (progreso ≠ 100%) |
| **Concluido** | `estado === 'Completado'` | — (disabled) | Estado terminal |

### 2.4 LÓGICA DE INICIO DE SERVICIO (★ regla de negocio crítica)

El servicio **no se puede iniciar** (Pendiente → En_Proceso) hasta cumplir el checklist de Fase 1. Getter `motivosInicio` arma la lista de lo que falta:

```
motivosInicio incluye:
- 'asignar el equipo técnico'              si equipo.length === 0
- 'repartir las tareas del servicio'        si procedimientos.length === 0
- 'asignar un responsable a todas las tareas' si alguna tarea sin responsableId
- 'elegir los materiales y herramientas'    si totalMateriales === 0 && borrador vacío
- 'enviar el borrador a Logística'          si materialesBorrador.length > 0
- 'esperar la entrega de N material(es)'     si materialesPendientesEntrega > 0
```

`puedeIniciar = motivosInicio.length === 0`.

`iniciarServicio()`: valida de nuevo `motivosInicio`; si falta algo, muestra toast de error con la lista. Si todo OK → `PATCH /operaciones/servicio/{id}/estado {estado:'En_Proceso'}`, actualiza estado local y toast "Servicio iniciado".

**Sub-getters de los 3 sub-pasos de Fase 1 (checklist visual):**
- `prepEquipoListo` = `equipo.length > 0`.
- `prepTareasListo` = `procedimientos.length > 0 && todas tienen responsableId`.
- `prepMaterialesListo` = `totalMateriales > 0 && borrador vacío && nada pendiente de entrega`.
- `prepMaterialesHint` = texto contextual (cuántos en borrador, esperando entrega, etc.).

### 2.5 STEPPER DE FASES (`.svc-stepper`)

Renderiza las 4 fases (`fasesLista`). Cada paso pinta `done`/`active`/`muted` vía `faseClase(n)`. Pasos `done` muestran ✓; conectores (`step-line`) se llenan (`filled`) cuando el paso está `done`.

### 2.6 CHECKLIST DE PREPARACIÓN (`.prep-checklist`) — solo si `estado === 'Pendiente'`

Lista visual de los 3 sub-pasos (`prepEquipoListo`, `prepTareasListo`, `prepMaterialesListo`), cada uno con ✓ o número. Al final:
- Si `!puedeIniciar`: nota ámbar "Falta: <motivosInicio>".
- Si `puedeIniciar`: nota verde "Todo listo. Ya puedes iniciar el servicio."

### 2.7 BANNER HU-16 — MATERIALES LISTOS PARA FIRMAR (`.firma-card`) — solo si `reqsListos.length > 0`

Es el cierre del ciclo de requerimientos: cuando Logística **aprueba** un requerimiento, aparece aquí para que el equipo **firme la recepción**.

- `cargarReqsListos()`: `GET /logistica/requerimientos?estado=todos&servicioId={id}`, filtra `estado === 'aprobado' || 'listo'`.
- `hayReqsPorFirmar` = algún req en `'aprobado'`.
- Cada req lista sus items (chips: `nombre × cantAprobada unidad`, marca `(compra)` si `estadoItem === 'para_compra'`).
- Botón **"Firmar recepción"** (si `estado === 'aprobado'`) → `abrirFirma(req)`.
- Si ya firmado → muestra "Firmado · esperando despacho".

**Modal de firma (canvas):** `abrirFirma` → bloquea scroll, inicializa canvas. `firmaStart/Move/End` dibujan con mouse o touch (¡ya soporta touch, ideal para móvil!). `confirmarFirma()`:
- Exige `_hayTrazo` (debe haber dibujado algo).
- `canvas.toDataURL('image/png')` → `POST /logistica/requerimientos/{id}/firmar { recibidoPorId:'', firmaUrl: dataUrl }`.
- Toast "Recepción firmada. Logística fue notificada." + recarga.

### 2.8 GRID DE 3 COLUMNAS

#### COLUMNA IZQUIERDA — Equipo de trabajo + Materiales

**Equipo de trabajo:** grid de tarjetas (`miembro-card`) con avatar (foto o iniciales `getIniciales`, color `getColorAvatar(i)`), nombre, rol de proyecto, cargo. Si vacío: "Sin miembros asignados."

**Materiales y Herramientas:** dos bloques:
- **Asignados (N):** lista `itemsAsignados`. Cada fila (`mat-row`): icono por clase (equipo/herramienta/material), nombre, `× cantidad unidad`, badge de clase, badge de estado (`estadoReq`), botón editar lápiz si `puedeEditar`.
- **Solicitados (N):** lista `itemsSolicitados`, mismo formato.
- `puedeEditar(mat)` = `estadoReq !== 'entregado' && estadoReq !== 'aprobado'` (no se editan ítems ya aprobados/entregados).
- Click en fila editable → `abrirModalEditarMat(mat)` (Modal 2).
- Botón **"Agregar Material / Herramienta"** (`abrirModalSolicitar()`, Modal 3). `disabled` si `estado === 'Completado'`.

##### ★★★ BORRADOR DE MATERIALES — metodología anti-duplicidad (regla de negocio central)

Esto es lo que el usuario describió como "la metodología de la primera persona que pide". Funciona así:

1. Cada técnico que abre el Modal 3 y agrega ítems los mete a un **borrador persistente en BD** (`materialesBorrador`), NO directamente a Logística.
2. El borrador es **compartido por todo el equipo del servicio** y se sincroniza en **tiempo real** vía WebSocket: cuando llega `{tipo:'borrador_actualizado'}` por el socket, todos recargan el borrador (`cargarBorrador()`). → Todos ven en vivo lo que sus compañeros añadieron.
3. **Banner de advertencia** (`.banner-warning`): *"¡Atención Equipo! Solo un técnico debe consolidar y enviar los materiales para evitar duplicidad. Verifiquen con los demás antes de confirmar."*
4. Para enviar a Logística hace falta marcar el **checkbox de consenso** (`consensoEquipo`): *"Confirmo que el equipo está de acuerdo con esta solicitud en lote"*. Sin él, el botón de enviar está deshabilitado.
5. Botón **"Enviar N ítems a Logística"** (`enviarSolicitudLote()`) → `POST /operaciones/servicio/{id}/borrador/enviar`. Vacía el borrador y recarga el detalle (los ítems pasan a ser requerimientos formales).

> **Por qué importa:** evita que 3 técnicos pidan el mismo taladro 3 veces. El borrador compartido + consenso + envío único por una sola persona es la salvaguarda. **Esto DEBE replicarse en móvil** con la misma sincronización en tiempo real (el app ya tiene `syncCompletedNotifier` + FCM `borrador_actualizado` — ver memoria `ezyro-realtime`).

**Operaciones sobre el borrador:**
| Acción | Función | Endpoint |
|---|---|---|
| Cargar borrador | `cargarBorrador()` | `GET /operaciones/servicio/{id}/borrador` |
| Agregar ítem | `agregarItemBorrador` (vía Modal 3) | `POST /operaciones/servicio/{id}/borrador/item` |
| Editar ítem (inline) | `guardarEdicionBorrador(i)` | `PATCH /operaciones/requerimiento-detalle/{rdId}` |
| Quitar ítem | `removerDelBorrador(i)` | `DELETE /operaciones/borrador-detalle/{rdId}` |
| Enviar lote | `enviarSolicitudLote()` | `POST /operaciones/servicio/{id}/borrador/enviar` |

Cada ítem del borrador guarda **quién lo agregó** (`agregadoPor`, `agregadoPorFoto`) — visible en la tarjeta (avatar + "Añadido por <nombre>"). Ítems de compra externa llevan badge "COMPRA EXTERNA" (`esNuevo === true`).

**Edición inline del borrador:** `editarItemBorrador(i)` activa modo edición (`editandoIndice`); si el ítem es nuevo (compra externa) deja editar nombre + especificación + cantidad; si no, solo cantidad. `cancelarEdicionBorrador()` / `guardarEdicionBorrador(i)`.

#### COLUMNA CENTRAL — Tareas (timeline) + Evidencias

**Tareas del servicio (`.tareas-card`):**
- Header: título + contador `tareasCompletadas / total completadas`.
- Descripción del problema embebida (`servicio.descripcion`).
- Timeline de `procedimientos`. Cada ítem:
  - **Nodo toggle** (`tl-node`) → `toggleProcedimiento(proc)`: alterna `completado` ⇄ `pendiente`. **Optimista:** cambia estado local + `recalcularProgreso()`, luego `PATCH /operaciones/procedimiento/{id}/estado`; si falla, revierte. `disabled` si `estado === 'Completado'`.
  - Nombre `orden. nombre`, sub: N° evidencias o "Sin evidencias".
  - Badge de estado (`procEstadoLabel`: pendiente→"No iniciado", en_proceso→"En proceso", completado→"Completado", bloqueado→"Bloqueado").
  - **Botón cámara** (`tl-ev`) → `abrirModalEvidencia(proc)` (Modal 1). `disabled` si Completado.
- `recalcularProgreso()`: `progreso = round(completadas / total * 100)`.

**Procesos / Evidencia (`.fotos-grid`):** galería de `todasLasEvidencias` (flatMap de evidencias de todas las tareas). Cada foto: imagen Cloudinary + overlay (descripción + hora). Hay un tile "Agregar Foto" (decorativo/general).

#### COLUMNA DERECHA — Chat + Comunicados + Notas

**(A) Chat en tiempo real** (ver §2.9).
**(B) Comunicados** (ver §2.10).
**(C) Notas del servicio** (ver §2.11).

### 2.9 CHAT EN TIEMPO REAL (WebSocket)

- Conexión: `_conectarChat(servicioId)` abre `ws(s)://<api>/ws/chat/servicio/{servicioId}?token=<jwt>`.
- Mensajes entrantes (`chatSocket$.subscribe`):
  - `{tipo:'historial', mensajes:[...]}` → carga historial completo.
  - `{tipo:'error'}` → ignora.
  - `{tipo:'borrador_actualizado'}` → recarga el borrador de materiales (¡el socket de chat también notifica cambios de borrador!).
  - Cualquier otro → push del mensaje al chat.
- Enviar: `enviarMensajeChat()` → `chatSocket$.next({ contenido, destinatario_id })`. El backend hace broadcast al remitente también (el mensaje propio llega de vuelta por el WS).
- **Mensajes privados (solo jefe):** si `soyJefeOperaciones`, aparece un `<select>` para elegir destinatario (`chatDestinatario`): "Todos (Equipo)" o un miembro concreto. Mensajes privados muestran tag "privado".
- `esMiMensaje(msg)`: compara por `remitente_id === miId`, con fallback por nombre completo.
- Avatares: `getChatAvatarColor(id)` (hash → paleta), `getChatInitiales(nombre)`, `getChatMemberFoto(id)` (busca en equipo).
- Header con pill "En vivo" + N° participantes.
- Input `disabled` si `estado === 'Completado'`.

> **Para móvil:** el app ya usa FCM + `syncCompletedNotifier`. Para el chat conviene WebSocket nativo igual que web (mismo endpoint), o degradar a polling. El endpoint y el protocolo de mensajes son los mismos.

### 2.10 COMUNICADOS (nivel PROYECTO — tablero de anuncios)

- `cargarComunicados()`: `GET /comunicados/proyecto/{proyectoId}`.
- Cada comunicado: `{id, titulo, mensaje, autor, fecha, adjunto_url, leido}`.
- `comunicadosNoLeidos` = badge de no leídos.
- **Crear (solo jefe):** botón "Nuevo" → `abrirNuevoComunicado()` muestra form (título + mensaje). `enviarComunicado()` → `POST /comunicados/proyecto/{proyectoId}/nuevo`. Valida título y mensaje no vacíos.
- **Marcar leído:** click en un comunicado → `marcarComunicadoLeido(c)` (optimista) → `PUT /comunicados/{id}/marcar-leido`.
- Adjunto (`adjunto_url`) abre en nueva pestaña.
- En móvil ya escuchado vía FCM `comunicado_proyecto` (memoria `ezyro-realtime`).

### 2.11 NOTAS DEL SERVICIO (nivel SERVICIO — CRUD)

- `cargarNotas()`: `GET /operaciones/servicio/{id}/notas`. Cada nota: `{id, descripcion, autor, autor_id, fecha, puede_editar}`.
- **Crear:** textarea + botón "Agregar" (`agregarNota()` → `POST /operaciones/servicio/{id}/nota`). Atajo: `Ctrl+Enter`.
- **Editar:** solo si `puede_editar` (es el autor). `iniciarEdicionNota` → textarea inline → `guardarEdicionNota(n)` → `PUT /operaciones/nota/{id}`.
- **Eliminar:** `eliminarNota(n)` → `DELETE /operaciones/nota/{id}` (con spinner `notaEliminandoId`).

### 2.12 FOOTER DE ACCIÓN (`.action-footer-bar`) — solo si `estado !== 'Completado'`

- Barra de mini-progreso + porcentaje.
- Botón **Pre-Informe** (`abrirModalPreInforme()`).
- Botón **Finalizar e Informe Total** (`finalizarServicio()`):
  - Si `soyJefeOperaciones`: `disabled` hasta `todasCompletadas` (100%). Si no llega, muestra "Bloqueado (N%)".
  - Si NO es jefe: botón siempre deshabilitado mostrando "Esperando Cierre de Jefatura" (si 100%) o "En Ejecución (N%)".

### 2.13 FINALIZAR SERVICIO — `finalizarServicio()`

```
1. Candado: si !soyJefeOperaciones → toast "Acceso denegado: solo el Jefe de
   Operaciones puede finalizar y cerrar este servicio." y return.
2. Si !todasCompletadas o sin servicio → return.
3. PATCH /operaciones/servicio/{id}/estado {estado:'Completado'} → estado local = Completado.
4. abrirModalPreInforme() → genera y muestra el PDF.
```

Cuando `estado === 'Completado'`: banner "Servicio Concluido" + **todos los inputs pasan a solo lectura** (chat, toggles de tareas, agregar material, etc. todos `disabled`).

### 2.14 PRE-INFORME PDF — `abrirModalPreInforme()` (pdf-lib, lazy import)

Genera **client-side** un PDF profesional A4 (`pdf-lib`). Estructura del documento:
- Cabecera "INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO" + identidad E-System TIC + línea verde de marca.
- Metadatos en 2 columnas: OT (`OT-<id 8 chars>`), fecha emisión, cliente, hora, tipo servicio, estado, ubicación, fecha servicio, técnico responsable (usuario logueado).
- Indicador de progreso textual.
- **Sección 1:** Descripción del problema (word-wrap).
- **Sección 2:** Tabla de procedimientos (N°, nombre, estado, N° evidencias) + sub-fila de descripción.
- **Sección 3:** Liquidación de materiales — dos tablas: "Asignados Originalmente" y "Extra Aprobados" (filtra `itemsSolicitados` con estado `aprobado`/`entregado`).
- **Sección 4:** Registro fotográfico — descarga imágenes de Cloudinary (`fetch`→`arrayBuffer`), las incrusta en grilla 3-columnas agrupadas por etapa (Antes/Durante/Después).
- Pie institucional + paginación automática (`checkPage`).
- Resultado: `Blob` → `URL.createObjectURL` → iframe en el modal.
- `descargarPDF()`: descarga con nombre `pre-informe-<cliente>-<timestamp>.pdf`.

> **Para móvil:** Flutter no usa pdf-lib. Opciones: (a) generar el PDF en el backend y descargarlo, o (b) usar el paquete `pdf`/`printing` de Dart replicando esta estructura. **Recomendado: mover la generación al backend** (un solo lugar de verdad para el formato del informe) y exponer `GET /operaciones/servicio/{id}/informe.pdf`.

---

## 3. LOS 5 MODALES DEL DETALLE

| # | Modal | Trigger | Función abrir | Función guardar/acción |
|---|---|---|---|---|
| 1 | **Evidencia por etapas** | botón cámara en tarea | `abrirModalEvidencia(proc)` | `guardarEvidenciaPorEtapa(etapa)` |
| 2 | **Editar material** | click fila editable | `abrirModalEditarMat(mat)` | `guardarEditarMat()` |
| 3 | **Agregar material/herramienta/equipo** (3 tabs) | botón "Agregar" | `abrirModalSolicitar()` | `solicitarMaterial()` / `solicitarEquipo()` / `solicitarMaterialManual()` |
| 4 | **Pre-Informe PDF** | botón "Pre-Informe" | `abrirModalPreInforme()` | `descargarPDF()` |
| 5 | **Firma de recepción** (HU-16) | botón "Firmar recepción" | `abrirFirma(req)` | `confirmarFirma()` |

### 3.1 Modal 1 — Evidencia por etapas

- 3 slots: **antes / durante / después** (`etapasLista`).
- Cada slot: si ya existe evidencia (`getEvExistente(etapa)`) la muestra con ✓; si no, dropzone para subir foto (`accept="image/*"`).
- `onFileSlotSelected(event, etapa)`: guarda File + genera preview con FileReader.
- `guardarEvidenciaPorEtapa(etapa)`: `FormData{archivo, etapa}` → `POST /operaciones/procedimiento/{procId}/evidencia`. Al éxito: agrega evidencia, **marca la tarea como `completado`**, recalcula progreso, limpia slot.

> **Para móvil:** ya existe el flujo offline-first de evidencias (memoria `ezyro-offline-first`). Las etapas antes/durante/después deben mantenerse idénticas.

### 3.2 Modal 2 — Editar material

Solo cantidad (el nombre es readonly). `guardarEditarMat()` → `PATCH /operaciones/requerimiento-detalle/{id} {cantidad}`. Muestra estado actual del requerimiento.

### 3.3 Modal 3 — Agregar al Requerimiento (3 pestañas)

Todas las pestañas **agregan al borrador** (no envían directo a Logística):

**Tab "Materiales"** (del inventario):
- Búsqueda con debounce (`buscarMateriales()`, min 2 chars) → `GET /operaciones/materiales/buscar?q=`.
- Dropdown de resultados (nombre, unidad, stock). `elegirMaterial(mat)`.
- Cantidad (max = stock). `solicitarMaterial()` → `agregarItemBorrador {material_id, nombre, unidad, cantidad}`.

**Tab "Equipos / Herramientas"** (del inventario):
- `buscarEquipos()` → `logistica.getEquipos({q})`, filtra solo `estado === 'operativo'`.
- `elegirEquipo(eq)`. `solicitarEquipo()` → `agregarItemBorrador {material_id:null, nombre, especificacion:'[Equipo|Herramienta] ...'}`.

**Tab "Compra Externa"** (no está en inventario):
- Campos: nombre exacto (*), cantidad (*), unidad (select), especificación/justificación (*).
- `solicitarMaterialManual()` → `agregarItemBorrador {material_id:null, esNuevo:true, especificacion}`. Marca como COMPRA EXTERNA.

### 3.4 Modal 5 — Firma de recepción (ver §2.7)

Incluye **preview del "Reporte de Salida de Materiales"** (tabla: material, cantidad, origen stock/compra) + canvas de firma (mouse + touch). Confirma → `firmarRequerimiento`.

---

## 4. LISTA DE SERVICIOS — `OperacionesServiciosListaComponent` (`/operaciones/proyecto/:id`)

Pantalla previa al detalle. Muestra las tarjetas de servicios de un proyecto.

- `cargarServicios()`: `GET /operaciones/proyecto/{id}/servicios`. Modelo `ServicioProyecto {id, nombre, descripcion, estado, orden, fecha_programada, estado_color, progreso}`.
- **Filtros:** `['Todos','Pendiente','En_Proceso','Completado']` (`setFiltro`, `serviciosFiltrados`).
- Cada tarjeta muestra el **mismo stepper de 4 fases** (`faseClaseCard` usa `faseClaseServicio` con `active→'current'`).
- **Navegación:**
  - Click en tarjeta → `irAlServicio(id)` → `/operaciones/servicio/{id}`.
  - Botón cronograma → `irAlCronograma()` → `/operaciones/cronograma/{proyectoId}`.
- **Botón Crear servicio:** `abrirCrearServicio()` → modal `CrearServicioModal` (modo crear).
- **Botón Editar servicio** (en tarjeta, `stopPropagation`): `abrirEditarServicio()` → modal (modo editar).
- **Botón Configurar/Asignar** (`abrirModalAsignacion`): abre `AsignacionServicioModal`. Modo `crear` si estado Pendiente, `editar` si no. `puedeAsignar` = estado no es Completado/Cancelado.
- Al cerrar modales con `{guardado:true}` → toast + recarga lista.

---

## 5. MODAL CREAR/EDITAR SERVICIO — `CrearServicioModalComponent`

Formulario reactivo (`ReactiveFormsModule`). Crea un `proyecto_servicio`.

**Campos:**
- `nombre` (req, max 200), `catalogo_servicio_id` (req — `GET /operaciones/catalogo-servicios`), `descripcion`.
- **Liderazgo:** `lider_id` (Líder del Servicio — `getLideresServicio`), `responsable_id` (Técnico Líder — `getResponsablesServicio`). Ambos opcionales; si se omite líder, el jefe que configura queda como líder.
- `zona_ejecucion`, `alcance`.
- **Documento cliente:** `tipo_documento_cliente` = `'OC'|'PROF'|'SIN_OC'`. Si `SIN_OC`, `nro_documento` se limpia y deshabilita; si OC/PROF, `nro_documento` es requerido.
- `estado`, `fecha_programada`, `fecha_inicio`, `fecha_fin`.

**Validaciones en `guardar()`:** form válido; `fecha_fin >= fecha_inicio`; `nro_documento` presente si no es SIN_OC.
**Endpoints:** crear → `POST /operaciones/proyecto/{proyectoId}/servicios`; editar → `PATCH /operaciones/servicio/{servicioId}`.

---

## 6. MODAL ASIGNACIÓN (HU-13) — `AsignacionServicioModalComponent` ★

Wizard de 3 secciones que **configura el equipo y el cronograma de tareas** de un servicio. Es lo que llena la Fase 1 (Preparación).

### Sección 1 — Resumen / Líder
- Carga el servicio (`getDetalleServicio`) → muestra cliente, ubicación, fecha, estado.
- **Líder:** el asignado al crear el servicio (`lider_id`); si no hay, el usuario logueado quedará como líder. Resuelve nombre/foto cruzando `getLideresServicio` + `getResponsablesServicio` (`_personasMap`).

### Sección 2 — Selección de equipo técnico
- `getPersonalTecnicos()` → `{tecnicos[], grupos[]}`.
- **Columna izquierda:** técnicos disponibles (`tecnicosFiltrados` = todos − seleccionados, filtrados por búsqueda `filtrarTecnicos()`).
- **Columna derecha:** `equipoSeleccionado`.
- `seleccionarTecnico(t)`: lo mueve a la derecha.
  - **★ HU-13 — Alerta de grupo:** si el técnico ya pertenece a un grupo activo (`grupoActual`), abre confirmación (`confirmGrupoOpen`) antes de añadirlo. `confirmarAgregarConGrupo()` / `cancelarAgregarConGrupo()`. **Precaución anti-conflicto: no robar un técnico de otro grupo sin confirmar.**
- `agregarGrupo(grupo)`: añade todos los miembros de un grupo de una vez.
- `removerTecnico(id)`: lo devuelve a la izquierda **y limpia su asignación** en cualquier tarea del cronograma + limpia alertas de cruce.
- `limpiarEquipo()`: vacía todo.

### Sección 3 — Cronograma de tareas (FormArray `procedimientos`)
Cada tarea: `{ id?, nombre (req), responsable_id (req), fecha_inicio (req), fecha_fin (req) }`.
- `agregarTarea()` / `removerTarea(i)` (mínimo 1 tarea).
- **★ Validación de cruce de horarios (HU-13):** al cambiar responsable/fechas → `validarCruceHorario(i)` → `POST /operaciones/personal/validar-horario {empleado_id, fecha_inicio, fecha_fin, excluir_servicio_id}`. Si hay conflicto, muestra ⚠ con el detalle (tarea + servicio + fechas en conflicto). No bloquea el guardado pero avisa. Estado por tarea en `cruceEstados[i]`.

### Guardar (`guardar()`)
- Valida: ≥1 técnico, form válido, `fecha_fin >= fecha_inicio` por tarea.
- Payload: `{ equipo: [empleadoIds], lider_id, procedimientos: [{id?, nombre, responsable_id, fecha_inicio, fecha_fin}] }`.
- `POST /operaciones/servicio/{id}/configurar`. Al éxito emite `{guardado:true}`.

> **Para móvil:** este wizard es clave para Fase 1. Si el móvil solo ejecuta (no configura), puede omitirse o ser solo-lectura; pero la **validación de cruce de horarios** y la **alerta de grupo** son reglas de negocio que conviene respetar si el móvil permite configurar.

---

## 7. CRONOGRAMA (GANTT) — `OperacionesCronogramaComponent` (`/operaciones/cronograma/:proyectoId`)

Diagrama de Gantt jerárquico: Proyecto → Servicios → Procedimientos.
- `cargarDatos()`: busca el proyecto en `getProyectos()` + `cargarServicios()`.
- `buildTimeline()`: calcula la línea temporal (desde `fecha_inicio` del proyecto hasta `fecha_fin_estimada`, o derivado de los servicios). Snap a meses. Calcula `barLeft`/`barWidth` % por servicio. Marca "hoy" (`todayLeft`).
- `toggleServicio(srv)`: expande/colapsa; al expandir por 1ª vez carga procedimientos (`getDetalleServicio`) y resuelve responsable de cada tarea cruzando con el equipo.
- `navegarATarea(servicioId, procId)`: navega a `/operaciones/servicio/{id}?abrirTareaId={procId}` → el detalle abre directamente el modal de evidencia de esa tarea (deep-link, ver §2.1).
- `parseDate`: soporta ISO y `"dd Mon YYYY"` (formato strftime del backend).

---

## 8. EQUIPOS INTERVENIDOS — `EquiposIntervenidosComponent` (`/operaciones/servicio/:id/equipos`)

> ⚠️ **ESTADO ACTUAL: DATOS MOCK.** `MOCK_ZONAS` está hardcodeado (Trujillo, Iquitos, etc.). No hay backend conectado todavía. La carga es un `setTimeout(800ms)`.

- Lista de **zonas** del servicio (`ZonaServicio`): nombre, ciudad/región, equipo total, completados, estado (`completado|en_proceso|sin_inicio`), resumen (operativos/mantenimiento/fuera de servicio/pendientes), técnicos asignados.
- Filtro por estado (`zonasFiltradas`). Progreso global (`progresoGlobal`).
- `verEquipos(zona)` → `/operaciones/servicio/{id}/equipos/{zonaId}` (`EquiposZonaComponent`).

> **Para móvil:** dejar esta sección como pendiente o feature-flag hasta que tenga backend real. No replicar los mocks como si fueran datos productivos.

---

## 9. CAPA DE SERVICIOS Y ENDPOINTS (referencia para móvil)

### `OperacionesService` (`/operaciones/*`)
| Método | Endpoint | Uso |
|---|---|---|
| `getDashboardData` | `GET /operaciones/dashboard` | Dashboard |
| `getProyectos` | `GET /operaciones/proyectos` | Lista proyectos |
| `getServiciosPorProyecto` | `GET /operaciones/proyecto/{id}/servicios` | Servicios del proyecto |
| `getDetalleServicio` | `GET /operaciones/servicio/{id}` | **Detalle (★)** |
| `actualizarEstado` | `PATCH /operaciones/servicio/{id}/estado` | Iniciar/Finalizar |
| `toggleProcedimiento` | `PATCH /operaciones/procedimiento/{id}/estado` | Completar tarea |
| `subirEvidencia` | `POST /operaciones/procedimiento/{id}/evidencia` | Foto evidencia (FormData) |
| `buscarMateriales` | `GET /operaciones/materiales/buscar?q=` | Autocomplete material |
| `actualizarRequerimientoDetalle` | `PATCH /operaciones/requerimiento-detalle/{id}` | Editar cantidad |
| `getBorrador` | `GET /operaciones/servicio/{id}/borrador` | Borrador materiales |
| `agregarItemBorrador` | `POST /operaciones/servicio/{id}/borrador/item` | Añadir al borrador |
| `removerItemBorrador` | `DELETE /operaciones/borrador-detalle/{id}` | Quitar del borrador |
| `enviarBorrador` | `POST /operaciones/servicio/{id}/borrador/enviar` | Enviar lote a Logística |
| `getNotasServicio` / `agregarNota` / `actualizarNota` / `eliminarNota` | `…/notas`, `…/nota`, `/nota/{id}` | Notas CRUD |
| `getComunicadosProyecto` / `crearComunicado` / `marcarComunicadoLeido` | `/comunicados/proyecto/{id}…` | Comunicados |
| `getPersonalTecnicos` | `GET /operaciones/personal/tecnicos` | Técnicos + grupos |
| `validarHorario` | `POST /operaciones/personal/validar-horario` | Cruce de horarios |
| `configurarServicio` | `POST /operaciones/servicio/{id}/configurar` | Equipo + cronograma |
| `getCatalogoServicios` / `getLideresServicio` / `getResponsablesServicio` / `getSiguienteOrdenTrabajo` | catálogos | Modal crear servicio |
| `crearServicio` / `actualizarServicio` | `POST/PATCH …servicios` | CRUD servicio |
| `getClientes` / `crearProyecto` / `actualizarProyecto` / `getDetalleProyecto` | proyectos | CRUD proyecto |

### `LogisticaService` (`/logistica/*`) — lado que recibe los requerimientos
| Método | Endpoint | Uso |
|---|---|---|
| `getRequerimientos` | `GET /logistica/requerimientos?estado=&servicio_id=` | Lista requerimientos |
| `aprobarRequerimiento` | `POST /logistica/requerimientos/{id}/aprobar` | Decisiones por ítem |
| `rechazarRequerimiento` | `POST /logistica/requerimientos/{id}/rechazar` | Rechazo con motivo |
| `firmarRequerimiento` | `POST /logistica/requerimientos/{id}/firmar` | **Firma recepción (★)** |
| `entregarRequerimiento` | `POST /logistica/requerimientos/{id}/entregar` | Despacho |
| `getEquipos` | `GET /logistica/equipos?q=&clase=&estado=` | Buscar equipos/herramientas |

### WebSocket
`ws(s)://<api>/ws/chat/servicio/{servicioId}?token=<jwt>` — chat + notificación `borrador_actualizado`.

---

## 10. CICLO COMPLETO DE UN REQUERIMIENTO DE MATERIAL (estados)

Este es el flujo extremo-a-extremo que cruza Operaciones ↔ Logística ↔ Compras:

```
1. [Operaciones · Equipo en campo] Técnico abre Modal 3 y agrega ítems al BORRADOR
   (material de stock / equipo del inventario / compra externa).
   → Borrador compartido en tiempo real con todo el equipo (WS borrador_actualizado).

2. [Operaciones] Un solo técnico marca CONSENSO y pulsa "Enviar a Logística"
   → POST .../borrador/enviar → nace un REQUERIMIENTO (estado: 'pendiente').

3. [Logística · RequerimientosComponent] Logístico abre "Revisión":
   - Sugerencia automática por ítem: en stock → 'aprobar'; sin stock/compra → 'compra'.
   - Decide por ítem: aprobar (de stock) | compra (externa) | rechazar.
   - confirmarAprobacion() → POST .../aprobar → estado: 'aprobado'. Stock se descuenta.
   - (o rechazarRequerimiento → 'rechazado' con motivo).

4. [Operaciones · banner HU-16] El requerimiento aprobado aparece en "Materiales
   listos para firmar". Técnico líder/jefe FIRMA la recepción (canvas)
   → POST .../firmar → 'listo' (firmado, esperando despacho). Logística notificada.

5. [Logística] entregar() → POST .../entregar → 'entregado'.
   Los ítems entregados ya no son editables (puedeEditar=false).

6. [Compras (HU-17)] Ítems marcados 'para_compra' generan TicketCompra
   → proveedores, precios, factura → 'completado'.
```

**Estados del requerimiento:** `pendiente → aprobado → listo → entregado` (o `rechazado`).
**Estados por ítem:** `pendiente | aprobado (de stock) | para_compra | rechazado`.

---

## 11. MATRIZ DE PERMISOS (rol → acción)

| Acción | Jefe Operaciones / Admin | Técnico |
|---|---|---|
| Ver detalle servicio | ✓ | ✓ |
| Iniciar servicio (si checklist OK) | ✓ | ✓ |
| Completar tareas / subir evidencia | ✓ | ✓ |
| Agregar materiales al borrador | ✓ | ✓ |
| Enviar borrador a Logística (con consenso) | ✓ | ✓ |
| Firmar recepción de materiales | ✓ | ✓ (recomendado líder/jefe) |
| Chat: mensajes privados a un miembro | ✓ | ✗ (solo "Todos") |
| Crear comunicados | ✓ | ✗ |
| **Finalizar y cerrar servicio** | ✓ | ✗ (candado explícito) |
| Configurar equipo + cronograma | ✓ | (según UI; botón visible salvo Completado/Cancelado) |

Flag: `soyJefeOperaciones = rol ∈ {jefe_operaciones, administrador}` (de `localStorage.ezyro_user`).

---

## 12. PRECAUCIONES / REGLAS DE NEGOCIO A PRESERVAR EN MÓVIL (resumen ejecutivo)

1. **Borrador compartido + consenso + envío único** → evita compras duplicadas por error humano. Sincronización en tiempo real obligatoria.
2. **Checklist de Fase 1 bloquea el inicio** → no se puede iniciar sin equipo + tareas con responsable + materiales gestionados.
3. **Solo Jefatura finaliza** → candado de cierre. Y solo al 100% de tareas.
4. **Ítems aprobados/entregados son inmutables** (`puedeEditar`).
5. **Firma de recepción** cierra el handshake con Logística (canvas, ya soporta touch).
6. **Validación de cruce de horarios** al asignar técnicos a tareas (HU-13).
7. **Alerta de grupo** al tomar un técnico que ya pertenece a otro grupo activo (HU-13).
8. **Evidencias por etapa** (antes/durante/después); subir evidencia auto-completa la tarea.
9. **Estado Completado = solo lectura total.**
10. **Equipos Intervenidos sigue con datos MOCK** — no productivo aún.
11. **Fuente única de verdad de fases** (`fase-servicio.ts`) compartida entre vistas.

---

## 13. RECOMENDACIONES PARA LA IMPLEMENTACIÓN MÓVIL

- **Reutilizar la utilidad de fases** como código puro en Dart (`fase_servicio.dart`) — espejo exacto de `faseActiva`/`faseClase`.
- **Mantener los mismos endpoints y nombres de estado** (snake_case del backend) para no fragmentar la lógica.
- **Tiempo real:** ya hay base (`syncCompletedNotifier` + FCM, memoria `ezyro-realtime`). Para el borrador y el chat, conectar al WebSocket `/ws/chat/servicio/{id}` o, mínimo, refrescar el borrador al recibir FCM `borrador_actualizado`.
- **PDF del informe:** mover la generación al backend (`GET …/informe.pdf`) en lugar de replicar pdf-lib en Dart — un solo formato de verdad.
- **Offline-first ya cubre evidencias** (memoria `ezyro-offline-first`): extender el mismo patrón de cola al borrador de materiales y al toggle de tareas.
- **Respetar la matriz de permisos** (§11) ocultando/deshabilitando botones según `rol`.

---

*Documento generado a partir del análisis directo del código de `E-zyro-frontend`. Próximo paso sugerido: con esta guía, derivar el plan de implementación pantalla por pantalla en el app Flutter (`E-zyro-app`).*
