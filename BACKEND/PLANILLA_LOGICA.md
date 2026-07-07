# Lógica completa de Planilla (E-zyro) — Backend

> Documento de referencia técnica, generado el 2026-07-07 a partir del código real
> (`BACKEND/app/services/planilla_calculo_service.py`,
> `planilla_asistencia_service.py`, `planilla_service.py`,
> `routers/planilla.py`, `schemas/planilla.py`). No es aspiracional: cada
> fórmula acá descrita es exactamente la que corre hoy en producción.

---

## 1. Flujo de datos, de punta a punta

```
┌─────────────────────┐
│ RegistroAsistencia   │  (marcaciones reales: entrada/salida/almuerzo)
│ SolicitudLaboral     │  (permisos, justificaciones, permanencia_extra)
│ Turno / TurnoEmpleado│  (jornada pactada por empleado)
│ FeriadoEmpresa       │  (feriados que la EMPRESA registró manualmente)
└─────────┬────────────┘
          │  planilla_asistencia_service.resumen_horas_periodo(db, empresa_id, inicio, fin)
          ▼
┌──────────────────────────────────────────────────────────┐
│ Por empleado: horas_reales, horas_justificadas,           │
│ horas_faltantes, meta_horas, horas_extra,                  │
│ horas_extra_aprobadas, horas_extra_no_autor,               │
│ horas_domingo, horas_feriado, dias_laborados, porcentaje   │
└─────────┬──────────────────────────────────────────────────┘
          │  + sueldo_base (EmpleadoConcepto → concepto SUELDO_BASE)
          │  + config previsional (EmpleadoPlanillaConfig: pensión, AFP, asig. familiar)
          ▼
┌──────────────────────────────────────────────────────────┐
│ InsumoEmpleado  (dataclass, sin BD)                        │
└─────────┬──────────────────────────────────────────────────┘
          │  planilla_calculo_service.calcular_boleta_empleado(insumo, regimen_empresa, periodo_pago)
          ▼
┌──────────────────────────────────────────────────────────┐
│ DesgloseBoleta  (dataclass, sin BD) — TODOS los montos      │
│ sueldo_devengado, pago_horas_extra, pago_domingo,          │
│ pago_feriado, asignacion_familiar, descuento_pension,       │
│ renta_5ta, total_ingresos, total_descuentos_legales,        │
│ neto_a_pagar, aporte_essalud, provisiones CTS/Grati/Vac.    │
└─────────┬──────────────────────────────────────────────────┘
          │
          ├──► GET /planilla/preview  →  SOLO LECTURA, no escribe nada en BD
          │
          └──► POST /planilla/calcular (planilla_service.calcular_planilla)
                     │  escribe Planilla + BoletaPago + BoletaPagoDetalle (estado "calculada")
                     ▼
               POST /planilla/{id}/aprobar   → asiento contable de PROVISIÓN, estado "aprobada"
                     ▼
               POST /planilla/{id}/marcar-pagada → asiento contable de PAGO, estado "pagada"

               (alternativa desde "calculada": POST /planilla/{id}/anular → estado "anulada",
                libera el período para volver a calcular)
```

**Punto clave:** el motor de cálculo (`planilla_calculo_service.py`) **no toca la base de datos**. Recibe un `InsumoEmpleado` ya resuelto y devuelve un `DesgloseBoleta`. Esto es deliberado (testeable de forma aislada, sin mocks de BD) y significa que **cualquier error de cálculo real está o bien en cómo se arma el `InsumoEmpleado`** (la parte que sí toca BD, en `planilla_asistencia_service.py` / `planilla_service.py` / `routers/planilla.py`) **o en las fórmulas puras** (`planilla_calculo_service.py`).

---

## 2. `resumen_horas_periodo` — de dónde salen las horas

Archivo: `app/services/planilla_asistencia_service.py`

Para cada empleado activo de la empresa, en el rango `[inicio, fin]`:

1. **`dias_lab`** = todos los días del rango con `weekday() < 6` (Lunes a **Sábado**; el Domingo queda excluido por construcción — `_dias_laborables`, en `rrhh_asistencia.py`).
2. **`feriados`** = fechas registradas en la tabla `FeriadoEmpresa` para esa empresa en el rango (`_feriados_set`). **Esto NO es una lista nacional automática — depende 100% de que RRHH haya cargado el feriado manualmente** en la pantalla de Feriados. Si no lo cargó, ese día se trata como un día laborable normal (sin sobretasa).
3. **`domingos`** = todas las fechas del rango con `weekday() == 6`, calculadas aparte (no vienen de `dias_lab`, que ya los excluye).
4. **`feriados_trabajables`** = `feriados` que **NO** caen en domingo (evita pagar la sobretasa dos veces el mismo día).

