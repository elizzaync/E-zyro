# Manual de Usuario — Pantallas de Finanzas E-Zyro
### Qué hacer en cada pantalla, y qué asiento contable (PCGE) genera cada acción

> Este manual es distinto del "Manual del módulo de Finanzas" (el que
> explica la teoría y la arquitectura). **Este es un manual operativo**:
> está pensado para la persona que se sienta frente a la pantalla y
> necesita saber **qué botón tocar, qué campos llenar, en qué orden, y
> qué pasa "del otro lado"** — es decir, qué registro contable exigido
> por el **PCGE (Plan Contable General Empresarial)** queda formado
> automáticamente al completar cada acción.
>
> Formato de cada sección:
> 1. **¿Qué tengo que hacer?** — pasos concretos, en orden
> 2. **¿Qué registro contable se forma?** — qué cuentas PCGE se mueven y
>    en qué sentido (Debe / Haber), explicado en una frase simple
> 3. **Cosas a las que debo prestar atención** — validaciones, errores
>    comunes, requisitos previos
>
> Si necesitas entender **por qué** funciona así (la teoría detrás), ese
> es el rol del otro manual — aquí solo nos enfocamos en **la acción y su
> consecuencia contable**.

---

# ÍNDICE

0. Empezar aquí — cómo pensar Finanzas y en qué orden usarla
1. Plan de cuentas (Periodos y Asiento manual)
2. Cuentas por Pagar — registrar facturas de proveedores y pagos
3. Cuentas por Cobrar — emitir comprobantes a clientes y registrar cobros
4. Activos fijos — dar de alta un activo y procesar la depreciación mensual
5. Planilla — calcular, aprobar y pagar la planilla del mes
6. Tributario / IGV — configurar y consultar (no se "registra" nada aquí)
7. Centros de costo — crear centros y revisar el comparativo presupuesto vs. real
8. Inventario valorizado — registrar ingresos y salidas de almacén
9. Reportes financieros — cómo leer lo que generaron tus acciones
10. Checklist mensual recomendado (orden sugerido de tareas)

---

# 0. Empezar aquí — cómo pensar Finanzas y en qué orden usarla
### La idea central, los 4 conceptos mínimos y el orden lógico de todo el módulo

## 0.A — La idea central (léela dos veces)

**Todo movimiento de valor genera un asiento contable, y todo lo que ves
(dashboard, reportes) se deriva en vivo de esos asientos.** Nada se digita
dos veces: cuando facturas un servicio, cuando logística compra, cuando
pagas la planilla, el sistema escribe la contabilidad solo. Tu trabajo no
es "hacer contabilidad" — es registrar las operaciones donde ocurren, y
Finanzas se cuadra sola.

## 0.B — Los 4 conceptos mínimos

1. **Asiento**: anotación de doble entrada. Cada operación mueve al menos
   2 cuentas y siempre suma igual en ambos lados. Ejemplo: facturas un
   servicio por S/ 2,055.56 con IGV → cuenta 12 "clientes" +2,055.56 (te
   deben) / cuenta 70 "ventas" +1,742.00 / cuenta 40 "IGV" +313.56.
2. **Plan de cuentas (PCGE)**: el catálogo peruano de "cajones" donde caen
   los montos. Los que más verás: **10** caja y bancos (tu plata), **12**
   clientes te deben, **20** mercadería en almacén, **33** activos fijos,
   **40** impuestos por pagar, **42** debes a proveedores, **6x** gastos,
   **7x** ingresos.
3. **Devengado vs. caja**: la venta se registra cuando facturas
   (devengado), no cuando cobras. Por eso el resultado del mes puede ser
   positivo aunque aún no haya entrado un sol. "Disponible" sí es caja real.
4. **Periodo contable**: cada mes se abre, se registra y se cierra, para
   que nadie toque números de meses ya reportados (capítulo 1).

## 0.C — Cómo leer el dashboard (pantalla inicial de Finanzas)

- **Disponible hoy**: saldo real de caja y bancos (cuentas 10). Si nunca
  cargaste saldos iniciales, marca S/ 0 aunque tengas plata en el banco.
- **Te deben / Debes**: suma de facturas de clientes (CxC) y de
  proveedores (CxP) aún no cobradas/pagadas. Las facturas en dólares se
  convierten al **tipo de cambio de emisión** (el del asiento), no al del
  día — así el card siempre cuadra con el libro contable.
- **Mes**: resultado del mes en curso = ingresos (cuentas 7x) menos gastos
  (cuentas 6x), **sin IGV** (el IGV no es ingreso tuyo, es deuda con
  SUNAT). Es ganancia devengada, no efectivo.
- **Caja proyectada 30/60/90**: disponible hoy + cobros que vencen en el
  horizonte − pagos comprometidos. Lo vencido cuenta como exigible ya.

## 0.D — El orden lógico de uso

**Configurar (una sola vez):**

1. Cargar **saldos iniciales** de caja y bancos (y deudas existentes). Sin
   esto, "Disponible" y "Caja proyectada" no reflejan tu realidad.
2. Verificar tasa de IGV y régimen (capítulo 6) y que el periodo del mes
   esté abierto (capítulo 1).
