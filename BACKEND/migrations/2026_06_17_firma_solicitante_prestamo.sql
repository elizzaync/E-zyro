-- Firma del solicitante al pedir el lote de equipos/herramientas (préstamo).
-- Aditivo y nullable: seguro de aplicar sobre la tabla viva.
ALTER TABLE prestamo ADD COLUMN IF NOT EXISTS firma_solicitante_url   text;
ALTER TABLE prestamo ADD COLUMN IF NOT EXISTS firma_solicitante_fecha timestamp;