Por cada empleado:

- **`horas_domingo`**: suma de `_horas_dia(registros)` para cada día en `domingos`. `_horas_dia` = (hora salida − hora entrada) − (almuerzo si hay entrada/salida de almuerzo registradas). Si no hay entrada+salida ese día → 0.
- **`horas_feriado`**: mismo cálculo, para cada día en `feriados_trabajables`.
- Para cada día en `dias_lab` (excluyendo feriados registrados):
  - Se resuelve el turno vigente del empleado ese día (`_info_turno_dia` → horas requeridas del turno y qué días de la semana son laborables para ESE turno). Si no tiene turno asignado: **default 8h, Lunes-Viernes**.
  - Si el día no es laborable para el turno del empleado (`dia.weekday() not in dias_turno`) → se salta (no cuenta ni como meta ni como falta).
  - `meta_horas_emp += req_h` (la meta se acumula por turno real, no una jornada fija de 8h para todos).
  - Si el día está cubierto por una `SolicitudLaboral` **aprobada** (tipo distinto de `justificacion_tardanza`/`permanencia_extra`) → cuenta como `horas_justificadas` (con el valor pleno del turno, no 0).
  - Si no → se suman las horas reales marcadas ese día a `horas_reales`; si `h > 0`, cuenta como `dias_laborados`.
- **`horas_total`** = `horas_reales + horas_justificadas`.
- **`horas_faltantes`** = `max(0, meta_horas − horas_total)`.
- **`horas_extra`** = `max(0, horas_total − meta_horas)` — **informativo en esta capa**, el motor de cálculo lo recalcula por su cuenta con la misma fórmula pero a partir de `horas_reales`/`meta_horas` puros (ver §3).
- **`horas_extra_aprobadas`**: `min(horas_extra, suma de SolicitudLaboral tipo="permanencia_extra" y estado="aprobada", campo `dias`)`. **Ojo:** el campo `dias` del modelo `SolicitudLaboral` almacena HORAS cuando `tipo == "permanencia_extra"` (nombre de columna engañoso, es así en todo el código).
- **`horas_extra_no_autor`** = `horas_extra − horas_extra_aprobadas`.

### Posibles causas de "algo está fallando" en esta capa

- **Feriado sin registrar** → nunca se detecta `horas_feriado`, nunca se paga la sobretasa. Verificar que el feriado esté cargado en el módulo de Feriados de la empresa, con la fecha exacta.
- **Turno mal configurado o sin asignar** → cae al default 8h L-V; si el empleado en realidad trabaja otro horario/días, `meta_horas` y por tanto `horas_extra`/`horas_faltantes` salen mal.
- **Falta el registro de `salida`** ese día → `_horas_dia` devuelve 0 aunque haya marcado entrada (se necesitan AMBOS: entrada y salida).
- **Solicitud de "permanencia_extra" con estado ≠ "aprobada"** → no cuenta para `horas_extra_aprobadas`, aparece como "sin trámite" en la boleta (comportamiento esperado, ver §3.2).

---

## 3. `calcular_boleta_empleado` — el motor de cálculo puro

Archivo: `app/services/planilla_calculo_service.py`. Sin acceso a BD. Todo en `Decimal`, sin redondear valores intermedios (solo se redondea al mostrar/serializar).

### 3.1 Sueldo devengado (reemplaza el "sueldo completo menos descuento aproximado" del diseño original)

```
sueldo_periodo = sueldo_base                    si periodo_pago == "mes"
               = sueldo_base / 2                 si es quincena (q1/q2) — mitad exacta, NO prorrateo por días

valor_dia    = sueldo_base / 30
valor_hora   = valor_dia / 8
valor_minuto = valor_hora / 60          (valor_dia/hora/minuto SIEMPRE sobre el sueldo MENSUAL completo,
                                          nunca sobre sueldo_periodo)

proporcion_asistencia = (meta_horas − horas_faltantes) / meta_horas     (clamp [0, 1])
                       = 1                                               si meta_horas == 0

sueldo_devengado = sueldo_periodo × proporcion_asistencia
```