3. Dar de alta los activos fijos existentes (capítulo 4) — la depreciación
   mensual luego corre sola.

**Ciclo del INGRESO (cada venta):**

1. Operaciones completa el servicio.
2. Cuentas por Cobrar → "Facturar servicio" → factura + asiento
   automático (capítulo 3.A). Sube "Te deben" y "Mes".
3. El cliente paga → registrar el cobro (capítulo 3.C). Baja "Te deben",
   sube "Disponible".

**Ciclo del COSTO (cada gasto):**

- Compra de materiales/equipos → nace en **Logística** (requerimiento /
  carta de compra) → cae sola en CxP → la pagas ahí (capítulo 2.C).
- Factura suelta (alquiler, luz, servicios) → CxP manual eligiendo la
  cuenta de gasto (capítulo 2.A).
- Gasto menor en efectivo → **Caja chica**.
- Sueldos → **Planilla** mensual (capítulo 5).
- Depreciación e inventario → automáticos, no haces nada.

**Rutina mensual** (1-2 horas): conciliación bancaria, leer el estado de
resultados y el top de gastos, comparar presupuesto y rentabilidad, y
cerrar el periodo. El paso a paso completo está en el **capítulo 10
(Checklist mensual)**.

**Rutina anual**: cierre de ejercicio + export PLE para SUNAT, con tu
contador (capítulos 1 y 6).

> Regla de oro: si una operación movió plata o valor y no pasó por uno de
> estos circuitos, la contabilidad quedó incompleta. Todo entra por su
> pantalla — nunca "de memoria" al final del mes.

---

# 1. Plan de cuentas
### Pestañas: Cuentas · Comprobación · Periodos · Asientos

## 1.A — Abrir el periodo del mes (pestaña "Periodos")

### ¿Qué tengo que hacer?
1. Entra a la pestaña **"Periodos"**.
2. Toca **"Abrir periodo"**.
3. Elige el mes (formato AAAA-MM, ej. `2026-06`) que vas a empezar a
   trabajar.
4. Confirma.

### ¿Qué registro contable se forma?
Ninguno todavía — esta acción **no mueve dinero**, solo "habilita la
puerta" para que, a partir de ahora, todas las demás pantallas (facturas,
pagos, planillas, depreciaciones, movimientos de almacén) puedan
registrar operaciones con fecha dentro de ese mes.

### Cosas a las que debo prestar atención
- **Hazlo SIEMPRE al inicio de cada mes**, antes de registrar cualquier
  factura, pago o movimiento — si el periodo no está abierto, el sistema
  rechazará cualquier intento de registro con esa fecha.
- Solo personas con el permiso `contabilidad:abrir_periodo` ven este
  botón.

## 1.B — Cerrar el periodo del mes (pestaña "Periodos")

### ¿Qué tengo que hacer?
1. **Antes de cerrar**, ve a la pestaña **"Comprobación"** y verifica que
   el aviso esté en **verde** ("Balance cuadrado: Debe = Haber"). Si está
   en rojo, **NO cierres el periodo** — primero hay que investigar el
   descuadre (avisa a quien administra la contabilidad).
2. Vuelve a la pestaña **"Periodos"**, toca **"Cerrar periodo"**.
3. Elige el mes que ya terminó y cuyas operaciones ya están completas.
4. Confirma (esta acción es seria: nadie podrá tocar nada de ese mes
   después).

### ¿Qué registro contable se forma?
Ninguno — es un **candado administrativo**, no un movimiento de dinero.
A partir de este momento, ese mes queda "sellado": ninguna pantalla del
sistema podrá crear, editar ni anular nada con fecha de ese mes.

### Cosas a las que debo prestar atención
- Una vez cerrado, si encuentras un error, **no puedes simplemente
  editarlo** — hace falta que alguien con el permiso
  `contabilidad:reabrir_periodo` reabra el mes (procedimiento
  excepcional, no recomendado como rutina).
- Cierra el mes solo cuando estés seguro de que **ya se registraron
  todas** las facturas, pagos, cobros, planilla y depreciación de ese
  mes — y de que el balance de comprobación está cuadrado.

## 1.C — Registrar un asiento manual (pestaña "Asientos", botón "Asiento manual")

### ¿Qué tengo que hacer?
> ⚠️ Esta opción es **solo para quien sabe contabilidad** (visible
> únicamente con el permiso `contabilidad:crear_asiento`). Para el día a
> día normal (facturas, pagos, planilla, etc.) **no necesitas usar
> esto** — el sistema genera esos asientos solo, desde sus pantallas
> correspondientes. Usa esto solo para casos especiales que no tienen
> pantalla propia (ajustes, correcciones, préstamos entre socios, etc.).

1. Entra a la pestaña **"Asientos"** y toca **"Asiento manual"**.
2. Elige la **fecha** del movimiento (el sistema validará que el periodo
   de esa fecha esté abierto).
3. Escribe una **descripción** clara de qué es ("Ajuste por...",
   "Corrección de...", etc.).
