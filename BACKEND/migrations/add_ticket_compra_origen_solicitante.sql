-- Compra del faltante de un préstamo: el ticket nace directo en Compras
-- (sin requerimiento). 'origen' marca su procedencia para, al recibir el
-- ingreso, auto-generar el préstamo de las unidades compradas; 'solicitante_id'
-- guarda al técnico para asignarle ese préstamo.
ALTER TABLE ticket_compra
  ADD COLUMN IF NOT EXISTS origen VARCHAR(30);
ALTER TABLE ticket_compra
  ADD COLUMN IF NOT EXISTS solicitante_id UUID;
