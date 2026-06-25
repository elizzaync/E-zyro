# Manual de Usuario — Admin de Empresa

E-Zyro · E-System TIC · v1.0

---

## ¿Qué puede hacer un Admin?

El **Admin** tiene acceso completo a todos los módulos de su empresa. Gestiona usuarios, supervisa operaciones, logística, finanzas, RR.HH. y configura el acceso al Portal Cliente para los clientes externos.

---

## 1. Pantalla Principal

Vista ejecutiva con:
- KPIs globales: proyectos activos, servicios del mes, facturación pendiente.
- Próximos servicios de toda la empresa.
- Accesos rápidos a módulos frecuentes.

---

## 2. Gestión de Usuarios

### Crear un usuario nuevo

1. **Más → Administración → Gestión de Usuarios → "+ Nuevo Usuario"**.
2. Ingresar: nombre completo, email, rol.
3. El sistema envía credenciales temporales al email del usuario.
4. El usuario debe cambiar la contraseña en el primer inicio de sesión.

### Roles disponibles

| Rol | Descripción |
|-----|-------------|
| Admin | Acceso total a la empresa |
| Jefe de Operaciones | Gestión de proyectos y servicios |
| Técnico | Campo: servicios asignados, evidencias, asistencia |
| Logístico | Almacén, materiales, compras, EPP |

### Activar / Desactivar usuarios

- En la lista de usuarios → deslizar el switch al lado del nombre.
- Un usuario inactivo no puede iniciar sesión.

### Resetear contraseña

- Seleccionar usuario → **"Resetear contraseña"** → confirmar.
- El usuario recibe un email con nueva contraseña temporal.

---

## 3. Operaciones

Acceso total a todos los proyectos de la empresa:

- Crear, editar y cerrar proyectos.
- Ver y asignar servicios a cualquier Jefe de Operaciones.
- Supervisar procedimientos y evidencias.
- Ver Dashboard de Operaciones con métricas globales.

> Ver [manual_jefe_operaciones.md](manual_jefe_operaciones.md) para detalle operativo.

---

## 4. Logística y Almacén

Acceso total al módulo logístico:

- Aprobar cartas de compra de alto valor.
- Ver inventario valorizado.
- Gestionar almacenes y transferencias.
- Ver y auditar solicitudes de materiales de todos los proyectos.

> Ver [manual_logistico.md](manual_logistico.md) para detalle logístico.

---

## 5. Recursos Humanos

### Acceso al hub de RR.HH.

1. **Más → Administración → Recursos Humanos**.
2. Ver todas las secciones:

| Sección | Descripción |
|---------|-------------|
| Personal | Expedientes de todos los trabajadores |
| Asistencias | Control diario de entradas y salidas |
| Evaluaciones | Desempeño por trabajador |
| Vacaciones | Saldo y solicitudes de vacaciones |
| Indicadores | KPIs de RR.HH. (ausentismo, puntualidad, rotación) |
| Solicitudes | Bandeja de permisos y trámites |

### Gestión de personal

1. **RR.HH. → Personal → seleccionar trabajador**.
2. Ver expediente: datos personales, historial laboral, evaluaciones, vacaciones.
3. Exportar PDF del historial completo.

### Control de asistencias

1. **RR.HH. → Control de Asistencias**.
2. Ver tabla de asistencias diarias de todo el equipo.
3. Filtrar por fecha, turno, área.
4. Aplicar justificaciones o correcciones de tardanza.
5. Exportar reporte mensual para nómina.

---

## 6. Finanzas

### Dashboard financiero

1. **Más → Módulos Operativos → Finanzas**.
2. Ver: ingresos del mes, gastos, CxC, CxP, saldo en caja, balance general.

### Cuentas por Cobrar (CxC)

- Cada servicio Completado genera automáticamente una CxC.
- **Finanzas → CxC**: ver facturas pendientes y cobradas.
- Registrar cobro: tocar la CxC → **"Registrar pago"** → ingresar monto y fecha.

### Cuentas por Pagar (CxP)

- Las compras aprobadas generan CxP automáticamente.
- **Finanzas → CxP**: ver deudas con proveedores.
- Registrar pago al proveedor desde esta sección.

### Libro Diario

- **Finanzas → Asientos**: ver todos los asientos contables generados automáticamente.
- Los movimientos de inventario, cobros y pagos generan asientos PCGE automáticamente.

### Caja Chica

- **Finanzas → Caja**: registrar gastos menores con justificante.
- Cierre periódico de caja con resumen de movimientos.

### Conciliación Bancaria

- **Finanzas → Conciliación**: subir extracto bancario (CSV) y conciliar contra asientos.
- Marcar cada movimiento bancario como conciliado.

> Ver [manual_finanzas.md en la app] para detalle de cada pantalla de Finanzas.

---

## 7. Accesos Portal Cliente

Dar acceso al Portal B2B a los clientes:

1. **Más → Administración → Accesos Portal Cliente**.
2. **"+ Nuevo acceso"**: ingresar email del cliente y asociar a su proyecto(s).
3. El cliente recibe email de bienvenida con link al portal web.
4. Puede revocar acceso en cualquier momento.

---

## 8. Registro de Auditoría

Ver el historial de acciones de todos los usuarios de la empresa:

1. **Más → Administración → Registro de Auditoría**.
2. Filtrar por usuario, módulo, fecha, tipo de acción.
3. Ver quién creó, editó o eliminó cada registro.

> El SuperAdmin puede ver la auditoría global de todas las empresas.

---

## 9. Dashboards

Tableros analíticos de la empresa:

1. **Más → Administración → Dashboards**.
2. Seleccionar dashboard: Operaciones, Logística, Finanzas, RR.HH.
3. Filtrar por rango de fechas.

---

## 10. Módulos Operativos Adicionales

| Módulo | Acceso | Descripción |
|--------|--------|-------------|
| Mantenimientos | Más → Módulos Operativos | Panel semáforo de equipos |
| Calibraciones | Más → Módulos Operativos | Historial y alertas de calibración |
| Garantías / Correctivos | Más → Módulos Operativos | Gestión de correctivos y garantías |
| Inspección ITSE | Más → Módulos Operativos | Checklists de inspección eléctrica |
| Catálogos | Más → Módulos Operativos | Materiales, equipos, EPP |
| Procedimientos estándar | Más → Módulos Operativos | Plantillas de procedimientos por tipo de trabajo |
| Documentos SST | Más → Módulos Operativos | Documentos de seguridad y salud en el trabajo |
| Planos | Más → Recursos | Planos técnicos de proyectos |
| Galería | Más → Recursos | Todas las fotos de evidencia |

---

## Preguntas frecuentes

**¿Puedo ver datos de otras empresas?**  
No. El Admin solo ve los datos de su propia empresa. Para acceso multi-empresa se requiere rol SuperAdmin.

**¿Cómo reabrir un servicio Completado?**  
Solo el SuperAdmin puede reabrir servicios completados. Contactar al SuperAdmin o al equipo de E-System TIC.

**¿Qué pasa si elimino un usuario?**  
Los usuarios no se eliminan permanentemente, solo se desactivan. Su historial de actividad se conserva en auditoría.