4. Agrega **líneas**: por cada una, elige una **cuenta de detalle** del
   PCGE (no se pueden usar cuentas "de carpeta", solo las que admiten
   montos directos) y escribe el monto en **Débito** o en **Crédito**,
   más una glosa opcional explicando esa línea puntual.
5. Verifica el resumen que aparece abajo: debe decir que **Débitos =
   Créditos** (si no, el sistema no te dejará guardar).
6. Guarda.

### ¿Qué registro contable se forma?
Exactamente el que tú armaste, línea por línea — eso es lo especial de
esta pantalla: **tú decides qué cuentas PCGE se mueven**. Por eso es la
única pantalla del módulo donde se requiere conocimiento contable: el
sistema valida que cuadre matemáticamente, pero no valida que sea
"correcto" desde el punto de vista contable — esa responsabilidad es
tuya (o de quien tenga el permiso para hacerlo).

### Cosas a las que debo prestar atención
- Si tu asiento no cuadra (Débitos ≠ Créditos), revisa: ¿olvidaste una
  línea? ¿escribiste un monto en la columna equivocada?
- Usa la pestaña **"Cuentas"** (de esta misma pantalla) para buscar el
  código y nombre exacto de la cuenta PCGE que necesitas, **antes** de
  abrir el formulario de asiento manual.

---

# 2. Cuentas por Pagar (CxP)
### Pestañas: Facturas · Saldos · Pagos
### "Lo que la empresa debe a sus proveedores"

## 2.A — Registrar una factura de un proveedor (pestaña "Facturas")

### ¿Qué tengo que hacer?
1. Entra a la pestaña **"Facturas"** y toca el botón de **agregar**
   (nueva factura).
2. Llena el formulario:
   - **Proveedor** (el "tercero" que te vendió algo)
   - **Número de documento** (el número de la factura física/electrónica
     que recibiste)
   - **Fecha de emisión**
   - **Monto** (base, sin IGV) y, si aplica, el **IGV**
   - Cualquier otro dato pedido (concepto, glosa, vencimiento, etc.)
3. Guarda.
4. Si te equivocaste o la factura llegó duplicada/anulada por el
   proveedor, usa el botón **"Anular"** (con confirmación — esta acción
   no se puede deshacer).

### ¿Qué registro contable se forma? (PCGE — explicado en simple)
Al guardar, el sistema arma automáticamente un asiento que dice, en
esencia:
- **Sube** (entra al "Debe") la cuenta del **gasto, costo o activo** que
  corresponda según lo que compraste (ej. familia 60 — Compras, o la
  cuenta del activo si así corresponde)
- Si hay IGV, **sube** también la cuenta de **IGV — Crédito fiscal**
  (familia 40, subcuenta de IGV por cobrar a favor)
- **Sube** (entra al "Haber") la cuenta de **Cuentas por pagar
  comerciales — Terceros** (familia 42), que representa la deuda nueva
  con ese proveedor

En una frase: *"compré algo (o gané un crédito de IGV) y, a cambio,
ahora le debo ese monto a mi proveedor"*.

### Cosas a las que debo prestar atención
- Asegúrate de que la **fecha de emisión** caiga dentro de un periodo
  **abierto** — si no, el sistema rechazará el registro.
- Revisa bien el **monto y el IGV**: una vez guardada, la única forma de
  corregir es anulando (lo cual deja rastro) y volviendo a registrar.
- Si lo que compraste es una **máquina, vehículo o equipo que vas a usar
  por años** (no algo que se consume el mismo mes), avisa a quien
  administra Finanzas — probablemente eso debe registrarse también como
  **Activo fijo** (sección 4), que tiene un tratamiento especial
  (depreciación), y no solo como un gasto del mes.

## 2.B — Revisar cuánto le debes a cada proveedor (pestaña "Saldos")

### ¿Qué tengo que hacer?
Solo entra y consulta — esta pestaña **no tiene formularios**. Verás una
lista de proveedores con el saldo pendiente de cada uno (lo que te
facturaron menos lo que ya pagaste).

### ¿Qué registro contable se forma?
Ninguno — es un **resumen calculado en vivo** a partir de las facturas y
los pagos que ya registraste. No genera ni guarda nada nuevo.