**Por qué:** si `proporcion_asistencia = 0` (faltó el mes entero), `sueldo_devengado = 0` y en cascada `neto_a_pagar = 0`. El diseño anterior (fórmula del TS original) dejaba un residuo de pago incluso con 0% de asistencia — se corrigió deliberadamente en esta migración.

`dias_faltantes`, `minutos_tardanza`, `descuento_dominical` se siguen calculando pero son **puramente informativos** (para mostrar "por qué" en la boleta) — no participan en el cálculo del neto, porque el descuento real ya está reflejado en `sueldo_devengado`.

### 3.2 Horas extra

```
horas_extra           = max(0, horas_reales − meta_horas)                         ← INFORMATIVO, sin truncar
horas_extra_pagables  = floor(horas_extra)                                        ← lo que SÍ se paga

si horas_extra_pagables <= 0:        pago_horas_extra = 0
si es practicante:                    pago_horas_extra = horas_extra_pagables × valor_hora        (tarifa simple, 1x)
si es dependiente (planilla/contrato):
    h1 = min(horas_extra_pagables, 2) × valor_hora × 1.25     (2 primeras horas, recargo 25%)
    h2 = max(0, horas_extra_pagables − 2) × valor_hora × 1.35  (resto, recargo 35%)
    pago_horas_extra = h1 + h2

horas_extra_sin_tramite = max(0, horas_extra_pagables − horas_extra_aprobadas)     ← SOLO ALERTA
```

**Dos reglas de negocio decididas explícitamente con el usuario (2026-07-06), ambas DESVÍAN la ley en un sentido u otro — no son bugs, son decisiones documentadas:**

1. **Solo se paga la hora ya COMPLETADA** (`floor`, no la fracción proporcional). El D.S. 007-2002-TR en realidad exige pagar también la fracción de hora cuando el sobretiempo es menor a una hora completa — esta es una desviación deliberada MENOS generosa que la ley, pedida explícitamente por el usuario después de exponerle el conflicto legal.
2. **El pago NUNCA se bloquea por falta de trámite de "Permanencia Extra" aprobado.** SUNAFIL presume autorización tácita con el solo registro de asistencia (la carga de la prueba de que NO hubo autorización es del empleador). Por eso `horas_extra_sin_tramite` es solo una **alerta informativa** para que RRHH regularice el papeleo — nunca reduce `pago_horas_extra`.

### 3.3 Domingo y feriado trabajados

```
factor = 1   si es practicante (Ley 28518, sin relación laboral formal → sin sobretasa)
       = 2   si es dependiente (D.Leg. 713 Art. 3/4 domingo, Art. 8/9 feriado)

pago_domingo = horas_domingo × valor_hora × factor
pago_feriado = horas_feriado × valor_hora × factor
```

Ambos son remuneración computable real: entran a `base_pension` y a `total_ingresos` (a diferencia de CTS/Gratificación/Vacaciones, que son solo informativos). `horas_feriado` ya viene deduplicado contra `horas_domingo` desde la capa de asistencia (§2).

### 3.4 Asignación familiar

```
si NO es dependiente, o regimen_empresa != "general", o !tiene_asignacion_familiar:
    asignacion_familiar = 0
si no:
    mensual = RMV_vigente × 10%            (S/ 113.00 con RMV = S/ 1130)
    mensual = mensual / 2                   si es quincena
    asignacion_familiar = mensual × proporcion_asistencia   (prorrateada igual que el sueldo)
```

Solo Régimen General (D.S. 035-90-TR), solo dependientes, solo si el flag `tiene_asignacion_familiar` está activo en `EmpleadoPlanillaConfig`.

### 3.5 Base de pensión y descuentos

```
base_pension = sueldo_devengado + pago_horas_extra + asignacion_familiar + pago_domingo + pago_feriado
             (0 si no es dependiente)

si sistema_pension == "onp":
    descuento_pension = base_pension × 13%

si sistema_pension == "afp":
    comision_pct = comision_afp_personalizada si el empleado la tiene, si no la tasa oficial de su entidad:
        integra 1.55% | prima 1.60% | profuturo 1.69% | habitat 1.47%   (entidad default: "integra")
    descuento_pension = base_pension × (10% aporte + 1.37% seguro + comision_pct)
    afp_aporte_obligatorio = base_pension × 10%
    afp_prima_seguro       = base_pension × 1.37%
    afp_comision           = base_pension × comision_pct
```

