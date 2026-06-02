# ⚠️ Conflicto de diseño: flujo de recepción/firma de requerimientos

**Estado:** pendiente de resolver entre el equipo. No es un conflicto de git (los commits no chocan en el mismo archivo) — es que existen **dos modelos distintos** del cierre de un requerimiento.
**Commit actual al detectarlo:** `435d8fe1` (origin/Backend). Ese commit NO tocó `logistica.py`, así que la lógica de firma del compañero sigue vigente.

---

## Los dos modelos

### Modelo A — el que definió el dueño del producto (1 paso)
```
solicitar → pendiente
  ├─ hay stock → listo
  └─ sin stock → comprando → (llega compra) → listo
listo → FIRMA del equipo → aprobado   (= recibido, ESTADO FINAL)
```
- Una sola firma (el equipo confirma que recibió).
- `aprobado` = recibido = final. No hay paso de logística posterior.

### Modelo B — lo que construyó el compañero (`7b9d60b4`, 2 pasos + doble firma)
```
listo → firmar (técnico)  → listo           (el técnico "reclama"/confirma)
listo → entregar (logística, rol logística) → entregado   (ESTADO FINAL)
```
- Dos firmas: receptor (`firma_receptor_url`) + entregador (`firma_entregador_url`).
- Estado final = `entregado`. `aprobado` queda **sin usar** en su modelo.
- Incluye **cinema-seat lock** (`firmando_por_id`, `firmando_desde`, timeout 2 min) para que solo un técnico firme a la vez.

---

## Dónde choca exactamente (en `BACKEND/app/routers/logistica.py`)

| Punto | Modelo A (dueño) | Modelo B (compañero, vigente en origin) |
|---|---|---|
| `firmar_requerimiento` estado final | debe poner `aprobado` | pone `listo` |
| `firmar_requerimiento` guard | exigir `estado == "listo"` | acepta `aprobado`/`listo`/`comprando` |
| Cinema-seat lock en `firmar` | hay que **liberarlo** (`firmando_por_id = None`) | NO se libera en firmar (solo en `entregar`/`liberar`) → en modelo A quedaría pegado |
| `entregar_requerimiento` → `entregado` | no existe / se elimina | es el paso final |
| Valor `aprobado` | estado final (recibido) | sin uso |

## Cambios LOCALES sin pushear (implementan el Modelo A)
- `BACKEND/app/routers/logistica.py`: `firmar` → exige `listo`, pone `aprobado`; docstring/notificación ajustadas; `registrar_ingreso_compra` ya no reabre un `aprobado`.
- **App móvil** (`e-zyro-app`): `recepcion_models.dart` + `_RecepcionCard` ya alineados al Modelo A (`comprando`=en compra, `listo`=firmar, `aprobado`=recibido). Ya pasa `flutter analyze`.
- ⚠️ Estos cambios **NO** se han pusheado (esperan la decisión).

## Lo que NO choca (confirmado)
- `435d8fe1` está construido sobre nuestro commit `d7b3f3e3` → enforcement de estado, realtime y arreglo de sintaxis **conservados** en origin.
- `435d8fe1` amplió las columnas de firma `VARCHAR(500)` → `TEXT`: **bueno**, nuestra firma base64 las necesitaba (habría reventado en VARCHAR(500)).
- No hay CHECK constraint en `estado` → `aprobado` es valor válido en BD.

---

## Para resolver (decidir entre los 3)
1. **Modelo A (1 paso)** — aplicar los cambios locales, liberar el lock en `firmar`, y desactivar/repurposar `entregar`. Avisar al compañero (anula su flujo de 2 pasos).
2. **Modelo B (2 pasos)** — revertir el cambio local de firma; re-alinear el móvil para que el estado final sea `entregado`. Conserva el lock y la doble firma del compañero.
3. **Híbrido** — firma del técnico → `aprobado` (recibido) + `entregar` opcional de logística → `entregado`. Sobreviven ambos trabajos, pero hay que coordinar la semántica.

**Acción inmediata recomendada:** hablarlo con el compañero antes de pushear el cambio de firma, porque pisa su lógica de `firmar`/`entregar`.