### Cosas a las que debo prestar atención
- Si un saldo te parece raro ("¿por qué le debo tanto a este
  proveedor?"), ve al **Libro mayor** (sección 9) de la cuenta "Cuentas
  por pagar" y filtra — ahí verás, uno por uno, todos los movimientos
  que formaron ese saldo.

## 2.C — Registrar un pago a un proveedor (pestaña "Pagos")

### ¿Qué tengo que hacer?
1. Entra a la pestaña **"Pagos"** y toca **agregar** (nuevo pago).
2. Selecciona el **proveedor** y, normalmente, la(s) **factura(s)**
   específica(s) que estás cancelando (total o parcialmente).
3. Indica el **monto pagado**, la **fecha** y el **medio de pago**
   (efectivo, transferencia, etc.).
4. Guarda.

### ¿Qué registro contable se forma?
- **Baja** (entra al "Debe") la cuenta de **Cuentas por pagar
  comerciales — Terceros** (familia 42) — la deuda con ese proveedor
  disminuye
- **Baja** (entra al "Haber") la cuenta de **Caja o Bancos** (familia
  10) — el dinero realmente salió de la empresa

En una frase: *"le pagué al proveedor, así que ya no le debo tanto, y mi
banco/caja tiene menos plata"*.

### Cosas a las que debo prestar atención
- Vincula siempre el pago con la(s) **factura(s)** correspondiente(s) —
  así el saldo de "Saldos" (2.B) queda correcto y rastreable.
- Verifica el **medio de pago**: si registras "efectivo" cuando en
  realidad fue transferencia (o viceversa), la cuenta de banco/caja que
  se mueve será la incorrecta, y luego el balance de comprobación podría
  no coincidir con tu estado de cuenta bancario real.

---

# 3. Cuentas por Cobrar (CxC)
### Pestañas: Comprobantes · Saldos · Cobros
### "Lo que los clientes deben a la empresa" — el espejo del capítulo anterior

## 3.A — Registrar un comprobante emitido a un cliente (pestaña "Comprobantes")

### ¿Qué tengo que hacer?
1. Entra a **"Comprobantes"** y toca **agregar** (nueva factura/boleta
   emitida).
2. Llena: **cliente**, **número de comprobante**, **fecha de emisión**,
   **monto (base)** y **IGV** si corresponde.
3. Guarda.
4. Para anular (con confirmación, acción irreversible): botón
   **"Anular"**.

### ¿Qué registro contable se forma?
- **Sube** (Debe) la cuenta de **Cuentas por cobrar comerciales —
  Terceros** (familia 12) — ahora ese cliente te debe ese monto
- **Sube** (Haber) la cuenta de **Ventas / Ingresos por servicios**
  (familia 70) — registraste un ingreso
- Si hay IGV, también sube (Haber) la cuenta de **IGV — Débito fiscal**
  (familia 40) — ese IGV lo cobraste "para" la SUNAT, no es tuyo

En una frase: *"le vendí algo a un cliente: gané un ingreso, ahora me
debe ese dinero, y además cobré un IGV que tendré que entregarle al
Estado"*.

### Cosas a las que debo prestar atención
- El **monto y el IGV** deben coincidir exactamente con el comprobante
  físico/electrónico emitido — esta información alimenta directamente el
  "Registro de ventas" que se presenta a la SUNAT (sección 6).
- Verifica la **fecha de emisión** vs. el periodo abierto, igual que en
  CxP.

## 3.B — Revisar cuánto te debe cada cliente (pestaña "Saldos")

### ¿Qué tengo que hacer?
Solo consultar — sin formularios, igual que en CxP (2.B), pero en
espejo: aquí ves cuánto te debe cada cliente.

### ¿Qué registro contable se forma?
Ninguno — resumen calculado en vivo.

## 3.C — Registrar un cobro recibido de un cliente (pestaña "Cobros")

### ¿Qué tengo que hacer?
1. Entra a **"Cobros"**, toca **agregar** (nuevo cobro).
2. Selecciona **cliente** y el/los **comprobante(s)** que está cancelando.
3. Indica **monto recibido**, **fecha** y **medio de pago**.
4. Guarda.

### ¿Qué registro contable se forma?
- **Baja** (Haber) la cuenta de **Cuentas por cobrar comerciales —
  Terceros** (familia 12) — el cliente ya te debe menos
- **Sube** (Debe) la cuenta de **Caja o Bancos** (familia 10) — entró
  dinero real a la empresa

En una frase: *"el cliente me pagó: ya no me debe (tanto), y mi
banco/caja tiene más plata"*.

### Cosas a las que debo prestar atención
- Esta es la operación que alimenta el **Flujo de efectivo** (sección 9)
  como una "entrada real" — recuerda: vender no es lo mismo que cobrar.
  Si nunca registras el cobro, el sistema seguirá mostrando ese cliente
  como "pendiente" para siempre, aunque ya te haya pagado en la vida
  real.
- Igual que en pagos a proveedores: vincula el cobro al/los
  **comprobante(s)** correctos para que "Saldos" (3.B) refleje la
  realidad.

---

# 4. Activos fijos
### "Las máquinas, vehículos y equipos que la empresa usa por años"

## 4.A — Dar de alta un activo nuevo (botón "Nuevo activo")

### ¿Qué tengo que hacer?
1. Toca **"Nuevo activo"** (visible solo si tienes el permiso de
   gestionar activos).
2. Llena: **nombre/descripción**, **valor de adquisición** (lo que
   costó), **vida útil** (en meses — ej. 60 meses = 5 años), **fecha de
   compra**, y cualquier dato adicional pedido (categoría, ubicación,
   proveedor, etc.).
3. Guarda.

### ¿Qué registro contable se forma?
El alta del activo, por sí sola, **da de alta el bien en el catálogo de
activos fijos** — habilita que, mes a mes, se le calcule depreciación.
El asiento que reconoce contablemente la compra normalmente **ya se
generó al registrar la factura en Cuentas por Pagar** (sección 2.A) — es
decir, esta pantalla y la de CxP están conectadas: una registra "que
debo por esta compra" y esta otra registra "que tengo este bien y voy a
seguir su vida útil".

### Cosas a las que debo prestar atención
- **Avisa primero a quien administra Finanzas** cuando hagas una compra
  grande (vehículo, maquinaria, equipo costoso): hay que decidir si se
  registra como **gasto del mes** (CxP normal) o como **Activo fijo**
  (con depreciación) — la diferencia importa mucho para los reportes.
- Verifica bien la **vida útil en meses**: un número equivocado aquí
  hace que la depreciación mensual (4.B) salga mal durante todo el
  tiempo de vida del activo.

## 4.B — Procesar la depreciación del mes (botón con ícono de calculadora)

### ¿Qué tengo que hacer?
1. Una vez al mes (normalmente al cierre, **antes de cerrar el periodo**
   en la sección 1.B), entra a **Activos fijos** y toca el botón de
   **procesar depreciación** (ícono de calculadora — visible solo para
   quien gestiona activos).
2. Confirma. El sistema recorrerá **todos** los activos activos del mes
   y calculará lo que corresponde a cada uno automáticamente — no hay
   que hacerlo activo por activo.

### ¿Qué registro contable se forma?
- **Sube** (Debe) la cuenta de **Gasto por depreciación** (familia 68)
- **Sube** (Haber) la cuenta de **Depreciación acumulada** (familia
  39 — una "contracuenta" que reduce el valor en libros del activo, sin
  borrar el dato de cuánto costó originalmente)

En una frase: *"este mes, mis máquinas perdieron un poco de valor por el
uso del tiempo — eso es un gasto, y queda anotado sin perder el rastro
de cuánto costaron originalmente"*.

### Cosas a las que debo prestar atención
- Hazlo **una sola vez por mes**, y **antes** de cerrar ese periodo —
  si lo olvidas y cierras el mes, después será mucho más difícil
  corregirlo (habría que reabrir el periodo).
- El sistema **no te dejará procesar** la depreciación de un mes cuyo
  periodo está cerrado.
- Esta operación **no saca dinero real del banco** — es un ajuste
  contable. Por eso, después, notarás que el "Estado de resultados" baja
  por este concepto pero el "Flujo de efectivo" no se mueve — eso es
  normal y esperado.

---

# 5. Planilla
### Pestañas: Conceptos remunerativos · Planillas

## 5.A — Consultar el catálogo de conceptos (pestaña "Conceptos remunerativos")

### ¿Qué tengo que hacer?
Solo consultar — verifica qué "ingredientes" del sueldo existen
configurados (sueldo base, horas extra, bonificaciones, descuentos,
aportes, etc.) **antes** de calcular o revisar una planilla, para
entender de qué está compuesto el neto de cada trabajador.

### ¿Qué registro contable se forma?
Ninguno — es de referencia.

## 5.B — Calcular la planilla del mes (pestaña "Planillas")

### ¿Qué tengo que hacer?
1. Entra a **"Planillas"**, toca **"Calcular"** (o el botón equivalente
   de nueva planilla).
2. Elige el **periodo** (mes) que vas a calcular.
3. Confirma. El sistema recorrerá a todos los trabajadores activos,
   aplicará los conceptos que correspondan a cada uno, y generará la
   planilla en estado **"calculada"**.

### ¿Qué registro contable se forma?
Al **calcular/aprobar**:
- **Sube** (Debe) la cuenta de **Gastos de personal — sueldos y cargas
  sociales** (familia 62)
- **Sube** (Haber) las cuentas de **Remuneraciones por pagar** (familia
  41) y **Aportes/tributos por pagar a entidades** (familia 40/41 según
  el concepto: ESSALUD, ONP/AFP, renta de 5ta categoría, etc.)

En una frase: *"este mes generé un gasto de personal, y ahora le debo
ese dinero a mis trabajadores y al Estado (por los aportes y
descuentos)"*.

## 5.C — Aprobar la planilla calculada

### ¿Qué tengo que hacer?
1. Abre la planilla en estado **"calculada"**, revísala (montos por
   trabajador, totales).
2. Si está correcta, toca **"Aprobar"** (requiere permiso de
   aprobación — normalmente un cargo de jefatura/administración).

### ¿Qué registro contable se forma?
Según cómo esté configurado el flujo, la aprobación puede confirmar /
completar el asiento de "gasto + deuda" descrito en 5.B (algunos
sistemas generan el asiento recién al aprobar, para evitar registrar
algo que todavía podría corregirse).

### Cosas a las que debo prestar atención
- **Revisa los montos antes de aprobar** — una vez aprobada, corregir
  significa más pasos administrativos que simplemente "editar".

## 5.D — Pagar la planilla aprobada

### ¿Qué tengo que hacer?
1. Abre la planilla en estado **"aprobada"**, toca **"Pagar"** (o
   "Marcar como pagada").
2. Indica fecha y medio de pago si el formulario lo solicita.

### ¿Qué registro contable se forma?
- **Baja** (Debe) las cuentas de **Remuneraciones / aportes por pagar**
  (familias 40/41) — la deuda con trabajadores y entidades disminuye
- **Baja** (Haber) la cuenta de **Caja o Bancos** (familia 10) — salió
  dinero real

En una frase: *"les pagué a mis trabajadores (y/o entidades): ya no les
debo, y mi banco/caja tiene menos plata"* — exactamente el mismo patrón
que pagar a un proveedor (sección 2.C), solo que aquí "el proveedor" es
el trabajador (y el Estado).

### Cosas a las que debo prestar atención
- Sigue el ciclo en orden: **calcular → aprobar → pagar**. No se puede
  saltar pasos — cada estado habilita la siguiente acción según tus
  permisos.
- Hazlo dentro de un periodo **abierto**; si necesitas pagar planilla de
  un mes ya cerrado, debe reabrirse primero (caso excepcional).

---

# 6. Tributario / IGV
### Pestañas: Compras · Ventas · Configuración

## 6.A — Configurar el régimen y las cuentas de IGV (pestaña "Configuración")

> ⚠️ Esto normalmente se hace **una sola vez**, al iniciar a usar el
> módulo, y solo se vuelve a tocar si cambian las reglas tributarias del
> negocio. Solo personas con el permiso `tributario:configurar` pueden
> modificarlo.

### ¿Qué tengo que hacer?
1. Entra a **"Configuración"**.
2. Selecciona el **régimen tributario** de la empresa (define, entre
   otras cosas, la tasa de IGV — normalmente 18%).
3. Indica **qué cuenta del PCGE representa "IGV — Crédito fiscal"** y
   **cuál representa "IGV — Débito fiscal"** (ambas de la familia 40).
4. Guarda.

### ¿Qué registro contable se forma?
Ninguno directamente — pero esta configuración es **el "traductor"** que
le dice al sistema, de ahora en adelante, en qué cuenta exacta anotar el
IGV cada vez que se registre una factura de compra (CxP, sección 2.A) o
un comprobante de venta (CxC, sección 3.A).

### Cosas a las que debo prestar atención
- **Un cambio aquí afecta TODAS las facturas futuras** — no las pasadas.
  Si necesitas cambiarlo, hazlo con cuidado y, de preferencia, al cierre
  de un mes (no a mitad de operaciones).

## 6.B — Consultar los registros de Compras y Ventas (pestañas "Compras" / "Ventas")

### ¿Qué tengo que hacer?
Solo consultar — **no hay nada que registrar aquí**. Elige el periodo y
revisa el detalle: cada factura de compra/venta del mes, con su base
imponible, su IGV y su total, más los tres totales resumidos arriba
(Base, IGV, Total).

### ¿Qué registro contable se forma?
Ninguno — esta información **ya se generó sola** cuando registraste las
facturas en CxP (2.A) y los comprobantes en CxC (3.A). Esta pantalla
solo las re-organiza desde el punto de vista tributario, lista para tu
declaración mensual a la SUNAT.

### Cosas a las que debo prestar atención
- Si algo "no aparece" aquí que debería, **el problema no está en esta
  pantalla** — ve y revisa si esa factura/comprobante realmente se
  registró (y con la fecha correcta) en CxP o CxC.
- Usa esta pantalla como tu **checklist final antes de declarar el IGV**
  del mes a la SUNAT — los totales de Base e IGV que ves aquí deberían
  coincidir con lo que vas a declarar.

---

# 7. Centros de costo
### Catálogo + Detalle con comparativo presupuesto vs. real

## 7.A — Crear / editar / desactivar un centro de costo

### ¿Qué tengo que hacer?
1. Entra a **"Centros de costo"** (necesitas el permiso
   `controlling:gestionar_centros_costo`).
2. Para **crear**: toca **agregar**, llena **código**, **nombre**,
   **tipo** (libre / proyecto / área / empleado) y, opcionalmente, un
   **presupuesto referencial**.
3. Para **editar**: toca el centro existente y modifica sus datos.
4. Para **desactivar**: usa la opción correspondiente (no borra el
   historial — solo deja de estar disponible para nuevas imputaciones).

### ¿Qué registro contable se forma?
Ninguno — esta pantalla solo gestiona **"etiquetas"**. La parte
contable real ocurre cuando, **al registrar otras operaciones** (una
factura en CxP, una salida de almacén en Inventario, una planilla, etc.)
**se le asigna esta etiqueta** a esa operación.

### Cosas a las que debo prestar atención
- Crea el centro de costo **antes** de empezar a registrar gastos del
  proyecto/área correspondiente — si registras gastos sin etiquetarlos,
  después no aparecerán en el comparativo, aunque sí estarán
  correctamente contabilizados en general.
- Define un **presupuesto referencial realista** — es la base contra la
  que se va a comparar todo el seguimiento posterior.

## 7.B — Revisar el comparativo presupuesto vs. costo real (detalle del centro de costo)

### ¿Qué tengo que hacer?
1. Toca un centro de costo de la lista.
2. Elige un **rango de fechas** (selector "desde / hasta").
3. Revisa: **costo real**, **presupuesto**, **desviación** (verde =
   gastaste menos de lo previsto, rojo = gastaste más) y **% de
   ejecución** (si pasa de 100%, alerta de sobrecosto).

### ¿Qué registro contable se forma?
Ninguno — es, otra vez, un **resumen calculado en vivo**, pero esta vez
filtrado por la "etiqueta" del centro de costo, sumando todos los
asientos contables que ya se generaron en otras pantallas y que llevaban
esa etiqueta.

### Cosas a las que debo prestar atención
- Si el comparativo "no cuadra con lo que tú sabes que se gastó", la
  causa más probable es que **alguna operación no se etiquetó con este
  centro de costo** al momento de registrarse — revisa con quien
  registró esa operación si marcó la etiqueta correcta.
- Revísalo **periódicamente** (no solo al final) — para detectar
  sobrecostos a tiempo de corregir el rumbo, no cuando ya es tarde.

---

# 8. Inventario valorizado
### Pestañas: Kardex · Costo promedio — y el botón "Movimiento"

## 8.A — Registrar un ingreso de mercadería al almacén (botón "Movimiento" → "Ingreso")

### ¿Qué tengo que hacer?
1. Toca **"Movimiento"** (visible con el permiso
   `inventario_valorizado:registrar_movimiento`) y elige **"Ingreso"**.
2. Busca el **material** (autocompletar desde el catálogo de logística),
   elige el **almacén**.
3. Ingresa la **cantidad** y el **costo unitario** al que se compró
   (este dato es **obligatorio** — sin él, el sistema no puede recalcular
   el costo promedio).
4. Agrega un motivo si quieres dejar más contexto.
5. Guarda.

### ¿Qué registro contable se forma?
- **Sube** (Debe) la cuenta de **Inventario / Mercaderías o Materiales**
  (familia 20-25, según el tipo de material)
- **Baja o sube**, según corresponda, la cuenta de origen: si la compra
  ya se registró como factura en CxP, esto puede reflejarse contra esa
  deuda; si fue al contado, contra **Caja/Bancos**

En una frase: *"entró mercadería al almacén — el valor de mi inventario
sube, y eso vino de algún lado (una deuda con el proveedor o una salida
de caja)"*.

### Cosas a las que debo prestar atención
- El **costo unitario que ingreses aquí debe ser el real de esa compra**
  — es justamente el dato que el sistema usa para recalcular el "costo
  promedio ponderado" de ese material en ese almacén. Un costo
  equivocado aquí distorsiona el valor del inventario hasta la próxima
  entrada.
- Verifica que estés eligiendo el **almacén correcto** — el costo
  promedio se calcula **por combinación material + almacén**, no de
  forma global.

## 8.B — Registrar una salida de mercadería del almacén (botón "Movimiento" → "Salida")

### ¿Qué tengo que hacer?
1. Toca **"Movimiento"** → **"Salida"**.
2. Busca el **material**, elige el **almacén**, ingresa la **cantidad**.
3. **No necesitas indicar el costo** — el sistema lo calcula solo, al
   "costo promedio" vigente en ese momento.
4. Si esta salida corresponde a un proyecto/área específico, **asegúrate
   de etiquetarla con el centro de costo correspondiente** (si el
   formulario lo permite) — así aparecerá en el comparativo de la
   sección 7.
5. Agrega un motivo y guarda.

### ¿Qué registro contable se forma?
- **Baja** (Haber) la cuenta de **Inventario / Mercaderías o Materiales**
  — el valor de lo que tienes guardado disminuye
- **Sube** (Debe) una cuenta de **Costo / Gasto de producción o de
  servicio** (familia 61/65 según el caso) — ese material "se convirtió"
  en un costo del trabajo realizado

En una frase: *"salió mercadería del almacén para usarla en un trabajo —
mi inventario vale menos, y ese valor ahora es un costo de ese
trabajo"*.

### Cosas a las que debo prestar atención
- **Etiqueta la salida con el centro de costo del proyecto** si
  corresponde — de lo contrario, ese costo "se perderá" desde la óptica
  del comparativo presupuesto vs. real (sección 7), aunque sí quedará
  bien contabilizado en general.
- Si la cantidad que intentas sacar es mayor a la que hay disponible, el
  sistema debería impedir o advertir la operación — revisa el saldo en
  el **Kardex** (8.C) antes de registrar salidas grandes.

## 8.C — Consultar el Kardex y el costo promedio (pestañas "Kardex" / "Costo promedio")

### ¿Qué tengo que hacer?
Solo consultar:
- En **"Kardex"**: filtra por almacén y revisa el saldo valorizado
  (cantidad y valor total al costo promedio vigente) de cada material.
- En **"Costo promedio"**: busca un material puntual, elige almacén, y
  consulta cantidad, costo unitario promedio y valor total actual.

### ¿Qué registro contable se forma?
Ninguno — son **vistas de consulta**, alimentadas por los movimientos
que registraste en 8.A y 8.B.

### Cosas a las que debo prestar atención
- Antes de registrar una **salida grande**, revisa aquí si realmente hay
  suficiente cantidad disponible.
- Si el "costo promedio" de un material te parece extraño (muy alto o
  muy bajo), revisa el historial de **ingresos** — probablemente uno de
  ellos se registró con un costo unitario incorrecto.

---

# 9. Reportes financieros
### Pestañas: Balance general · Resultados · Flujo de efectivo · Libro diario · Libro mayor

## ¿Qué tengo que hacer aquí?

**Nada que "registrar"** — esta pantalla es 100% de consulta. Aquí es
donde **revisas el resultado** de todas las acciones que hiciste en las
secciones 1 a 8. Es tu "panel de control" para verificar que todo esté
en orden, especialmente antes de cerrar un periodo (sección 1.B).

| Pestaña | ¿Para qué la uso? |
|---|---|
| **Balance general** | "¿Qué tiene la empresa hoy, y a quién se lo debe?" — elige una fecha de corte y revisa que Activo = Pasivo + Patrimonio (aviso verde). |
| **Resultados** | "¿Gané o perdí plata este mes?" — revisa ingresos vs. gastos del periodo y la utilidad/pérdida resultante. |
| **Flujo de efectivo** | "¿Cuánto dinero REAL entró y salió?" — útil para detectar si "vendiste mucho" pero "cobraste poco" (dos cosas distintas). |
| **Libro diario** | "Lista cronológica de TODOS los asientos del mes" — útil para revisar, en orden, todo lo que pasó. |
| **Libro mayor** | "La historia completa de UNA cuenta específica" — elige una cuenta (ej. "Cuentas por pagar — proveedores") y mira, paso a paso, cómo llegó a su saldo actual. |

### ¿Qué registro contable se forma?
Ninguno — todo lo que ves aquí es un **resumen calculado en vivo** sobre
los asientos que ya generaste (automáticamente o a mano) en las demás
pantallas. Si algo se ve raro acá, el origen del problema **no está en
esta pantalla** — está en alguna de las acciones de las secciones 1-8, y
el **Libro mayor** es tu mejor herramienta para rastrearlo hasta su
asiento exacto.

### Cosas a las que debo prestar atención
- Antes de cerrar un periodo (1.B), revisa especialmente el **Balance
  general** (¿cuadra la ecuación?) y el balance de comprobación de la
  pestaña "Comprobación" (sección 1).
- Si un número no te cuadra con lo que esperabas, **no lo "ajustes" acá**
  — esta pantalla no permite editar nada. Ve a la operación original
  (factura, pago, planilla, movimiento de almacén) y corrígela ahí (o,
  si ya no se puede, usa un asiento manual de ajuste — sección 1.C, y
  con apoyo de quien sabe contabilidad).

---

# 10. Checklist mensual recomendado
### El orden sugerido de tareas para que todo quede correcto y a tiempo

Esta es una guía de **flujo operativo** — el orden en que normalmente
conviene hacer las cosas durante un mes, para que al final todo cuadre
sin sobresaltos:

**Al INICIO del mes:**
1. ☐ **Abrir el periodo** del nuevo mes (sección 1.A) — sin esto, nada
   de lo que sigue se podrá registrar.

**Durante el mes (a medida que ocurren los hechos):**
2. ☐ Registrar cada **factura de proveedor** que llegue (2.A)
3. ☐ Registrar cada **pago a proveedores** que se haga (2.C)
4. ☐ Registrar cada **comprobante emitido a clientes** (3.A)
5. ☐ Registrar cada **cobro recibido de clientes** (3.C)
6. ☐ Registrar cada **ingreso y salida de almacén** a medida que ocurren,
   etiquetando con el **centro de costo** correspondiente cuando
   corresponda (8.A, 8.B)
7. ☐ Si compraste un **activo fijo** nuevo, darlo de alta (4.A)

**Al CIERRE del mes (en este orden):**
8. ☐ **Calcular, aprobar y pagar la planilla** del mes (5.B → 5.C → 5.D)
9. ☐ **Procesar la depreciación** de activos fijos (4.B)
10. ☐ Revisar el **Balance de comprobación** (pestaña "Comprobación",
    sección 1) — debe estar en verde ("Debe = Haber")
11. ☐ Revisar el **Balance general** y el **Estado de resultados**
    (sección 9) — ¿tienen sentido los números?
12. ☐ Revisar **Tributario → Compras / Ventas** (6.B) — son tus
    registros listos para la declaración a la SUNAT
13. ☐ Revisar el **comparativo de Centros de costo** (7.B) si la empresa
    tiene proyectos/áreas en seguimiento
14. ☐ Si todo está en orden: **cerrar el periodo** (sección 1.B)

> 💡 **Regla de oro**: cualquier cosa que se te quede pendiente de
> registrar **antes** de cerrar el periodo será mucho más difícil de
> corregir después (requiere reabrir el mes — un procedimiento
> excepcional). Si tienes dudas sobre si ya registraste todo, repasa
> esta checklist antes de tocar "Cerrar periodo".

---

## Cierre

Si seguiste este manual paso a paso, ya sabes **exactamente qué hacer en
cada pantalla** y, sobre todo, **por qué cada acción tuya termina
formando, sola, el asiento contable correcto que exige el PCGE** — sin
que tengas que escribir débitos ni créditos a mano (salvo en el caso
especial del asiento manual, sección 1.C). Tu trabajo es simple: **registra
los hechos reales del negocio, en el momento en que ocurren, con datos
correctos y completos** — el sistema se encarga de "traducir" eso al
lenguaje contable que la empresa necesita para sus reportes, su gestión
y sus obligaciones ante la SUNAT.
