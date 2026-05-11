# DATABASE CONTEXT — Sistema de Gestión de Servicios de Campo

> **Uso:** Adjuntar este archivo como contexto al inicio de cualquier prompt con Claude Code que involucre esta base de datos. Contiene toda la información necesaria para generar queries, endpoints, migraciones y lógica de negocio correctos.

---

## Metadata del Sistema

| Campo | Valor |
|---|---|
| Motor | PostgreSQL 18.x |
| Extensión requerida | `uuid-ossp` |
| Total de tablas | **82** |
| Patrón de IDs | `UUID v4` en todas las tablas (via `uuid_generate_v4()`) |
| Multi-tenancy | `empresa_id UUID` presente en casi todas las tablas |
| Archivos | Imágenes y documentos almacenados en **Cloudinary** (`url_cloudinary` + `public_id_cloudinary`) |
| Fechas | `TIMESTAMP WITHOUT TIME ZONE` + `DATE` según el caso |
| Auditoría | Tabla `auditoria` global con `JSONB` para diff de datos |

---

## Arquitectura por Módulos

```
01. CORE EMPRESARIAL         → empresa, plan_suscripcion, suscripcion
02. AUTENTICACIÓN Y ACCESO   → usuario, usuario_cliente, sesion_usuario, recuperacion_password,
                               rol, permiso, rol_permiso, usuario_rol, usuario_permiso
03. RECURSOS HUMANOS         → empleado, contrato, documento_laboral, solicitud_laboral,
                               firma_digital, historial_firma, documento_firmado,
                               dispositivo_push, notificacion, turno, turno_empleado,
                               criterio_evaluacion, evaluacion, detalle_evaluacion,
                               categoria_habilidad, habilidad, empleado_habilidad
04. ASISTENCIA Y BIOMETRÍA   → foto_biometrica, registro_asistencia,
                               geolocalizacion_asistencia, foto_asistencia
05. GRUPOS DE TRABAJO        → grupo_trabajo, grupo_miembro
06. CLIENTES Y CONTRATOS     → cliente, contrato_comercial, usuario_cliente
07. EQUIPOS Y ACTIVOS        → tipo_equipo, equipo, plan_mantenimiento,
                               orden_mantenimiento, evidencia_mantenimiento, informe_tecnico
08. LOGÍSTICA E INVENTARIO   → almacen, categoria_material, material, stock,
                               movimiento_inventario, proveedor, proveedor_categoria,
                               orden_compra, detalle_compra, recepcion_compra, recepcion_detalle
09. PROYECTOS Y OPERACIONES  → catalogo_servicio, proyecto, proyecto_detalle, proyecto_grupo,
                               fase, proyecto_servicio, procedimiento, evidencia_procedimiento,
                               proyecto_equipo, proyecto_miembro, requerimiento,
                               requerimiento_detalle, requerimiento_entrega,
                               seguimiento_proyecto, calificacion_cliente
10. DOCUMENTACIÓN Y PLANOS   → carpeta_documental, plano, version_plano
11. COMUNICACIÓN             → programacion_campo, programacion_empleado,
                               mensaje_chat, adjunto_mensaje, lectura_mensaje
12. FINANZAS                 → caja_chica, movimiento_caja, recordatorio, recordatorio_destinatario
13. AUDITORÍA GLOBAL         → auditoria
```

---

## Jerarquía Operativa Central

```
empresa  (la empresa prestadora de servicios)
  └── cliente  (empresa solicitante del servicio)
        └── contrato_comercial  (acuerdo formal)
              └── proyecto  (conjunto de trabajos)
                    ├── fase  (etapa temporal: Planificación / Ejecución / Cierre)
                    ├── proyecto_servicio  (servicio específico: Mantenimiento POZO, CCTV, etc.)
                    │     └── procedimiento  (paso técnico: Inspección, Desmontaje, Instalación)
                    │           └── evidencia_procedimiento  (fotos antes/durante/después)
                    ├── proyecto_miembro  (empleados asignados al proyecto)
                    ├── proyecto_grupo  (grupos de trabajo asignados)
                    ├── proyecto_equipo  (equipos/activos en el proyecto)
                    ├── requerimiento  → requerimiento_detalle → requerimiento_entrega
                    ├── seguimiento_proyecto
                    └── calificacion_cliente
```

**% de avance del proyecto** se calcula como:
```sql
SELECT
  COUNT(*) FILTER (WHERE estado = 'Completado')::decimal / COUNT(*) * 100
FROM proyecto_servicio
WHERE proyecto_id = $1;
```

---

## Patrones de Diseño Importantes

### 1. Multi-tenancy por empresa_id
Toda consulta debe filtrar por `empresa_id`. No existe aislamiento a nivel de schema, se usa discriminador de columna.

```sql
-- SIEMPRE incluir empresa_id en WHERE
SELECT * FROM proyecto WHERE empresa_id = $empresa_id AND id = $id;
```

### 2. Soft Delete
Las entidades principales tienen columna `activo BOOLEAN`. No se borran físicamente.
```sql
UPDATE empleado SET activo = FALSE WHERE id = $id;
-- Siempre filtrar: WHERE activo = TRUE
```

### 3. Cloudinary Storage
Todo archivo/imagen tiene dos columnas:
- `url_cloudinary VARCHAR(500)` — URL pública para mostrar
- `public_id_cloudinary VARCHAR(255)` — ID para eliminar vía API de Cloudinary

### 4. Relaciones Polimórficas
`movimiento_inventario` usa patrón polimórfico:
```
referencia_id   UUID    → ID del origen
referencia_tipo VARCHAR → 'requerimiento' | 'orden_compra' | 'ajuste_manual'
```

### 5. RBAC (Control de Acceso por Roles)
```
usuario → usuario_rol → rol → rol_permiso → permiso(modulo, accion)
usuario → usuario_permiso → permiso  ← permisos directos (excepción)
```

### 6. Asistencia Biométrica con IA
```
foto_biometrica (foto_base, subida 1 vez al registrar usuario)
     ↓ comparada con
foto_asistencia.url_cloudinary (foto_selfie al marcar asistencia)
     ↓ resultado en
foto_asistencia.similitud_ia   DECIMAL(5,4)  → 0.0000 a 1.0000
foto_asistencia.resultado      → 'aprobado' | 'rechazado' | 'revision_manual' | 'pendiente'
```

---

