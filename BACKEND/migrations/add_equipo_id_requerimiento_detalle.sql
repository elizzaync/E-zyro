-- Permite que una línea de requerimiento referencie un EQUIPO existente
-- (no solo un material). Se usa para la "compra del faltante" de un préstamo:
-- al pedir más de lo disponible, el excedente se compra y, al recibirlo,
-- reabastece el equipo existente en vez de crear uno nuevo.
ALTER TABLE requerimiento_detalle
  ADD COLUMN IF NOT EXISTS equipo_id UUID REFERENCES equipo(id);
