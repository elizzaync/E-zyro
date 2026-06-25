# Manual de Usuario — Logístico

E-Zyro · E-System TIC · v1.0

---

## ¿Qué puede hacer un Logístico?

El **Logístico** gestiona el inventario de materiales, herramientas y equipos de la empresa. Atiende las solicitudes de los proyectos, gestiona compras, administra el almacén y controla EPP.

---

## 1. Pantalla Principal

Al iniciar:
- **KPIs**: solicitudes pendientes, ítems en stock crítico, transferencias del día.
- **Próximos servicios con solicitudes**: servicios que tienen materiales pendientes de despacho.
- **Acciones Rápidas**: Asistencia, Calendario, Operaciones.

---

## 2. Requerimientos (Panel Principal de Logística)

El panel central de logística. Accesible desde tab **Logística** o desde la pantalla principal.

### Ver solicitudes entrantes

- Lista unificada de todas las solicitudes (materiales + equipos) de todos los proyectos.
- Filtros: por estado, proyecto, urgencia, fecha.
- Cada solicitud muestra: proyecto, servicio, lista de ítems, firmado por.

### Atender una solicitud

1. Tocar la solicitud → ver detalle con todos los ítems solicitados.
2. Para cada ítem: verificar si hay stock disponible en almacén.
3. Si hay stock → marcar como **"Preparado para despacho"**.
4. Si no hay stock → iniciar proceso de compra (ver sección 4).
5. Al despachar → registrar la salida del almacén.
6. El técnico en obra firma la recepción desde su app.

### Estados de solicitud

| Estado | Significado |
|--------|-------------|
| Pendiente | Nueva solicitud, sin atender |
| En proceso | Logística está preparando o comprando |
| Despachada | Materiales enviados a obra |
| Recibida | Técnico firmó recepción en obra |

---

## 3. Almacén

### Ver inventario actual

1. Tab **Logística → Almacén**.
2. Ver todos los ítems del inventario: materiales, herramientas, equipos.
3. Columnas: nombre, código, stock actual, stock mínimo, almacén.
4. Íconos de alerta: 🔴 Stock crítico (bajo mínimo) · 🟡 Stock bajo · 🟢 Normal.

### Ingresar materiales al almacén

**Opción A — Ingreso directo (sin orden de compra):**
1. **Almacén → "+ Ingreso Directo"**.
2. Seleccionar tipo: Material / Herramienta / Equipo / EPP.
3. Escanear QR del ítem (si tiene etiqueta) o buscar por nombre.
4. Ingresar cantidad, costo unitario, destino (stock / servicio / correctivo).
5. Confirmar. El sistema genera asiento contable automático en Finanzas.

**Opción B — Recepción de compra (desde orden de compra):**
1. En la Carta de Compra → **"Recibir"**.
2. Verificar los ítems recibidos contra los solicitados.
3. Confirmar la recepción → actualiza stock automáticamente.

### Transferencias entre almacenes

1. **Almacén → Transferencias → "+ Nueva Transferencia"**.
2. Seleccionar almacén de origen y destino.
3. Agregar ítems y cantidades.
4. Confirmar.

### Etiquetas QR

Para ítems que no tienen etiqueta:
1. Seleccionar el ítem en inventario.
2. **"Generar etiqueta"** → imprime QR con nombre, código, almacén.
3. Pegar la etiqueta física en el ítem.

---

## 4. Compras

### Crear una carta de compra

Cuando se necesita comprar ítems no disponibles en stock:

1. **Logística → Compras → "+ Nueva carta de compra"**.
2. Agregar ítems con: cantidad, precio estimado, proveedor.
3. Vincular a solicitud o proyecto (opcional).
4. Enviar para aprobación del Admin (si supera el límite de monto).
5. Una vez aprobada, proceder con la compra al proveedor.
6. Al recibir la mercadería → **Recibir** la carta de compra.

### Ver estado de compras

- **Logística → Compras**: lista de todas las cartas de compra.
- Estados: Borrador · Enviada · Aprobada · En tránsito · Recibida.

---

## 5. EPP (Equipos de Protección Personal)

Control de entrega de EPP al personal:

1. **Más → Módulos Operativos → Catálogos → EPP**.
2. Ver stock de cada tipo de EPP (casco, chaleco, guantes, etc.).
3. Registrar entrega a un trabajador: fecha, cantidad, firma.
4. El sistema descuenta del stock y registra en el expediente del trabajador.

---

## 6. Inventario Valorizado

Vista financiera del inventario:

1. **Logística → Inventario Valorizado**.
2. Ver el valor total del inventario en tiempo real.
3. Desglose por: tipo de ítem, almacén, proyecto.
4. El valor se actualiza con cada entrada/salida.

> Esta vista es de solo lectura para Logístico. Finanzas accede a ella desde su módulo.

---

## 7. Drive de Empresa

Repositorio de documentos logísticos:

1. **Más → Trabajo → Drive de Empresa**.
2. Acceder a carpetas de: fichas técnicas, catálogos de proveedores, guías de manejo.
3. Subir documentos relevantes (facturas, guías de remisión, etc.).

---

## 8. Galería

Ver todas las fotos de evidencia subidas en los proyectos:

1. **Más → Recursos → Galería**.
2. Filtrar por proyecto, servicio, fecha.
3. Útil para verificar el estado de materiales instalados en obra.

---

## Preguntas frecuentes

**¿Puedo ver solicitudes de proyectos de otras empresas?**  
No. Solo ve solicitudes de los proyectos de su empresa.

**¿Qué pasa si el técnico no firma la recepción?**  
La solicitud permanece en estado "Despachada". El logístico puede hacer seguimiento y recordarle al técnico que confirme la recepción desde su app.

**¿Cómo registro un material que no existe en el catálogo?**  
Desde **Más → Módulos Operativos → Catálogos → Materiales** puede agregar nuevos ítems al catálogo. Si no tiene permiso, solicitarlo al Admin.

**¿El sistema avisa cuando el stock baja del mínimo?**  
Sí. Recibirá una notificación push cuando un ítem caiga por debajo del stock mínimo configurado.