## Módulo 01 — Core Empresarial

### `empresa`
La entidad raíz del sistema. Toda otra tabla depende de ella.

| Columna | Tipo | Nulo | Default | Descripción |
|---|---|---|---|---|
| `id` | UUID | NO | uuid_generate_v4() | **PK** |
| `razon_social` | VARCHAR(200) | NO | — | Nombre legal |
| `ruc` | VARCHAR(20) | NO | — | **UNIQUE** |
| `email_contacto` | VARCHAR(150) | NO | — | |
| `telefono` | VARCHAR(20) | SÍ | — | |
| `logo_url` | VARCHAR(500) | SÍ | — | |
| `slug` | VARCHAR(100) | NO | — | **UNIQUE**, para URLs |
| `estado` | VARCHAR(20) | NO | `'activo'` | CHECK: `activo` `inactivo` `suspendido` |
| `fecha_registro` | TIMESTAMP | NO | NOW() | |
| `created_at` | TIMESTAMP | NO | NOW() | |
| `updated_at` | TIMESTAMP | SÍ | — | |

### `plan_suscripcion`
Planes del SaaS. `max_usuarios = 9999` significa ilimitado.

| Columna | Tipo | Nulo | Default | Descripción |
|---|---|---|---|---|
| `id` | UUID | NO | uuid_generate_v4() | **PK** |
| `nombre` | VARCHAR(100) | NO | — | Ej: 'Starter', 'Pro', 'Enterprise' |
| `max_usuarios` | INT | NO | — | 9999 = sin límite |
| `max_proyectos` | INT | SÍ | — | NULL = sin límite |
| `precio_mensual` | DECIMAL(10,2) | NO | — | |
| `descripcion` | TEXT | SÍ | — | |
| `activo` | BOOLEAN | NO | TRUE | |

### `suscripcion`
Vínculo activo entre empresa y plan.

| Columna | Tipo | Nulo | FK | Descripción |
|---|---|---|---|---|
| `id` | UUID | NO | — | **PK** |
| `empresa_id` | UUID | NO | → empresa.id | |
| `plan_id` | UUID | NO | → plan_suscripcion.id | |
| `fecha_inicio` | DATE | NO | — | |
| `fecha_fin` | DATE | SÍ | — | NULL = indefinido |
| `estado` | VARCHAR(20) | NO | `'activa'` | CHECK: `activa` `vencida` `cancelada` `suspendida` |
| `created_at` | TIMESTAMP | NO | NOW() | |

---

## Módulo 02 — Autenticación y Control de Acceso

### `usuario`
Usuarios internos del sistema (empleados de la empresa prestadora).

| Columna | Tipo | Nulo | Restricciones | Descripción |
|---|---|---|---|---|
| `id` | UUID | NO | PK | |
| `empresa_id` | UUID | NO | FK → empresa.id | |
| `nombre` | VARCHAR(100) | NO | — | |
| `apellido` | VARCHAR(100) | NO | — | |
| `email` | VARCHAR(150) | NO | UNIQUE(empresa_id, email) | |
| `username` | VARCHAR(50) | NO | UNIQUE(empresa_id, username) | |
| `password_hash` | VARCHAR(255) | NO | — | bcrypt |
| `telefono` | VARCHAR(20) | SÍ | — | |
| `foto_url` | VARCHAR(500) | SÍ | — | URL genérica de perfil |
| `activo` | BOOLEAN | NO | DEFAULT TRUE | |
| `email_verificado` | BOOLEAN | NO | DEFAULT FALSE | |
| `ultimo_acceso` | TIMESTAMP | SÍ | — | |
| `created_at` | TIMESTAMP | NO | NOW() | |
| `updated_at` | TIMESTAMP | SÍ | — | |

> **Nota:** `foto_url` es foto de perfil general. La foto biométrica para asistencia está en tabla `foto_biometrica`.

### `usuario_cliente`
Acceso de representantes de la empresa cliente al portal de seguimiento. **Autenticación separada** de `usuario`.

| Columna | Tipo | Nulo | FK | Descripción |
|---|---|---|---|---|
| `id` | UUID | NO | — | **PK** |
| `cliente_id` | UUID | NO | → cliente.id | |
| `empresa_id` | UUID | NO | → empresa.id | |
| `nombre` | VARCHAR(100) | NO | — | |
| `apellido` | VARCHAR(100) | NO | — | |
| `email` | VARCHAR(150) | NO | **UNIQUE global** | |
| `password_hash` | VARCHAR(255) | NO | — | |
| `cargo` | VARCHAR(100) | SÍ | — | |
| `activo` | BOOLEAN | NO | TRUE | |
| `ultimo_acceso` | TIMESTAMP | SÍ | — | |
| `created_at` | TIMESTAMP | NO | NOW() | |
| `updated_at` | TIMESTAMP | SÍ | — | |

### `sesion_usuario`
Tokens de sesión activos. `ON DELETE CASCADE` cuando se elimina usuario.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `usuario_id` | UUID | NO | FK → usuario.id (CASCADE) |
| `token_hash` | VARCHAR(255) | NO | Hash del JWT/token |
| `dispositivo` | VARCHAR(100) | SÍ | |
| `ip` | VARCHAR(45) | SÍ | IPv4 e IPv6 |
| `user_agent` | VARCHAR(255) | SÍ | |
| `activa` | BOOLEAN | NO | DEFAULT TRUE |
| `fecha_expiracion` | TIMESTAMP | NO | |
| `created_at` | TIMESTAMP | NO | NOW() |

### `recuperacion_password`
OTP/código para reset de contraseña. Historial completo.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `usuario_id` | UUID | NO | FK → usuario.id (CASCADE) |
| `codigo_hash` | VARCHAR(255) | NO | bcrypt del código OTP |
| `intentos_fallidos` | INT | NO | DEFAULT 0 |
| `usado` | BOOLEAN | NO | DEFAULT FALSE |
| `ip_solicitud` | VARCHAR(45) | SÍ | |
| `fecha_expiracion` | TIMESTAMP | NO | |
| `created_at` | TIMESTAMP | NO | NOW() |

### `rol`
Roles por empresa. `es_rol_sistema = TRUE` indica roles predefinidos no editables.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `empresa_id` | UUID | NO | FK → empresa.id |
| `nombre` | VARCHAR(100) | NO | UNIQUE(empresa_id, nombre) |
| `descripcion` | VARCHAR(255) | SÍ | |
| `es_rol_sistema` | BOOLEAN | NO | DEFAULT FALSE |
| `created_at` | TIMESTAMP | NO | NOW() |
| `updated_at` | TIMESTAMP | SÍ | |

