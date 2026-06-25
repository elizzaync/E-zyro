# Manual de Usuario — SuperAdmin

E-Zyro · E-System TIC · v1.0

---

## ¿Qué puede hacer el SuperAdmin?

El **SuperAdmin** es el rol de más alto nivel. Tiene acceso completo a **todas las empresas** registradas en la plataforma. Gestiona la configuración del sistema, realiza auditoría global, puede operar cualquier módulo de cualquier empresa y tiene visibilidad total del estado de la plataforma.

> Este rol es exclusivo del equipo de E-System TIC.

---

## 1. Diferencias clave vs Admin

| Capacidad | Admin | SuperAdmin |
|-----------|-------|-----------|
| Ver datos de su empresa | ✓ | ✓ |
| Ver datos de todas las empresas | — | ✓ |
| Auditoría General (todas las empresas) | — | ✓ |
| Reabrir servicios Completados | — | ✓ |
| Configuración global del sistema | — | ✓ |
| Acceso a logs del sistema | — | ✓ |

---

## 2. Pantalla Principal

Igual a Admin, pero los KPIs suman todas las empresas si se activa la vista global.

---

## 3. Multi-empresa

El SuperAdmin puede cambiar de empresa sin cerrar sesión:

1. Desde cualquier pantalla → **banner de empresa** (arriba en el header).
2. Tocar para abrir el selector de empresa.
3. Seleccionar la empresa → la app recarga con los datos de esa empresa.

> La empresa principal de E-System TIC se llama "E-SystemTIC" y es la primera de la lista.

---

## 4. Auditoría General

Vista de auditoría de **todas las empresas**:

1. **Más → Administración → Auditoría General**.
2. Filtrar por: empresa, usuario, módulo, fecha, tipo de acción.
3. Ver el rastro completo de cualquier acción en el sistema.
4. Exportar log para análisis externo.

> "Registro de Auditoría" (visible para Admin) muestra solo su empresa.
> "Auditoría General" (solo SuperAdmin) muestra todo el sistema.

---

## 5. Gestión global de usuarios

Puede crear, editar y desactivar usuarios en cualquier empresa:

1. **Más → Administración → Gestión de Usuarios**.
2. Seleccionar empresa objetivo.
3. Operar igual que el Admin (ver [manual_admin.md](manual_admin.md) sección 2).

---

## 6. Todos los módulos operativos

El SuperAdmin tiene acceso a todos los módulos de cada empresa:

- **Operaciones**: todos los proyectos de todas las empresas.
- **Logística**: inventario, compras y almacenes de todas las empresas.
- **Finanzas**: estados financieros de cada empresa.
- **RR.HH.**: personal y asistencias de todas las empresas.
- **Mantenimientos, Calibraciones, ITSE, SST**: acceso completo.

Para operar en una empresa específica, primero cambiar a esa empresa (sección 3).

---

## 7. Configuración del sistema

Parámetros globales de la plataforma:

- Gestión de empresas activas.
- Configuración de HMAC y firma digital de eventos.
- Variables de entorno y claves de integración (Railway/backend).
- Umbrales y alertas globales.

> La configuración del sistema se realiza principalmente desde el backend (FastAPI/Railway). Consultar con el equipo técnico.

---

## 8. Logs del sistema

1. **Más → Administración → Auditoría General → pestaña Logs**.
2. Ver eventos del sistema: errores, sincronizaciones offline, procesos scheduler.
3. Útil para diagnóstico de incidencias en producción.

---

## 9. Portal Cliente

Puede crear accesos al Portal B2B para cualquier empresa:

1. Cambiar a la empresa objetivo.
2. **Más → Administración → Accesos Portal Cliente**.
3. Crear acceso para el cliente externo.

---

## 10. Reabrir servicios Completados

En casos excepcionales:

1. Entrar al servicio en estado "Completado".
2. **"Reabrir servicio"** (solo visible para SuperAdmin).
3. Ingresar justificación.
4. El evento queda registrado en Auditoría General.

---

## Buenas prácticas para el SuperAdmin

- **No operar datos de producción sin justificación documentada**: cualquier acción queda en el log de auditoría general.
- **Cambiar siempre a la empresa correcta antes de editar**: verificar el nombre de empresa en el header antes de crear o modificar datos.
- **Usar cuentas de prueba para demos**: no usar datos reales de clientes en demostraciones.
- **Rotar credenciales periódicamente**: cambiar la contraseña del SuperAdmin cada 90 días.
