# Contexto — Mejora de la Boleta de Pago (PDF)

> Documento de trabajo para no perder contexto entre sesiones.
> Fecha de análisis: 2026-06-16

## 1. Qué se quiere mejorar

Mejorar **solo la boleta individual** ("BOLETA DE PAGO" del trabajador), que se
genera desde:

- Tabla principal → columna **"Boleta"** → botón **"Ver"** (abre el modal).
- Dentro del modal → botón **"Descargar PDF"**.

**NO** tocar la "Planilla Mensual de Remuneraciones" (el PDF consolidado de todos
los trabajadores).

## 2. Dónde vive el generador del PDF (IMPORTANTE)

El PDF de la boleta **NO se genera en el backend**. Se genera en el **frontend**
con `html2pdf.js`.

### Frontend (es el que hay que mejorar)
`C:\E-zyro-frontend\src\app\features\rrhh\planillas\planillas.component.ts`

- `construirVoucherHtml(emp)` → **arma el HTML de la BOLETA individual** (este es
  el que se mejora). Líneas ~600-770.
- `descargarPdf(emp)` → llama a `crearDivVoucher` + `html2pdf().save()`.
- `enviarALegajo(emp)` → mismo HTML, sube el PDF al Legajo Digital (backend).
- `construirPlanillaMensualHtml(lista)` → **PLANILLA MENSUAL consolidada. NO TOCAR.**

Datos que usa la boleta del frontend (cálculo client-side):
- Sueldos base: `localStorage` (`ezp_sueldos_v1`), no backend.
- Asistencia: `RrhhService.getResumenAsistencia` → backend `rrhh_asistencia.py`.
- Régimen, pensión (ONP/AFP), asignación familiar, Renta 5ta: constantes y
  cálculos dentro del propio `.ts` (referenciales).

### Backend (contexto, NO genera la boleta PDF)
`C:\E-zyro\BACKEND`

- `app\routers\planilla.py` → **solo CRUD/JSON** (conceptos, planilla, boletas,
  asignaciones). No produce PDFs.
- `app\services\planilla_service.py` → cálculo real de planilla:
  `calcular_planilla` genera `Planilla` + `BoletaPago` + `BoletaPagoDetalle`
  con `total_ingresos / total_descuentos / total_aportes / total_neto`.
- `app\models\planilla.py` → modelos:
  - `ConceptoRemunerativo` (tipo: `ingreso|descuento|aporte_empleador`, `es_base`).
  - `Planilla`, `BoletaPago` (tiene `pdf_url`), `BoletaPagoDetalle`, `EmpleadoConcepto`.
- Infraestructura PDF del backend (reportlab/platypus), por si se migra a futuro:
  `app\services\pdf_docs.py`, `pdf_informe_servicio.py`, `pdf_service.py` (overlay).

> ⚠️ Hay **dos sistemas de planilla en paralelo**: el real/contable del backend
> (conceptos + asientos) y el de la pantalla RRHH del frontend (asistencia +
> localStorage). La boleta PDF actual usa el del **frontend**.

## 3. Cambios pedidos para la boleta (`construirVoucherHtml`)

1. **Firmas:** quitarlas, dejar el espacio libre.
2. **Título:** "BOLETA DE PAGO DE REMUNERACIONES" → **"BOLETA DE PAGO"**.
3. **Caja "Neto a Pagar":** quitar la caja gris destacada; el importe debe quedar
   **dentro de las tablas** (cierre/resumen de liquidación), bien colocado.
4. **Lenguaje contable experto:** todos los descuentos/conceptos redactados con
   terminología formal de contador.

## 4. Estado

- [x] Revertidos los cambios previos del frontend (working tree limpio).
- [x] Leído backend (planilla.py, planilla_service.py, models/planilla.py) y frontend.
- [x] Creado este MD de contexto.
- [x] Aplicadas las 4 mejoras SOLO en `construirVoucherHtml` (planilla mensual intacta).
  - Título → "BOLETA DE PAGO".
  - Firmas eliminadas (espacio libre).
  - Caja gris "Neto a Pagar" → tabla "Resumen de Liquidación" (3 filas:
    Total Remuneración Bruta, (−) Total Descuentos, **IMPORTE LÍQUIDO A PERCIBIR**).
  - Redacción contable formal en todos los ingresos y descuentos.
  - Sin errores de compilación (diagnostics limpios).