**Roles del sistema:** `Técnico de Campo`, `Supervisor de Campo`, `Jefe de Operaciones`, `Logística`, `Recursos Humanos`, `Administrador`, `SuperAdmin`

### `permiso`
Catálogo global de permisos por módulo y acción. UNIQUE(modulo, accion).

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | UUID | **PK** |
| `modulo` | VARCHAR(100) | Ej: `OPERACIONES`, `LOGISTICA`, `PERSONAL`, `ASISTENCIA`, `ADMIN`, `AUDITORIA` |
| `accion` | VARCHAR(50) | Ej: `VER`, `CREAR`, `EDITAR`, `GESTIONAR`, `VALIDAR`, `COMPRAS` |
| `descripcion` | VARCHAR(255) | |

### `rol_permiso`
Tabla puente muchos-a-muchos. PK compuesta (rol_id, permiso_id). CASCADE en ambos lados.

### `usuario_rol`
Asignación de roles a usuarios. Un usuario puede tener múltiples roles.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `usuario_id` | UUID | NO | FK → usuario.id (CASCADE) |
| `rol_id` | UUID | NO | FK → rol.id |
| `empresa_id` | UUID | NO | FK → empresa.id |
| `asignado_por` | UUID | SÍ | FK → usuario.id |
| `created_at` | TIMESTAMP | NO | NOW() |

UNIQUE(usuario_id, rol_id, empresa_id)

### `usuario_permiso`
Permisos directos a usuarios (excepción al sistema de roles). PK compuesta.

---

## Módulo 03 — Recursos Humanos

### `empleado`
Perfil laboral del usuario. Relación 1:1 con `usuario` (UNIQUE usuario_id).

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `usuario_id` | UUID | NO | FK → usuario.id — **UNIQUE** |
| `empresa_id` | UUID | NO | FK → empresa.id |
| `codigo` | VARCHAR(50) | SÍ | UNIQUE(empresa_id, codigo). Ej: 'TEC-001' |
| `cargo` | VARCHAR(100) | NO | Ej: 'Técnico de Campo' |
| `area` | VARCHAR(100) | SÍ | |
| `tipo` | VARCHAR(20) | NO | CHECK: `planilla` `recibo_honorarios` `practicante` `contrato` |
| `fecha_ingreso` | DATE | NO | |
| `fecha_fin_contrato` | DATE | SÍ | |
| `dias_aviso_vencimiento` | INT | SÍ | DEFAULT 7 |
| `activo` | BOOLEAN | NO | DEFAULT TRUE |
| `created_at` | TIMESTAMP | NO | NOW() |
| `updated_at` | TIMESTAMP | SÍ | |

> **Relación clave:** Para obtener datos completos de un trabajador: `JOIN empleado ON usuario.id = empleado.usuario_id`

### `contrato` *(laboral)*
Contrato de trabajo empleado-empresa (NO confundir con `contrato_comercial`).

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | UUID | **PK** |
| `empleado_id` | UUID | FK → empleado.id |
| `empresa_id` | UUID | FK → empresa.id |
| `tipo` | VARCHAR(50) | Tipo de contrato |
| `fecha_inicio` | DATE | |
| `fecha_fin` | DATE | SÍ — NULL si indefinido |
| `estado` | VARCHAR(20) | CHECK: `vigente` `vencido` `rescindido` `renovado` |
| `documento_url` | VARCHAR(500) | Cloudinary URL |
| `public_id_cloudinary` | VARCHAR(255) | Para eliminar en Cloudinary |
| `created_at` / `updated_at` | TIMESTAMP | |

### `documento_laboral`
Documentos personales del empleado (boletas, certificados, etc.).

| Columna | Tipo | Descripción |
|---|---|---|
| `tipo` | VARCHAR(50) | CHECK: `boleta` `contrato` `certificado_medico` `certificacion` `otro` |
| `nombre` | VARCHAR(200) | Nombre descriptivo del documento |
| `url_archivo` | VARCHAR(500) | Cloudinary URL |
| `public_id_cloudinary` | VARCHAR(255) | |
| `fecha_emision` | DATE | |

### `solicitud_laboral`
Solicitudes de los empleados a RRHH (justificaciones, permisos, vacaciones).

| Columna | Tipo | Descripción |
|---|---|---|
| `tipo` | VARCHAR(50) | CHECK: `justificacion_falta` `permiso` `vacaciones` `adelanto` `otro` |
| `estado` | VARCHAR(20) | CHECK: `pendiente` `aprobada` `rechazada` `anulada` |
| `aprobado_por` | UUID | FK → empleado.id |
| `fecha_aprobacion` | TIMESTAMP | SÍ |

### `firma_digital`
Firma manuscrita digitalizada del usuario. 1:1 con usuario (UNIQUE usuario_id). Se guarda historial al cambiar.

### `historial_firma`
Cada vez que se reemplaza la firma, la anterior se mueve aquí con `reemplazada_en`.

### `documento_firmado`
Registro de qué documentos fueron firmados, cuándo y desde qué IP. `tabla_documento` es polimórfico.

### `dispositivo_push`
Tokens FCM/APNs para notificaciones push.

| `plataforma` | CHECK: `android` `ios` `web` |

### `notificacion`
Centro de notificaciones del sistema.

| Columna | Descripción |
|---|---|
| `tipo` | Ej: `Aviso`, `Alerta`, `Sistema` |
| `categoria` | Subcategoría opcional |
| `leido` | BOOLEAN — DEFAULT FALSE |
| `enviado` | BOOLEAN — si fue enviada vía push |
| `referencia_tabla` | Tabla origen de la notificación (polimórfico) |
| `referencia_id` | ID del registro origen |

### `turno` / `turno_empleado`
Gestión de horarios. Un empleado puede tener múltiples turnos históricos (usar `activo = TRUE` para el vigente).

### `evaluacion` / `detalle_evaluacion` / `criterio_evaluacion`
Sistema de evaluación de desempeño por criterios ponderados.

| `criterio_evaluacion.peso` | DECIMAL(5,2) — CHECK: peso > 0 AND peso <= 100 |
| `detalle_evaluacion.puntaje` | INT — CHECK: BETWEEN 1 AND 10 |
| `evaluacion.estado` | CHECK: `borrador` `enviada` `completada` |

