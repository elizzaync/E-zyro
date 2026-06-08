# Auditoría Logística — E-zyro ERP

**Fecha:** 2026-06-08  
**Alcance:** Flujo Requerimientos → Compras → Entradas → Salidas → Retornos  
**Estado:** Implementado

---

## Hallazgos críticos y correcciones aplicadas

### 1. Race condition en aprobación de Requerimientos (`aprobar_requerimiento`)

**Archivo:** `app/routers/logistica.py`  
**Problema:** El flujo previo hacía dos queries separadas (TOCTOU):
1. `_stock_de_material()` — lee el stock disponible
2. `db.query(Stock)...all()` — lee las filas para deducir

Entre ambas lecturas, otro proceso concurrente podía deducir el mismo stock, causando saldo negativo.

**Corrección:**
- Eliminado el pre-check `_stock_de_material(db, ...)`.
- La query de Stock ahora incluye `.with_for_update()` (SELECT FOR UPDATE).
- La comprobación de disponibilidad se hace sobre las filas ya bloqueadas (`disponible_real = sum(...)`).
- Commit envuelto en `try/except` con `db.rollback()`.

---

### 2. Race condition en ingreso de Ticket de Compra (`_aplicar_ingreso_ticket`)

**Archivo:** `app/routers/logistica.py`  
**Problema:** La query `db.query(Stock).filter(...).first()` para sumar stock comprado no tenía bloqueo de fila. Dos recepciones simultáneas del mismo material podían leer el mismo saldo y ambas sumar sobre él (lost update).

**Corrección:**
- Añadido `.with_for_update()` a la query de Stock.
- Commit envuelto en `try/except` con `db.rollback()`.

---

### 3. Falta de transacción ACID en Retornos (`completar_retorno`)

**Archivo:** `app/routers/logistica.py`  
**Problemas:**
- Sin `try/except` ni `rollback`: un fallo al procesar el ítem N dejaba los ítems 1..N-1 comprometidos y los N..M sin procesar.
- Sin bloqueo de fila en la query de Stock.
- Sin validación: se podía confirmar más unidades de las entregadas (`cantidad_confirmada > cantidad_entregada`).

**Correcciones:**
- Validación previa: si `cantidad_confirmada > cantidad_entregada` en cualquier ítem → HTTP 400 antes de tocar la DB.
- Stock query con `.with_for_update()`.
- Bucle principal + commit envueltos en `try/except` con `db.rollback()`.
- `except HTTPException` re-lanzado para no envolverlo en 500.

---

### 4. Race condition en recepción de Orden de Compra (`recibir_orden`)

**Archivo:** `app/routers/compras.py`  
**Problema:** La query de Stock para sumar la cantidad recibida no tenía bloqueo de fila. Recepciones parciales concurrentes del mismo material podían generar lost updates.

**Correcciones:**
- Añadido `.with_for_update()` a la query de Stock.
- Commit envuelto en `try/except` con `db.rollback()`.

---

### 5. Frontend: `setDecision('aprobar')` sin stock disponible

**Archivo:** `src/app/features/logistica/components/requerimientos/requerimientos.component.ts`  
**Problema:** El usuario podía forzar la decisión 'aprobar' en un ítem sin stock (`!it.enStock`), bypasando la lógica de inicialización. El backend rechazaría silenciosamente (redirigiendo a compra), pero el resumen del modal mostraba el ítem como "aprobado".

**Corrección:**
- `setDecision()` ahora verifica `!item.enStock && !item.esCompraExterna` antes de asignar 'aprobar'.
- Si la condición se cumple, fuerza 'compra' y muestra un toast de aviso.

---

### 6. Frontend: `cantidadConfirmada` sin validación de límite en Retornos

**Archivo:** `src/app/features/logistica/components/retornos-tabla/retornos-tabla.component.ts`  
**Problema:** El campo `cantidadConfirmada` no tenía validación client-side de `<= cantidadEntregada`. El backend ya rechaza estos casos (ver corrección 3), pero el usuario podía llegar al error sin feedback previo.

**Correcciones:**
- Getter `inspeccionInvalida`: retorna `true` si algún ítem supera su límite.
- `guardarInspeccion()` evalúa `inspeccionInvalida` y muestra toast de error antes de llamar al API.

---

## Patrón aplicado (resumen)

```python
# Bloqueo de fila (evita race condition)
row = db.query(Model).filter(...).with_for_update().first()

# Transacción ACID
try:
    # mutaciones
    db.commit()
except HTTPException:
    db.rollback()
    raise
except Exception:
    db.rollback()
    raise HTTPException(status_code=500, detail="Error. No se realizaron cambios.")
```

---

## Flujos verificados (sin cambios necesarios)

| Endpoint | Estado |
|---|---|
| `POST /requerimientos/{id}/aprobar` | Corregido |
| `POST /tickets-compra/{id}/ingreso` | Corregido |
| `POST /retornos/{id}/completar` | Corregido |
| `POST /ordenes-compra/{id}/recibir` | Corregido |
| `GET /*` (consultas) | Sin cambios (solo lectura) |
| `POST /requerimientos` (crear) | Sin cambios (sin stock) |
| `POST /retornos` (crear) | Sin cambios (sin stock) |
