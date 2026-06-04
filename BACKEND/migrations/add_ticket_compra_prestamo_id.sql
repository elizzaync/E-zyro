-- Vincula la compra del faltante con el préstamo original. Al recibir la
-- compra, si ese préstamo sigue pendiente (no entregado) las unidades
-- compradas se fusionan en él (una sola entrega); si ya se entregó, la compra
-- genera un préstamo nuevo.
ALTER TABLE ticket_compra
  ADD COLUMN IF NOT EXISTS prestamo_id UUID;