### `empleado_habilidad`
Habilidades certificadas de cada empleado. UNIQUE(empleado_id, habilidad_id).

| `nivel` | CHECK: `basico` `intermedio` `avanzado` `experto` |

---

## Módulo 04 — Asistencia y Biometría

### `foto_biometrica`
Foto base del empleado para comparación IA. Se sube **una sola vez** al registrarse.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | UUID | **PK** |
| `usuario_id` | UUID | FK → usuario.id |
| `empresa_id` | UUID | FK → empresa.id |
| `url_cloudinary` | VARCHAR(500) | URL de la foto base |
| `public_id_cloudinary` | VARCHAR(255) | |
| `activa` | BOOLEAN | DEFAULT TRUE — solo una activa por usuario |
| `created_at` | TIMESTAMP | NOW() |

**Índice:** `idx_foto_biometrica_usuario ON foto_biometrica(usuario_id, activa)`

### `registro_asistencia`
Marcación de entrada/salida. Vinculado opcionalmente al proyecto activo.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `empresa_id` | UUID | NO | FK → empresa.id |
| `empleado_id` | UUID | NO | FK → empleado.id |
| `proyecto_id` | UUID | SÍ | FK → proyecto.id — proyecto activo al marcar |
| `proyecto_servicio_id` | UUID | SÍ | FK → proyecto_servicio.id — servicio específico |
| `tipo` | VARCHAR(30) | NO | CHECK: `entrada` `salida` `entrada_almuerzo` `salida_almuerzo` |
| `fecha_hora` | TIMESTAMP | NO | Momento exacto del registro |
| `estado` | VARCHAR(20) | NO | CHECK: `pendiente` `validado` `rechazado` `justificado` |
| `observacion` | VARCHAR(500) | SÍ | |
| `validado_por` | UUID | SÍ | FK → empleado.id (supervisor) |
| `fecha_validacion` | TIMESTAMP | SÍ | |
| `created_at` | TIMESTAMP | NO | NOW() |

**Índice:** `idx_registro_asistencia_emp ON registro_asistencia(empleado_id, fecha_hora DESC)`

### `geolocalizacion_asistencia`
Coordenadas GPS al momento del registro. 1:1 con registro_asistencia (UNIQUE registro_id).

| Columna | Tipo | Descripción |
|---|---|---|
| `latitud` | DECIMAL(10,8) | 8 decimales de precisión |
| `longitud` | DECIMAL(11,8) | 8 decimales de precisión |
| `precision_m` | FLOAT | Precisión en metros del GPS |
| `altitud` | FLOAT | SÍ |

### `foto_asistencia`
Selfie tomada al marcar asistencia. Resultado de la comparación IA. 1:1 con registro.

| Columna | Tipo | Descripción |
|---|---|---|
| `registro_id` | UUID | FK → registro_asistencia.id — **UNIQUE** (CASCADE) |
| `foto_base_id` | UUID | FK → foto_biometrica.id — foto usada para comparar |
| `url_cloudinary` | VARCHAR(500) | URL de la selfie |
| `public_id_cloudinary` | VARCHAR(255) | |
| `similitud_ia` | DECIMAL(5,4) | Score IA: 0.0000–1.0000. CHECK: NULL o entre 0 y 1 |
| `resultado` | VARCHAR(20) | CHECK: `aprobado` `rechazado` `revision_manual` `pendiente` |
| `fecha_captura` | TIMESTAMP | |

---

## Módulo 05 — Grupos de Trabajo

### `grupo_trabajo`
Equipo de trabajo con un jefe asignado.

| Columna | Tipo | Descripción |
|---|---|---|
| `jefe_id` | UUID | FK → empleado.id |
| `activo` | BOOLEAN | DEFAULT TRUE |

### `grupo_miembro`
Miembros del grupo. UNIQUE(grupo_id, empleado_id). Soft-delete con `activo`.

---

## Módulo 06 — Clientes y Contratos Comerciales

### `cliente`
Empresa cliente que solicita los servicios.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | UUID | **PK** |
| `empresa_id` | UUID | FK → empresa.id (empresa prestadora) |
| `razon_social` | VARCHAR(200) | |
| `ruc` | VARCHAR(20) | SÍ |
| `contacto` / `telefono` / `email` / `direccion` | — | SÍ |
| `activo` | BOOLEAN | DEFAULT TRUE |

### `contrato_comercial`
Acuerdo entre empresa prestadora y cliente. **Distinto** de `contrato` (laboral).

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | UUID | **PK** |
| `cliente_id` | UUID | FK → cliente.id |
| `empresa_id` | UUID | FK → empresa.id |
| `numero_contrato` | VARCHAR(100) | UNIQUE(empresa_id, numero_contrato) |
| `fecha_inicio` | DATE | |
| `fecha_fin` | DATE | SÍ — NULL si indefinido |
| `monto_total` | DECIMAL(12,2) | SÍ |
| `estado` | VARCHAR(20) | CHECK: `borrador` `vigente` `vencido` `rescindido` |
| `descripcion` | TEXT | SÍ |
| `documento_url` | VARCHAR(500) | SÍ — Cloudinary |
| `public_id_cloudinary` | VARCHAR(255) | SÍ |
| `creado_por` | UUID | FK → usuario.id |
| `created_at` / `updated_at` | TIMESTAMP | |

---

## Módulo 07 — Equipos y Activos

### `tipo_equipo`
Catálogo de tipos de equipos con procedimientos técnicos asociados.

### `equipo`
Activo físico. Puede estar asignado a cliente o a proyecto.

| Columna | Tipo | Descripción |
|---|---|---|
| `tipo_equipo_id` | UUID | FK → tipo_equipo.id |
| `proyecto_id` | UUID | SÍ — FK → proyecto.id |
| `cliente_id` | UUID | SÍ — FK → cliente.id |
| `tipo_asignacion` | VARCHAR(20) | CHECK: `activo_cliente` `proyecto` |
| `estado` | VARCHAR(20) | CHECK: `operativo` `en_mantenimiento` `fuera_de_servicio` `baja` |

> Si `tipo_asignacion = 'proyecto'`: usar `proyecto_id`. Si `'activo_cliente'`: usar `cliente_id`.

