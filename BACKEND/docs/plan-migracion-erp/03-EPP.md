# 03 · EPP — Equipos de Protección Personal (Fase 2)

## Mapeo desde el ERP
Cubre las 5 secciones del ERP: **Tabla de EPPs (48)**, **Control de Entrega (49)**, **Historial de Entrega (50)**, **Ingreso de EPPs Nuevos (51)**, **Historial de EPPs Nuevos (52)**.
Campos observados en los formularios del ERP:
- Catálogo EPP: `nombre, descripcion, marca, unidad, stock_actual, stock_min, zona, precio, imagen`.
- Entrega: receptor (empleado), fecha, ítems (epp + cantidad), **constancia PDF + firma**, observación.
- Ingreso: personal que compró, fecha compra, ítems (epp + cantidad), proveedor opcional.

## Ubicación en la app
Pestaña **Logística** → nueva sección "EPP" (es gestión de almacén/stock). Tres vistas: Catálogo, Entregas, Ingresos. Acceso secundario desde "Más" si se requiere.

## Modelo de datos (tablas nuevas)
Reutiliza `marca`, `unidad_medida`, zona (Fase 0), `empleado`, `proveedor`.

**`epp`** (catálogo)
| col | tipo | nota |
|-----|------|------|
| id | String(36) PK | |
| empresa_id | FK empresa | NOT NULL |
| nombre | String(200) | |
| descripcion | String(500) | nullable |
| marca_id | FK marca | nullable |
| unidad_id | FK unidad_medida | nullable |
| zona_id | FK zona | nullable |
| stock_actual | Integer | default 0 |
| stock_min | Integer | default 0 |
| precio | Numeric(12,2) | nullable |
| imagen_url | Text | nullable (Cloudinary) |
| activo | Boolean | default true |
| created_at/updated_at | | |

**`epp_entrega`** (cabecera de entrega)
| id, empresa_id, empleado_id (receptor, FK empleado), fecha (Date), registrado_por_id, firma_url, pdf_url, observacion, created_at |
- `estado` String(20) CHECK in ('registrada','anulada').

**`epp_entrega_detalle`**: id, entrega_id (FK), epp_id (FK), cantidad (Integer).

**`epp_ingreso`** (cabecera de ingreso de stock nuevo)
| id, empresa_id, personal_compro_id (FK empleado), proveedor_id (FK, nullable), fecha_compra (Date), registrado_por_id, created_at |

**`epp_ingreso_detalle`**: id, ingreso_id (FK), epp_id (FK), cantidad (Integer), precio_unitario (Numeric, nullable).

> **Movimiento de stock:** entrega ⇒ `epp.stock_actual -= cantidad`; ingreso ⇒ `+= cantidad`. Hacerlo **dentro de la misma transacción** que inserta el detalle. Validar stock suficiente antes de entregar (HTTPException 409 si no alcanza).

## Migraciones
- Tablas con FK uuid a `empresa`/`marca`/`unidad`/`empleado` → crear en `_pre_create_migrations()` con `uuid` explícito (mismo patrón que `marca`).
- CHECKs de estado idempotentes (`DROP IF EXISTS` + `ADD`).
- Permisos RBAC seed: `epp.ver`, `epp.crear`, `epp.editar`, `epp.entregar`, `epp.ingresar`, `epp.eliminar`.
- Espejo SQL en `migrations/<fecha>_epp.sql`.

## API backend — `app/routers/epp.py` (prefix `/epp`)
Catálogo:
- `GET /epp` (filtros: q, zona, marca, stock_bajo) · `POST /epp` · `PUT /epp/{id}` · `DELETE /epp/{id}` (soft `activo=false`).
- `POST /epp/{id}/imagen` — sube imagen vía `cloudinary_paths.carpeta_epp` + indexa en `recurso_cloudinary`; elimina la anterior.

Entregas:
- `POST /epp/entregas` — body: empleado_id, items[], firma (base64), observacion. Descuenta stock, sube firma a `carpeta_epp_entrega`, **genera constancia PDF** (`pdf_service`) y la sube como `raw`; indexa firma y PDF.
- `GET /epp/entregas` (historial, filtros: empleado, fecha) · `GET /epp/entregas/{id}` · `POST /epp/entregas/{id}/anular` (revierte stock).

Ingresos:
- `POST /epp/ingresos` — suma stock · `GET /epp/ingresos` (historial) · `GET /epp/ingresos/{id}`.

Schemas en `app/schemas/epp.py` (EppCreate/Update/Out, EntregaCreate/Out, IngresoCreate/Out, con validadores de cantidad>0).

## PDF (constancia de entrega)
Plantilla "CONSTANCIA DE ENTREGA DE EPP" (vista en ERP): datos de empresa, receptor, tabla de ítems (EPP, marca, cantidad), fecha, firma del receptor. Implementar en `services/pdf_service.py` (reusar estilo de los PDF existentes).

## App móvil
- `models/epp_models.dart`: Epp, EppEntrega, EppEntregaDetalle, EppIngreso.
- `services/epp_service.dart`: CRUD catálogo, entregas, ingresos.
- `screens/`:
  - `pantalla_epp.dart` — tabs: Catálogo / Entregas / Ingresos.
  - `pantalla_epp_entrega.dart` — seleccionar receptor + ítems + **captura de firma** (paquete de firma ya factible; reusar widget de firma si existe en mantenimiento/recepción) → genera y muestra PDF.
  - `pantalla_epp_ingreso.dart` — registrar ingreso de stock.
- **Offline-first opcional:** la entrega en campo puede encolarse (`repositories/epp_local_repo.dart`) y sincronizar; evaluar según uso real. Catálogo/ingreso pueden ser online.
- Navegación: sección "EPP" dentro de `pantalla_logistica.dart` (o `_MenuItem` en Más).

## Orden interno
1. Modelos + migración (`_pre_create`) + seeds permisos → arranque limpio.
2. Schemas + router catálogo + imagen → arranque + commit.
3. Router entregas (stock + firma + PDF + index) → arranque + commit.
4. Router ingresos (stock) → arranque + commit.
5. App: catálogo → entregas(firma+PDF) → ingresos.

## Checklist anti-errores específico
- [ ] Stock nunca queda negativo (validación + transacción atómica).
- [ ] Anular entrega revierte stock exactamente una vez (idempotente).
- [ ] Firma y PDF indexados en `recurso_cloudinary` con `entidad_tipo='epp_entrega'`.
- [ ] CHECK de `estado` incluye todos los valores usados.
- [ ] Cantidades > 0 validadas en schema.

## Definition of Done
- [ ] CRUD catálogo + imagen funcionando, stock consistente.
- [ ] Entrega genera constancia PDF + firma, descuenta stock, historial consultable.
- [ ] Ingreso suma stock, historial consultable.
- [ ] App con las 3 vistas; entrega con firma en móvil.
- [ ] Backend arranca limpio; `/code-review` sin hallazgos altos; PROGRESO actualizado.
