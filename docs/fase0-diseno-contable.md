# Fase 0 — Diseño contable del ERP (documento base)

## 1. Validación contable
- Estado: no es requisito normativo estricto para este proyecto (no se usará para declarar impuestos formalmente en esta etapa).
- Recomendación: si en el futuro el sistema se usa para declarar ante SUNAT o auditorías, este documento debe ser revisado por un contador colegiado antes de ese uso.

## 2. Plan de cuentas base (Chart of Accounts)
- Estándar adoptado: **PCGE (Plan Contable General Empresarial – Perú)**, versión completa, importado como catálogo semilla.
- Estructura de cada cuenta:
  - `codigo` (jerárquico, ej. 10, 101, 1041)
  - `nombre`
  - `tipo`: Activo | Pasivo | Patrimonio | Ingreso | Gasto
  - `naturaleza`: Deudora | Acreedora (define si aumenta con débito o crédito)
  - `nivel`: cuenta de mayor (agrupadora) | cuenta de detalle (imputable)
  - `estado`: activa | inactiva
- Reglas:
  - Solo las cuentas de detalle pueden recibir movimientos en asientos.
  - Las cuentas se cargan completas desde el PCGE; cada empresa puede desactivar (no eliminar) las que no use.

## 3. Estrategia multi-empresa
- Modelo: **contabilidad independiente por empresa**.
- Cada empresa tiene su propio:
  - Plan de cuentas (copia del catálogo PCGE, con activación/desactivación propia)
  - Libro mayor / asientos
  - Periodos contables
- Toda tabla contable (cuentas, asientos, líneas, periodos) lleva `empresa_id` como llave foránea obligatoria.
- Consolidación entre empresas (si se necesita en el futuro): se resuelve como **reporte derivado** que agrega datos de varias empresas, sin mezclar sus estructuras de datos.

## 4. Motor de moneda
- Modelo: **moneda funcional única por empresa**.
- Cada empresa define su moneda base (ej. PEN).
- Si se requiere reportar en otra moneda, se aplica un tipo de cambio **al momento de generar el reporte**, no se almacenan transacciones multi-moneda.
- Campos relacionados: `moneda_funcional` en empresa; `tipo_cambio` opcional solo en reportes de conversión.
- Explícitamente fuera de alcance (sobre-ingeniería evitada): multi-moneda transaccional real.

## 5. Motor de asientos contables (journal engine)
### Invariante de oro
> Suma de débitos = Suma de créditos, por cada asiento, sin excepción.

### Diseño del invariante a nivel de datos/transacción
- Estructura:
  - `asiento` (encabezado): `id`, `empresa_id`, `fecha`, `periodo_id`, `descripcion`, `origen` (tipo de transacción que lo generó), `numero`
  - `asiento_linea` (detalle): `id`, `asiento_id`, `cuenta_id`, `debito`, `credito` (uno de los dos es 0)
- Regla de creación:
  - **Nunca** se insertan líneas directamente; toda creación de asiento pasa por una única función/transacción que:
    1. Recibe encabezado + líneas
    2. Valida que `SUM(debito) = SUM(credito)`
    3. Valida que el periodo (`periodo_id`) esté **abierto**
    4. Valida que cada `cuenta_id` sea una cuenta de **detalle** y esté activa
    5. Inserta encabezado y líneas en una sola transacción de base de datos (todo o nada)
  - Esto garantiza que es **imposible** que exista un asiento descuadrado en la base de datos.

### Periodos contables
- Tabla `periodo_contable`: `id`, `empresa_id`, `anio`, `mes`, `estado` (`abierto` | `cerrado`)
- Un asiento solo puede crearse/modificarse si su periodo está `abierto`.
- Cerrar un periodo es una operación irreversible (o requiere reapertura controlada con auditoría).

### Reglas de asientos automáticos por tipo de transacción
Cada tipo de transacción de negocio define un mapeo fijo a cuentas contables. Ejemplos iniciales a definir con el equipo de negocio:

| Transacción | Débito | Crédito |
|---|---|---|
| Venta al contado (con IGV) | 10 - Efectivo | 70 - Ventas / 40 - IGV por pagar |
| Venta al crédito | 12 - Cuentas por cobrar | 70 - Ventas / 40 - IGV por pagar |
| Compra de mercadería al contado | 60 - Compras / 40 - IGV crédito fiscal | 10 - Efectivo |
| Pago de planilla | 62 - Gastos de personal | 10 - Efectivo / 40 - Tributos por pagar |

> Esta tabla debe completarse y validarse según los tipos de transacción reales del negocio antes de implementarse en código (configuración, no hardcoding).

## Entregable
Este documento constituye el diseño base de Fase 0:
- ✅ Plan de cuentas definido (PCGE)
- ✅ Estrategia multi-empresa definida (independiente)
- ✅ Estrategia de moneda definida (única funcional)
- ✅ Invariante del motor de asientos definido (débito = crédito, forzado transaccionalmente)
- ⏳ Pendiente: completar tabla de mapeo transacción → cuentas contables con el equipo de negocio antes de codificar el motor de asientos automáticos.