### `plan_mantenimiento`
Plan recurrente para un equipo.

| `tipo` | CHECK: `preventivo` `correctivo` `predictivo` |

### `orden_mantenimiento`
Ejecución puntual de mantenimiento.

| `tipo` | CHECK: `preventivo` `correctivo` `predictivo` |
| `estado` | CHECK: `pendiente` `en_proceso` `completado` `cancelado` |

### `evidencia_mantenimiento`
Fotos por etapa de la orden de mantenimiento.

| `etapa` | CHECK: `antes` `durante` `despues` |

---

## Módulo 08 — Logística e Inventario

### `almacen`
Ubicación física del inventario. Reemplaza el campo `almacen VARCHAR` anterior (3FN fix).

| `responsable_id` | UUID SÍ | FK → empleado.id |

### `categoria_material`
Categorías para clasificar materiales por empresa.

### `material`
Ítem de inventario con unidad de medida.

### `stock`
Stock actual por material por almacén. **PK compuesta:** (material_id, empresa_id, almacen_id).

| Columna | Tipo | Descripción |
|---|---|---|
| `material_id` | UUID | FK → material.id |
| `empresa_id` | UUID | FK → empresa.id |
| `almacen_id` | UUID | FK → almacen.id |
| `cantidad` | INT | DEFAULT 0 — CHECK: >= 0 |
| `cantidad_minima` | INT | DEFAULT 0 — umbral de alerta |
| `updated_at` | TIMESTAMP | DEFAULT NOW() |

**Query de stock bajo mínimo:**
```sql
SELECT m.nombre, s.cantidad, s.cantidad_minima, a.nombre as almacen
FROM stock s
JOIN material m ON m.id = s.material_id
JOIN almacen a ON a.id = s.almacen_id
WHERE s.empresa_id = $1 AND s.cantidad < s.cantidad_minima;
```

### `movimiento_inventario`
Trazabilidad completa de entradas/salidas. `referencia_id` + `referencia_tipo` es polimórfico.

| `tipo` | CHECK: `entrada` `salida` `ajuste` `requerimiento` `transferencia` `compra` |
| `cantidad` | INT — CHECK: != 0 (negativo = salida, positivo = entrada) |
| `referencia_tipo` | `'requerimiento'` `'orden_compra'` `'ajuste_manual'` |

### `proveedor`
Contacto de proveedores de materiales.

### `proveedor_categoria`
Muchos-a-muchos: proveedor suministra categorías de material. PK compuesta.

### `orden_compra`
Pedido formal a proveedor. Puede originarse de un requerimiento.

| `estado` | CHECK: `borrador` `enviada` `confirmada` `en_transito` `recibida` `cancelada` |
| `requerimiento_id` | UUID SÍ | FK → requerimiento.id — origen del pedido |

### `detalle_compra`
Ítems de la orden de compra. `ON DELETE CASCADE` desde orden_compra.

### `recepcion_compra`
Registro formal de recepción de materiales con responsable y almacén destino.

| `estado` | CHECK: `completa` `parcial` `con_diferencias` |
| `almacen_id` | UUID | FK → almacen.id — dónde se reciben los materiales |

### `recepcion_detalle`
Detalle por ítem recibido vs esperado.

| `estado_item` | CHECK: `completo` `parcial` `faltante` `danado` |

---

## Módulo 09 — Proyectos y Operaciones

### `catalogo_servicio`
Tipos de servicios que ofrece la empresa. Master data.

| `tipo_trabajo` | Ej: `'ELÉCTRICO'`, `'TELECOMUNICACIONES'`, `'CIVIL'` |

### `proyecto`
Entidad central del negocio. Contiene múltiples servicios.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `empresa_id` | UUID | NO | FK → empresa.id |
| `cliente_id` | UUID | NO | FK → cliente.id |
| `contrato_comercial_id` | UUID | SÍ | FK → contrato_comercial.id |
| `orden_trabajo` | VARCHAR(50) | NO | UNIQUE(empresa_id, orden_trabajo). Ej: 'S2026-080' |
| `jefe_operaciones_id` | UUID | NO | FK → empleado.id |
| `nombre_proyecto` | VARCHAR(200) | NO | |
| `estado` | VARCHAR(30) | NO | CHECK: `Pendiente` `En_Proceso` `En_Pausa` `Completado` `Cancelado` |
| `fecha_inicio` | DATE | SÍ | |
| `fecha_fin_estimada` | DATE | SÍ | |
| `fecha_fin_real` | DATE | SÍ | |
| `created_at` / `updated_at` | TIMESTAMP | | |

**Índices:** `idx_proyecto_empresa`, `idx_proyecto_cliente`, `idx_proyecto_estado(empresa_id, estado)`

### `proyecto_detalle`
Información extendida del proyecto. PK = proyecto_id (1:1 con CASCADE).

| Columna | Descripción |
|---|---|
| `zona_ejecucion` | Lugar físico |
| `alcance` | TEXT NOT NULL — descripción del trabajo |
| `orden_compra_cliente` | Nro de OC del cliente |
| `tipo_documento_cliente` | Ej: 'Orden de Servicio' |
| `nro_documento` | |
| `nro_conformidad` | DEFAULT 'En Espera' |
| `acta_url` | Cloudinary — acta de conformidad |
| `public_id_cloudinary` | |

### `proyecto_grupo`
Muchos-a-muchos proyecto-grupo_trabajo. PK compuesta (proyecto_id, grupo_id).

### `fase`
Etapas temporales del proyecto (Planificación → Ejecución → Cierre).

| Columna | Tipo | Descripción |
|---|---|---|
| `proyecto_id` | UUID | FK → proyecto.id |
| `nombre` | VARCHAR(150) | Ej: 'Planificación', 'Ejecución', 'Cierre' |
| `orden` | INT | Número secuencial |
| `estado` | VARCHAR(20) | CHECK: `pendiente` `en_proceso` `completada` `cancelada` |
| `fecha_inicio` / `fecha_fin` | DATE | SÍ |

