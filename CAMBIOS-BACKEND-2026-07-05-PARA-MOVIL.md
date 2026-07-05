# Cambios en el backend (2026-07-05) — qué le afecta a la app móvil

Este documento lo generó Claude tras aplicar cambios en `C:\E-zyro\BACKEND` y
`C:\E-zyro-frontend`. **No se tocó ni un archivo de este repo (`e_zyro_app`)** —
todo lo de abajo es para que sepas qué cambió del lado del servidor y qué
podrías (opcionalmente) adoptar acá cuando tengas tiempo.

## 1. Cambio de comportamiento que SÍ te afecta sin que cambies nada

`POST /logistica/requerimientos/{id}/aprobar` — cuando logística NO manda una
decisión explícita por ítem (o sea, aprobación automática/por defecto), antes
se aprobaba de stock con solo `stock_disponible >= cantidad_solicitada`. Ahora
también respeta el mínimo de reserva configurado: se aprueba de stock solo si
`stock_disponible - cantidad_solicitada >= stock_minimo`; si no, el ítem se
manda a compra (`estado_item = "para_compra"`), igual que antes cuando no
había stock.

**Qué vas a notar en la app:** algunos ítems que antes se aprobaban directo del
almacén ahora pueden aparecer como "en compra" con más frecuencia, si ese
material está cerca de su mínimo configurado. No es un bug — es la
protección de stock mínimo que antes no existía en la decisión automática.
Logística sigue pudiendo forzar "aprobar" manualmente por ítem si igual
quiere sacarlo del almacén (eso no cambió).

## 2. Préstamo de equipos — ahora respeta el mínimo de reserva (parcial)

`POST /prestamos/servicio/{servicio_id}` (crear préstamo) y
`GET /prestamos/equipos-catalogo` ya restan el mínimo configurado del equipo
(`atributos.stock_minimo`, el mismo campo `stockMinimo` que ya usan en el
formulario de equipos) al calcular cuánto hay disponible para prestar.

**Pendiente conocido, NO implementado todavía:** el flujo de **borrador de
préstamo** (`GET/POST /prestamos/servicio/{id}/borrador`,
`POST .../borrador/item`) — el que arma la lista antes de enviarla — **todavía
NO resta el mínimo** al mostrar disponibilidad. O sea que en el borrador puede
aparecer más "disponible" del que realmente se puede prestar; recién se
corrige en el momento de crear el préstamo final. Si ustedes muestran
"disponible" en la pantalla de armado del borrador (`pantalla_prestamos_servicio.dart`
o similar), puede verse inconsistente con lo que después realmente se presta.
Avísenme si quieren que también parchee esa parte.

## 3. Motivo de rechazo categorizado (nuevo campo opcional)

Al rechazar un ítem o un requerimiento completo, ahora se puede mandar un
campo opcional `motivoRechazo` (string) junto al `observacion` de siempre:

```
"sin_tiempo_compra" | "no_disponible_catalogo" | "duplicado" | "otro"
```

- `POST /logistica/requerimientos/{id}/rechazar` — body ahora acepta
  `motivoRechazo` opcional (además de `observacion`, que sigue siendo obligatorio).
- Dentro de `POST /logistica/requerimientos/{id}/aprobar`, cada decisión por
  ítem (`decisiones: [...]`) ahora acepta `motivoRechazo` y `observacion`
  opcionales cuando `decision: "rechazar"`.
- El detalle de un requerimiento (`RequerimientoItemOut`) ahora devuelve
  `motivoRechazo` cuando el ítem está rechazado.

**Es 100% opcional** — si no lo mandan, todo sigue funcionando exactamente
igual que antes (queda `null`). Lo agregamos porque cuando algo se rechaza por
falta de tiempo para comprarlo, ahora el técnico recibe una notificación más
específica ("Se rechazó: Multímetro Fluke 87V. Revisa si puedes
reemplazarlo.") en vez del mensaje genérico de antes. Si en algún momento
quieren que el técnico pueda elegir el motivo o ver un botón directo de
"reemplazar" en el borrador de materiales, esa parte de UI quedó pendiente
(no se tocó nada de Flutter en esta tanda, fue explícitamente fuera de
alcance).

## 4. Firma digital global — mecanismo que YA EXISTÍA, ahora lo usa el web

Esto es informativo, no requiere ningún cambio de su parte, pero por si no lo
sabían: el backend tiene desde antes una tabla `FirmaDigital` por usuario
(`GET /permisos/mi-firma`, `POST /permisos/guardar-firma`) que guarda la firma
de cada empleado y la reemplaza si vuelve a firmar distinto. **El móvil no usa
este mecanismo en ningún lado** — dibuja una firma nueva cada vez, en todas
las pantallas (asistencia, requerimientos, préstamos, etc.), sin guardarla ni
reutilizarla.

El web ahora sí lo usa (recién lo conectamos en Requerimientos y en el nuevo
módulo de Préstamos-web). Si en algún momento quieren que el técnico no tenga
que redibujar su firma cada vez en el celular, este es el mecanismo a
reutilizar — ya está probado y funcionando del lado del servidor, sería
trabajo puramente de UI en Flutter (leer `mi-firma` al abrir un modal de
firma, ofrecer "usar mi firma guardada", y llamar a `guardar-firma` cuando
dibujen una nueva).

## 5. Nada de esto rompe contratos existentes

Todos los cambios son aditivos (campos nuevos opcionales) o cambios de
comportamiento interno (la decisión automática de aprobación) — ningún
endpoint que ya consume la app cambió de forma, ni dejó de aceptar lo que ya
mandaban. No hace falta ningún cambio urgente en el móvil por esto; los
puntos 2, 3 y 4 son mejoras opcionales para cuando tengan tiempo.