### 3.6 EsSalud (aporte del empleador, no se descuenta al trabajador)

```
aporte_essalud = sueldo_devengado × 9%
```

**Fidelidad deliberada a una particularidad ya presente en el diseño original:** se calcula para AMBAS modalidades (dependiente y practicante), no está condicionado por `es_dependiente`. No se "corrigió" en la migración.

### 3.7 CTS / Gratificación / Vacaciones — SOLO INFORMATIVOS

No afectan el neto del mes (se pagan en su fecha real: CTS mayo/noviembre, gratificación julio/diciembre).

```
si NO es dependiente o regimen_empresa == "micro":  provision_cts = provision_gratificacion = 0
si no:
    factor_cts   = 1/12  (Régimen General, 1 remuneración/año)  |  1/24  (Pequeña Empresa, 15 rem. diarias/año)
    factor_grati = 1/6   (Régimen General, 2 sueldos/año)       |  1/12  (Pequeña Empresa, 2 medias rem./año)
    provision_cts = sueldo_devengado × factor_cts
    provision_gratificacion = sueldo_devengado × factor_grati

dias_vacaciones = 30 (Régimen General) | 15 (Micro/Pequeña, Ley 32353)
provision_vacaciones = sueldo_devengado × (dias_vacaciones / 360)     (0 si no es dependiente)
```

### 3.8 Renta de 5ta Categoría (retención mensualizada)

```
si NO es dependiente o sueldo_devengado <= 0:  renta_5ta = 0
si no:
    asig_mensual_renta = RMV × 10%   si tiene_asignacion_familiar, si no 0
    renta_anual = (sueldo_devengado + asig_mensual_renta) × 12
    deduccion = 7 UIT  (UIT 2026 = S/ 5500 → S/ 38,500)
    base_imponible = max(0, renta_anual − deduccion)

    Tramos progresivos sobre base_imponible (en UIT):
        hasta 5 UIT   → 8%
        5–20 UIT      → 14%
        20–35 UIT     → 17%
        35–45 UIT     → 20%
        más de 45 UIT → 30%

    impuesto_mensual = impuesto_anual / 12
    renta_5ta = impuesto_mensual            (mes completo)
              = impuesto_mensual / 2         (quincena)
```

**Fidelidad deliberada a una inconsistencia ya presente en el diseño original:** esta base SUMA la asignación familiar a la renta anual sin verificar que el régimen sea "general" (a diferencia de `asignacion_familiar`, que sí lo verifica antes de pagarla). No se corrigió — se documenta y se copia tal cual.

La proyección se hace sobre `sueldo_devengado` (lo realmente ganado), no sobre el sueldo teórico — si no, un empleado con 0% de asistencia igual generaría una retención sobre un pago que nunca se hizo.

### 3.9 Totales finales

```
total_ingresos            = sueldo_devengado + pago_horas_extra + asignacion_familiar + pago_domingo + pago_feriado
total_descuentos_legales  = descuento_pension + renta_5ta
neto_a_pagar              = 0                                              si sueldo_periodo <= 0
                          = max(0, total_ingresos − total_descuentos_legales)

bajo_rmv = sueldo_base > 0 AND sueldo_base < RMV_vigente (S/ 1130)          ← solo informativo/alerta, no altera ningún cálculo
```

---

## 4. Parámetros legales vigentes (hardcodeados, 2026 — hay que actualizarlos si cambian por norma)

| Parámetro | Valor | Base legal |
|---|---|---|
| ONP | 13% | D.L. 19990 |
| AFP aporte obligatorio | 10% | D.L. 25897 |
| AFP prima de seguro | 1.37% | 2026, tope S/ 12,209.11 (no modelado el tope) |
| AFP comisión Integra / Prima / Profuturo / Habitat | 1.55% / 1.60% / 1.69% / 1.47% | SBS |
| EsSalud (empleador) | 9% | Ley 26790 |
| RMV vigente | S/ 1,130 | D.S. 001-2025-TR |
| Asignación familiar | 10% RMV = S/ 113 | D.S. 035-90-TR |
| UIT vigente | S/ 5,500 | R.M. SUNAT 2026 |
| Deducción Renta 5ta | 7 UIT = S/ 38,500 | — |
| CTS Régimen General / Pequeña Empresa | 1/12 · 1/24 | — |
| Gratificación Régimen General / Pequeña Empresa | 1/6 · 1/12 | — |
| Vacaciones Régimen General / Micro-Pequeña | 30 / 15 días | Ley 32353 |
| Recargo hora extra | 25% (2 primeras h) / 35% (resto) | D.L. 854 |
| Sobretasa domingo/feriado | 100% (doble) para dependientes; tarifa simple para practicantes | D.Leg. 713 Art. 3/4 (domingo), Art. 8/9 (feriado) |