### `proyecto_servicio`
Un servicio específico dentro del proyecto. **Nodo central de la operación.**

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `id` | UUID | NO | **PK** |
| `proyecto_id` | UUID | NO | FK → proyecto.id |
| `empresa_id` | UUID | NO | FK → empresa.id |
| `catalogo_servicio_id` | UUID | NO | FK → catalogo_servicio.id — tipo de servicio |
| `fase_id` | UUID | SÍ | FK → fase.id — en qué fase del proyecto ocurre |
| `nombre` | VARCHAR(200) | NO | Ej: 'Mantenimiento de POZO' |
| `descripcion` | TEXT | SÍ | |
| `responsable_id` | UUID | SÍ | FK → empleado.id — técnico/supervisor líder |
| `orden` | INT | NO | DEFAULT 1 |
| `estado` | VARCHAR(30) | NO | CHECK: `Pendiente` `En_Proceso` `Completado` `Cancelado` |
| `fecha_programada` | DATE | SÍ | |
| `fecha_inicio` / `fecha_fin` | DATE | SÍ | |
| `created_at` / `updated_at` | TIMESTAMP | | |

### `procedimiento`
Paso técnico dentro de un servicio (renombrado de `tarea`).

| Columna | Tipo | Descripción |
|---|---|---|
| `proyecto_servicio_id` | UUID | FK → proyecto_servicio.id |
| `responsable_id` | UUID SÍ | FK → empleado.id |
| `nombre` | VARCHAR(200) | Ej: 'Inspección visual del tablero' |
| `orden` | INT | DEFAULT 1 — secuencia dentro del servicio |
| `estado` | VARCHAR(20) | CHECK: `pendiente` `en_proceso` `completado` `bloqueado` |
| `fecha_limite` | DATE | SÍ |

### `evidencia_procedimiento`
Fotos tomadas por el técnico en campo. Vinculada al procedimiento específico.

| Columna | Tipo | Descripción |
|---|---|---|
| `procedimiento_id` | UUID | FK → procedimiento.id |
| `proyecto_servicio_id` | UUID | FK → proyecto_servicio.id |
| `proyecto_id` | UUID | FK → proyecto.id |
| `subido_por` | UUID | FK → empleado.id |
| `url_cloudinary` | VARCHAR(500) | |
| `public_id_cloudinary` | VARCHAR(255) | |
| `etapa` | VARCHAR(20) | CHECK: `antes` `durante` `despues` |
| `descripcion` | VARCHAR(500) | SÍ |
| `fecha_captura` | TIMESTAMP | |

### `proyecto_miembro`
Empleados asignados al proyecto. UNIQUE(proyecto_id, empleado_id).

| `rol_proyecto` | VARCHAR(50) | Ej: 'Técnico', 'Supervisor', 'Jefe Técnico' |
| `activo` | BOOLEAN | DEFAULT TRUE — soft remove |

### `requerimiento`
Solicitud de materiales/herramientas desde campo, vinculada al contexto operativo.

| Columna | Tipo | Descripción |
|---|---|---|
| `proyecto_id` | UUID | FK → proyecto.id |
| `proyecto_servicio_id` | UUID SÍ | FK → proyecto_servicio.id — servicio que lo originó |
| `procedimiento_id` | UUID SÍ | FK → procedimiento.id — procedimiento que lo originó |
| `solicitante_id` | UUID | FK → empleado.id |
| `tipo` | VARCHAR(30) | CHECK: `material` `herramienta` `equipo_especial` |
| `estado` | VARCHAR(20) | CHECK: `pendiente` `aprobado` `rechazado` `entregado` `anulado` |
| `aprobado_por` | UUID SÍ | FK → empleado.id (supervisor) |

### `requerimiento_detalle`
Ítems del requerimiento con cantidades solicitadas y aprobadas.

### `requerimiento_entrega`
Registro firmado de la entrega física de materiales. 1:1 con requerimiento (UNIQUE).

| Columna | Tipo | Descripción |
|---|---|---|
| `requerimiento_id` | UUID | FK → requerimiento.id — **UNIQUE** |
| `entregado_por_id` | UUID | FK → empleado.id (logística) |
| `recibido_por_id` | UUID | FK → empleado.id (técnico) |
| `firma_receptor_url` | VARCHAR(500) | SÍ — Cloudinary |
| `firma_public_id` | VARCHAR(255) | SÍ |
| `fecha_entrega` | TIMESTAMP | |

### `seguimiento_proyecto`
Registro histórico de avance del proyecto (manual o calculado).

| `porcentaje_avance` | DECIMAL(5,2) — CHECK: BETWEEN 0 AND 100 |

### `calificacion_cliente`
NPS/rating del cliente al proyecto. 1 a 5.

| `puntaje` | INT — CHECK: BETWEEN 1 AND 5 |

---

## Módulo 10 — Documentación y Planos

### `carpeta_documental`
Sistema de carpetas jerárquico (auto-referencia con `padre_id`).

| `padre_id` | UUID SÍ | FK → carpeta_documental.id (auto-ref para subcarpetas) |

### `plano`
Documento técnico/plano asociado a un proyecto.

### `version_plano`
Control de versiones de cada plano. `es_version_activa = TRUE` marca la versión vigente.

---

## Módulo 11 — Comunicación y Programación

### `programacion_campo`
Planificación de despliegue de personal en obra.

| `cantidad_personas` | INT SÍ | Estimado de personas necesarias |
| `confirmado` | BOOLEAN | DEFAULT FALSE |

### `programacion_empleado`
Empleados asignados a cada programación. UNIQUE(programacion_id, empleado_id).

| `confirmacion_movil` | BOOLEAN | El empleado confirmó desde la app |

### `mensaje_chat`
Chat por proyecto con soporte de hilos. `padre_id` auto-referencia para respuestas.

| Columna | Descripción |
|---|---|
| `padre_id` | UUID SÍ — FK → mensaje_chat.id (hilo/respuesta) |
| `contenido` | TEXT NOT NULL |
| `fecha` | TIMESTAMP — momento del mensaje |

### `adjunto_mensaje`
Múltiples archivos adjuntos por mensaje. `ON DELETE CASCADE` desde mensaje_chat.

### `lectura_mensaje`
Lectura por usuario. PK compuesta (mensaje_id, usuario_id). `ON DELETE CASCADE`.

---

## Módulo 12 — Finanzas

### `caja_chica`
Fondo de caja por proyecto o general.

| `estado` | CHECK: `abierta` `cerrada` `suspendida` |
| `monto_asignado_referencial` | DECIMAL(10,2) SÍ — referencial, no contable |

### `movimiento_caja`
Ingresos y egresos de caja.

| `tipo` | CHECK: `ingreso` `egreso` |
| `monto` | DECIMAL(10,2) — CHECK: > 0 (el tipo define si entra o sale) |

