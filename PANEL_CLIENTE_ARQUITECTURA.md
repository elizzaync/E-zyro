# Panel Cliente — Arquitectura y Plan de Implementación

> Documento generado el 2026-06-07. Auditoría de BD de producción + plan de módulo futuro.

---

## 1. Estado actual de la BD (producción)

### Tablas existentes relevantes al Panel Cliente

| Tabla | Propósito para el panel | Estado |
|---|---|---|
| `usuario_cliente` | Login/sesión del cliente | ✅ Lista |
| `cliente` | Empresa cliente (razón social, RUC) | ✅ Lista |
| `equipo_intervenido` | Activos con historial de mantenimiento | ✅ Lista |
| `incidencia` | Fallas reportadas durante intervenciones | ✅ Lista |
| `evidencia_mantenimiento` | Fotos/evidencias del mantenimiento | ✅ Lista |
| `carta_garantia` | Documentos de garantía emitidos | ⚠️ Incompleta (ver abajo) |
| `recurso_cloudinary` | Índice de todos los assets subidos | ✅ Lista |
| `orden_mantenimiento` | Órdenes de mantenimiento por equipo | ✅ Lista |
| `plan_mantenimiento` | Plan de frecuencia por equipo | ✅ Lista |

### Campos clave ya disponibles en `equipo_intervenido`
- `ultimo_mantenimiento` (date) — fecha del último mantenimiento realizado
- `proximo_mantenimiento` (date) — fecha proyectada del próximo
- `frecuencia_meses` (int) — cada cuántos meses se realiza
- `observaciones` (text) — notas del técnico
- `estado_intervencion` — sin_inspeccion / en_proceso / completado
- `activo_cliente_id` — FK hacia el activo del cliente (si aplica)

### Campos clave en `incidencia`
- `tipo_falla`, `descripcion`, `estado`, `resolucion_nota`
- `fecha_reporte`, `fecha_resolucion`
- Vinculada a `equipo_id` y `proyecto_servicio_id`

---

## 2. Gap: tabla `carta_garantia` incompleta

Las firmas digitales y el PDF generado no se persisten en la nube actualmente.

### Migración requerida (ya aplicada el 2026-06-07)

```sql
ALTER TABLE carta_garantia
  ADD COLUMN IF NOT EXISTS firma_verificador_url TEXT,
  ADD COLUMN IF NOT EXISTS firma_gerente_url     TEXT,
  ADD COLUMN IF NOT EXISTS documento_pdf_url     TEXT;
```

---

## 3. Plan de implementación del Panel Cliente

### 3.1 Funcionalidades requeridas

1. **Historial de mantenimiento del equipo**
   - Query: `equipo_intervenido` → `evidencia_mantenimiento` → `orden_mantenimiento`
   - Mostrar: fecha, técnico, observaciones, próximo mantenimiento

2. **Herramientas y EPPs usados**
   - Query: `prestamo` + `prestamo_item` (filtrar por servicio)
   - Mostrar: herramienta, serie, marca, estado de calibración

3. **Incidencias reportadas**
   - Query: `incidencia` filtrada por `equipo_id` o `proyecto_servicio_id`
   - Mostrar: tipo de falla, descripción, estado, resolución

4. **Próximo mantenimiento**
   - Campo directo: `equipo_intervenido.proximo_mantenimiento`
   - Cálculo: `ultimo_mantenimiento` + `frecuencia_meses`

5. **Documentos (Informe / Carta de Garantía en PDF)**
   - El Jefe de Operaciones sube el PDF a Cloudinary (tabla `recurso_cloudinary`)
   - El Panel Cliente consume el campo `documento_pdf_url` de `carta_garantia`
   - Alternativa futura: endpoint que genera PDF on-demand desde el Word existente

### 3.2 Flujo propuesto para gestión de documentos

```
Jefe Operaciones
  → Genera Word (endpoint actual)
  → [Futuro] Convierte a PDF (WeasyPrint o LibreOffice headless en Docker)
  → Sube PDF a Cloudinary (subir_pdf_bytes_cloudinary ya existe en cloudinary_service.py)
  → Guarda URL en carta_garantia.documento_pdf_url
  
Usuario Cliente
  → Accede al Panel Cliente con sus credenciales (usuario_cliente)
  → Ve lista de equipos de su empresa
  → Descarga el PDF desde la URL de Cloudinary
```

### 3.3 Ruta API sugerida (no implementada aún)

```
GET  /cliente/equipos                        → lista de activos del cliente autenticado
GET  /cliente/equipos/{id}/historial         → mantenimientos del activo
GET  /cliente/equipos/{id}/incidencias       → incidencias del activo
GET  /cliente/documentos                     → cartas y informes disponibles para descarga
POST /cliente/documentos/{carta_id}/pdf      → (futuro) genera y sube el PDF
```

### 3.4 Autenticación del Panel Cliente

- `usuario_cliente` ya tiene `email`, `password_hash`, `activo`, `cliente_id`
- Crear un router separado `/panel-cliente/...` con JWT propio (distinto al JWT de empleados)
- Scope del token: solo puede ver datos de su `cliente_id`

---

## 4. Dependencias técnicas

| Componente | Estado | Notas |
|---|---|---|
| `cloudinary_service.py` | ✅ Listo | `subir_pdf_bytes_cloudinary` ya disponible |
| `word_carta_garantia.py` | ✅ Listo | Genera .docx con imágenes flotantes |
| Conversión Word→PDF | ❌ Pendiente | Requiere LibreOffice headless en Docker o WeasyPrint |
| Router Panel Cliente | ❌ Pendiente | Nueva feature branch |
| Frontend Panel Cliente | ❌ Pendiente | App Angular separada o ruta pública |
