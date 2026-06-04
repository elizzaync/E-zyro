-- Recepción de préstamos con doble firma + consenso (cinema-seat), igual que HU-16
-- materiales. firma_entregador_url = firma de logística al despachar;
-- firmando_por_id/desde = lock anti-duplicidad mientras un técnico firma la recepción.
ALTER TABLE prestamo
  ADD COLUMN IF NOT EXISTS firma_entregador_url TEXT;
ALTER TABLE prestamo
  ADD COLUMN IF NOT EXISTS firmando_por_id VARCHAR(36);
ALTER TABLE prestamo
  ADD COLUMN IF NOT EXISTS firmando_desde TIMESTAMP;