**No modelado:** el tope de la prima de seguro AFP (S/ 12,209.11) — si un sueldo supera ese tope, el cálculo actual seguiría aplicando 1.37% sobre la base completa sin recortar. Punto a verificar si hay sueldos altos en la empresa.

---

## 5. Cómo se llega al `InsumoEmpleado` en cada endpoint

Tres puntos de entrada arman `InsumoEmpleado` de forma casi idéntica (mismo patrón, código duplicado a propósito para mantenerlos independientes):

1. **`GET /planilla/preview`** (`routers/planilla.py`) — SOLO LECTURA. Sueldo base: `EmpleadoConcepto` sobre el concepto `SUELDO_BASE` (si el catálogo aún no existe para la empresa, `sueldo_base = 0` para TODOS). Config previsional: `EmpleadoPlanillaConfig` (default: ONP, sin asignación familiar, si el empleado no tiene fila propia).
2. **`POST /planilla/calcular`** (`planilla_service.calcular_planilla`) — Igual, pero además siembra el catálogo estándar de conceptos (`asegurar_catalogo_estandar`, idempotente) y persiste `Planilla` + `BoletaPago` + `BoletaPagoDetalle` en estado `"calculada"`.
3. Ambos llaman a `resumen_horas_periodo` con el rango de fechas: `preview` acepta cualquier rango (incluida media quincena, es solo una VISTA); `calcular_planilla` siempre usa el **mes calendario completo** del `PeriodoContable` (la quincena nunca se persiste como planilla real — es un simulador de solo lectura).

### Persistencia (`calcular_planilla`)

Cada concepto con monto > 0 se agrega como una fila de `BoletaPagoDetalle`, mapeado 1:1 desde el `DesgloseBoleta`:

| Código | Origen |
|---|---|
| `SUELDO_BASE` | `desglose.sueldo_devengado` |
| `HRS_EXTRA` | `desglose.pago_horas_extra` |
| `DOMINGO_TRABAJADO` | `desglose.pago_domingo` |
| `FERIADO_TRABAJADO` | `desglose.pago_feriado` |
| `ASIG_FAMILIAR` | `desglose.asignacion_familiar` |
| `PENSION_ONP` **o** `AFP_APORTE`+`AFP_PRIMA`+`AFP_COMISION` | `desglose.descuento_pension` (excluyentes según `sistema_pension`) |
| `RENTA_5TA` | `desglose.renta_5ta` |
| `ESSALUD` | `desglose.aporte_essalud` |

`total_cts`/`total_gratificacion`/`total_vacaciones` se guardan en la `BoletaPago` como columnas aparte (informativas, **no** generan `BoletaPagoDetalle`, no entran a los asientos contables).

Conceptos configurados manualmente por la empresa (fuera de este catálogo legal) se siguen aplicando con el mecanismo genérico original (override por empleado o `monto_referencial`).

`_recompute_boleta`/`_recompute_planilla` tienen un **piso de seguridad**: el neto de una boleta o de la planilla completa nunca puede quedar negativo, sin importar la combinación de conceptos.

---

## 6. Ciclo de vida de una Planilla

```
calcular_planilla()  → estado "calculada"    (sin asiento contable — se puede editar boleta a boleta)
        │
        ├─► editar_boleta_detalle()  (override manual, solo mientras está "calculada")
        │
        ├─► aprobar_planilla()  → estado "aprobada"   + asiento de PROVISIÓN:
        │        Db 621 Remuneraciones (ingresos) + Db 627 Aportes empleador
        │        Cr 411 Remuneraciones por pagar (neto) + Cr 4032 (retenciones) + Cr 4031 (aportes empleador)
        │
        ├─► marcar_pagada()  → estado "pagada"   + asiento de PAGO:
        │        Db 411 (neto) + Db 4032 + Db 4031  /  Cr 101 Caja
        │
        └─► anular_planilla()  → estado "anulada"   (SOLO permitido desde "calculada", nunca desde "aprobada"
                                   — una aprobada ya generó asiento contable y requeriría reversión formal)
```