### `recordatorio`
Alertas programadas con soporte de recurrencia.

| Columna | Descripción |
|---|---|
| `estado` | CHECK: `activo` `vencido` `completado` `cancelado` |
| `recurrente` | BOOLEAN DEFAULT FALSE |
| `frecuencia_dias` | INT SÍ — cada cuántos días se repite |
| `dias_aviso` | INT DEFAULT 3 — con cuántos días de anticipación notificar |

### `recordatorio_destinatario`
A quién se envía el recordatorio. UNIQUE(recordatorio_id, usuario_id).

---

## Módulo 13 — Auditoría Global

### `auditoria`
Log inmutable de todas las acciones del sistema. Alta frecuencia de escritura.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | UUID | **PK** |
| `empresa_id` | UUID | SÍ — FK → empresa.id |
| `usuario_id` | UUID | SÍ — FK → usuario.id |
| `tabla_afectada` | VARCHAR(100) | Nombre de la tabla |
| `registro_id` | UUID | SÍ — ID del registro modificado |
| `accion` | VARCHAR(50) | CHECK: ver valores abajo |
| `modulo` | VARCHAR(100) | SÍ — módulo del sistema |
| `datos_anteriores` | **JSONB** | Estado antes del cambio |
| `datos_nuevos` | **JSONB** | Estado después del cambio |
| `ip` | VARCHAR(45) | IPv4/IPv6 |
| `user_agent` | VARCHAR(500) | |
| `descripcion` | VARCHAR(500) | |
| `fecha` | TIMESTAMP | DEFAULT NOW() |

**Valores permitidos en `accion`:**
```
INSERT | UPDATE | DELETE | LOGIN | LOGOUT | EXPORT | ACCESO_DENEGADO |
PASSWORD_RECOVERY_REQUEST | PASSWORD_RECOVERY_FAILED |
PASSWORD_RECOVERY_BLOCKED | PASSWORD_CHANGED_SUCCESS
```

**Query ejemplo — cambios en un registro:**
```sql
SELECT accion, datos_anteriores, datos_nuevos, fecha, ip
FROM auditoria
WHERE tabla_afectada = 'proyecto' AND registro_id = $1
ORDER BY fecha DESC;
```

**Índices de auditoría:**
- `idx_auditoria_empresa_fecha ON auditoria(empresa_id, fecha DESC)`
- `idx_auditoria_tabla ON auditoria(tabla_afectada, fecha DESC)`
- `idx_auditoria_datos_nuevos ON auditoria USING GIN (datos_nuevos)` ← para queries JSONB

---

## Todos los Índices del Sistema

| Índice | Tabla | Columnas | Uso |
|---|---|---|---|
| `idx_usuario_empresa` | usuario | empresa_id | Multi-tenant |
| `idx_empleado_empresa` | empleado | empresa_id | Multi-tenant |
| `idx_proyecto_empresa` | proyecto | empresa_id | Multi-tenant |
| `idx_proyecto_cliente` | proyecto | cliente_id | Filtro cliente |
| `idx_proyecto_estado` | proyecto | (empresa_id, estado) | Dashboard |
| `idx_proyecto_servicio_proy` | proyecto_servicio | proyecto_id | Servicios del proyecto |
| `idx_proyecto_servicio_estado` | proyecto_servicio | (proyecto_id, estado) | Avance |
| `idx_procedimiento_ps` | procedimiento | proyecto_servicio_id | Pasos del servicio |
| `idx_procedimiento_estado` | procedimiento | (proyecto_servicio_id, estado) | Completados |
| `idx_registro_asistencia_emp` | registro_asistencia | (empleado_id, fecha_hora DESC) | Historial |
| `idx_registro_asistencia_proy` | registro_asistencia | proyecto_id | Por proyecto |
| `idx_foto_biometrica_usuario` | foto_biometrica | (usuario_id, activa) | Login biométrico |
| `idx_movimiento_inv_material` | movimiento_inventario | (material_id, fecha DESC) | Trazabilidad |
| `idx_movimiento_inv_empresa` | movimiento_inventario | (empresa_id, fecha DESC) | Reportes |
| `idx_stock_almacen` | stock | almacen_id | Por ubicación |
| `idx_requerimiento_proyecto` | requerimiento | proyecto_id | Por proyecto |
| `idx_requerimiento_estado` | requerimiento | (empresa_id, estado) | Pendientes |
| `idx_requerimiento_solicitante` | requerimiento | solicitante_id | Por técnico |
| `idx_auditoria_empresa_fecha` | auditoria | (empresa_id, fecha DESC) | Log empresa |
| `idx_auditoria_tabla` | auditoria | (tabla_afectada, fecha DESC) | Por entidad |
| `idx_auditoria_datos_nuevos` | auditoria | datos_nuevos (GIN) | JSONB queries |
| `idx_notificacion_usuario` | notificacion | (usuario_id, leido, created_at DESC) | Bandeja |
| `idx_mensaje_chat_proyecto` | mensaje_chat | (proyecto_id, fecha DESC) | Chat |
| `idx_lectura_mensaje_usuario` | lectura_mensaje | usuario_id | No leídos |
| `idx_contrato_comercial_cliente` | contrato_comercial | (cliente_id, estado) | Contratos vigentes |

---

## Foreign Keys — Mapa Completo por Módulo

### CASCADE configurado en:
| Tabla hijo | FK | Comportamiento |
|---|---|---|
| `sesion_usuario` | → usuario.id | ON DELETE CASCADE |
| `recuperacion_password` | → usuario.id | ON DELETE CASCADE |
| `dispositivo_push` | → usuario.id | ON DELETE CASCADE |
| `usuario_rol` | → usuario.id | ON DELETE CASCADE |
| `usuario_permiso` | → usuario.id | ON DELETE CASCADE |
| `rol_permiso` | → rol.id | ON DELETE CASCADE |
| `rol_permiso` | → permiso.id | ON DELETE CASCADE |
| `geolocalizacion_asistencia` | → registro_asistencia.id | ON DELETE CASCADE |
| `foto_asistencia` | → registro_asistencia.id | ON DELETE CASCADE |
| `detalle_evaluacion` | → evaluacion.id | ON DELETE CASCADE |
| `proyecto_detalle` | → proyecto.id | ON DELETE CASCADE |
| `detalle_compra` | → orden_compra.id | ON DELETE CASCADE |
| `recepcion_detalle` | → recepcion_compra.id | ON DELETE CASCADE |
| `requerimiento_detalle` | → requerimiento.id | ON DELETE CASCADE |
| `adjunto_mensaje` | → mensaje_chat.id | ON DELETE CASCADE |
| `lectura_mensaje` | → mensaje_chat.id | ON DELETE CASCADE |
| `recordatorio_destinatario` | → recordatorio.id | ON DELETE CASCADE |

