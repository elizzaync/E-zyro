-- Firma del receptor (técnico) al entregar un préstamo de equipos/herramientas.
ALTER TABLE prestamo
  ADD COLUMN IF NOT EXISTS firma_receptor_url TEXT;