Solo puede existir **una planilla vigente** (no anulada) por `(empresa_id, periodo_id)`. Las anuladas no bloquean: se eliminan (junto a sus boletas) al recalcular, liberando el cupo.

---

## 7. Puntos a revisar si "algo parece estar fallando"

Basado en el diseño real (no hipótesis) — lista de sospechosos ordenados por probabilidad:

1. **Feriados no registrados.** El motor solo detecta feriados que la empresa cargó manualmente en `FeriadoEmpresa`. Si un feriado real no está en esa tabla, ese día se calcula como jornada normal (sin sobretasa, sin excluir de la meta de horas).
2. **Sueldo base en S/ 0.00.** Si nadie guardó el sueldo de un empleado (`PUT /planilla/empleados/{id}/sueldo-base`), TODO sale en 0 para él (sueldo, horas extra, domingo, feriado, pensión, renta — todo depende de `valor_hora = sueldo_base / 30 / 8`). Esto es el comportamiento esperado, no un bug, pero es la causa más común de "boletas en cero".
3. **Turno no asignado o mal configurado.** Sin `TurnoEmpleado` vigente, cae al default 8h Lunes-Viernes — si el empleado real trabaja otro horario, `meta_horas`/`horas_extra`/`horas_faltantes` van a estar mal para él específicamente.
4. **Falta el registro de salida.** Sin `entrada` Y `salida` ese día, `_horas_dia` = 0 (aunque haya marcado entrada). Revisar si hay marcaciones "colgadas" (entrada sin salida).
5. **Solicitud de Permanencia Extra sin aprobar.** Aparece la alerta "sin trámite" en la boleta — es informativo, NO reduce el pago, pero puede confundir si se espera que bloquee.
6. **Trámite de horas extra vs. horas realmente trabajadas.** `horas_extra_pagables` trunca a la hora completa (a pedido explícito del usuario) — si un empleado trabajó 3.9h extra, solo se le pagan 3h con recargo; las 0.9h no pagadas SÍ aparecen en `horas_extra` (campo informativo) pero no en el monto.
7. **Quincena (`q1`/`q2`) es solo una vista.** Nunca se persiste como planilla real — si se espera que "calcular" en modo quincena genere una `Planilla`, no ocurre: el ciclo real (`calcular→aprobar→pagar`) siempre opera sobre el mes calendario completo del `PeriodoContable`.
8. **Tope de la prima de seguro AFP no modelado** (ver §4) — sueldos muy altos con AFP podrían calcular de más en `afp_prima_seguro`.
9. **Bug de frontend ya corregido en esta misma sesión** (commit `3c219c91`, rama `frontend`): los campos `Decimal` del backend llegan como **string** en el JSON (no como number) — sumarlos con `+` sin convertir a `Number()` producía concatenación de texto en vez de suma en los KPIs de la pantalla de Planilla. Si sigues viendo totales raros en el navegador, confirmar que el frontend desplegado ya incluye ese commit.

---

## 8. Archivos fuente (para verificar cualquier punto de este documento contra el código real)

- `BACKEND/app/services/planilla_calculo_service.py` — motor de cálculo puro (fórmulas).
- `BACKEND/app/services/planilla_asistencia_service.py` — `resumen_horas_periodo` (asistencia → horas).
- `BACKEND/app/services/planilla_service.py` — orquestación (calcular/aprobar/pagar/anular, catálogo, asientos).
- `BACKEND/app/routers/planilla.py` — endpoints HTTP, incluido `GET /planilla/preview`.
- `BACKEND/app/schemas/planilla.py` — contratos Pydantic (lo que ve el frontend).
- `BACKEND/tests/test_planilla_calculo_service.py` — casos de prueba (A–S), cada uno con su valor esperado calculado independientemente.
- `BACKEND/app/routers/rrhh_asistencia.py` — helpers compartidos (`_dias_laborables`, `_feriados_set`, `_horas_dia`, `_parse_dias_lab`).