---

## Queries de Referencia Rápida

### Avance de un proyecto
```sql
SELECT
  p.nombre_proyecto,
  COUNT(ps.id) AS total_servicios,
  COUNT(ps.id) FILTER (WHERE ps.estado = 'Completado') AS completados,
  ROUND(
    COUNT(ps.id) FILTER (WHERE ps.estado = 'Completado')::decimal
    / NULLIF(COUNT(ps.id), 0) * 100, 2
  ) AS porcentaje_avance
FROM proyecto p
LEFT JOIN proyecto_servicio ps ON ps.proyecto_id = p.id
WHERE p.id = $1 AND p.empresa_id = $2
GROUP BY p.id, p.nombre_proyecto;
```

### Datos completos de un empleado
```sql
SELECT
  u.nombre, u.apellido, u.email, u.username,
  e.codigo, e.cargo, e.area, e.tipo,
  array_agg(DISTINCT r.nombre) AS roles
FROM empleado e
JOIN usuario u ON u.id = e.usuario_id
LEFT JOIN usuario_rol ur ON ur.usuario_id = u.id
LEFT JOIN rol r ON r.id = ur.rol_id
WHERE e.id = $1 AND e.empresa_id = $2
GROUP BY u.nombre, u.apellido, u.email, u.username, e.codigo, e.cargo, e.area, e.tipo;
```

### Asistencia de hoy por empresa
```sql
SELECT
  u.nombre || ' ' || u.apellido AS empleado,
  ra.tipo, ra.fecha_hora, ra.estado,
  fa.similitud_ia, fa.resultado AS resultado_biometrico,
  g.latitud, g.longitud
FROM registro_asistencia ra
JOIN empleado e ON e.id = ra.empleado_id
JOIN usuario u ON u.id = e.usuario_id
LEFT JOIN foto_asistencia fa ON fa.registro_id = ra.id
LEFT JOIN geolocalizacion_asistencia g ON g.registro_id = ra.id
WHERE ra.empresa_id = $1
  AND DATE(ra.fecha_hora) = CURRENT_DATE
ORDER BY ra.fecha_hora DESC;
```

### Stock bajo mínimo
```sql
SELECT
  m.nombre AS material, m.codigo, m.unidad,
  s.cantidad AS stock_actual,
  s.cantidad_minima,
  a.nombre AS almacen
FROM stock s
JOIN material m ON m.id = s.material_id
JOIN almacen a ON a.id = s.almacen_id
WHERE s.empresa_id = $1
  AND s.cantidad <= s.cantidad_minima
ORDER BY (s.cantidad_minima - s.cantidad) DESC;
```

### Requerimientos pendientes de aprobación
```sql
SELECT
  r.id, r.tipo, r.fecha, r.observacion,
  u.nombre || ' ' || u.apellido AS solicitante,
  p.nombre_proyecto,
  ps.nombre AS servicio,
  json_agg(json_build_object(
    'material', m.nombre, 'cantidad', rd.cantidad
  )) AS items
FROM requerimiento r
JOIN empleado e ON e.id = r.solicitante_id
JOIN usuario u ON u.id = e.usuario_id
JOIN proyecto p ON p.id = r.proyecto_id
LEFT JOIN proyecto_servicio ps ON ps.id = r.proyecto_servicio_id
LEFT JOIN requerimiento_detalle rd ON rd.requerimiento_id = r.id
LEFT JOIN material m ON m.id = rd.material_id
WHERE r.empresa_id = $1 AND r.estado = 'pendiente'
GROUP BY r.id, u.nombre, u.apellido, p.nombre_proyecto, ps.nombre
ORDER BY r.fecha;
```

---

## Notas para Claude Code

1. **Siempre filtrar `empresa_id`** — el sistema es multi-tenant y cada query debe incluirlo en `WHERE`.

2. **IDs son UUID** — nunca usar `SERIAL` o `BIGINT`. Generar con `uuid_generate_v4()` o desde el backend.

3. **`empleado` ≠ `usuario`** — `usuario` es auth, `empleado` es perfil laboral. Para datos completos hacer JOIN. Los IDs son diferentes.

4. **`contrato`** (laboral, FK → empleado) es distinto de **`contrato_comercial`** (comercial, FK → cliente).

5. **`proyecto_servicio`** es la tabla pivote más consultada — es el servicio específico dentro del proyecto. Los procedimientos, evidencias, requerimientos y asistencia se vinculan a ella.

6. **Cloudinary** — siempre guardar `url_cloudinary` (para mostrar) y `public_id_cloudinary` (para eliminar vía API). Nunca guardar solo uno.

7. **`auditoria.datos_anteriores/nuevos` son JSONB** — se puede hacer `WHERE datos_nuevos->>'estado' = 'Cancelado'` con índice GIN activo.

8. **Soft delete** — usar `activo = FALSE` en lugar de `DELETE` para: `empresa`, `usuario`, `empleado`, `cliente`, `material`, `equipo`, `grupo_trabajo`, `grupo_miembro`, `turno_empleado`, `proyecto_miembro`.

9. **`foto_biometrica.activa`** — un usuario solo debe tener una foto biométrica activa. Al actualizar, poner la anterior en `activa = FALSE`.

10. **`stock` tiene PK compuesta** `(material_id, empresa_id, almacen_id)` — los INSERT deben usar `ON CONFLICT DO UPDATE` para actualizar stock.

```sql
INSERT INTO stock (material_id, empresa_id, almacen_id, cantidad, cantidad_minima, updated_at)
VALUES ($1, $2, $3, $4, $5, NOW())
ON CONFLICT (material_id, empresa_id, almacen_id)
DO UPDATE SET cantidad = stock.cantidad + EXCLUDED.cantidad, updated_at = NOW();
```

---

*Documento generado automáticamente desde `schema_postgresql.sql` — 82 tablas — PostgreSQL 18.x*
