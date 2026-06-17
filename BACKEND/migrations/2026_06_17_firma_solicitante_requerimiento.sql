-- Firma del solicitante al enviar el lote de requerimiento a Logística.
-- Aditivo y nullable: seguro de aplicar sobre la tabla viva.
ALTER TABLE requerimiento ADD COLUMN IF NOT EXISTS firma_solicitante_url   text;
ALTER TABLE requerimiento ADD COLUMN IF NOT EXISTS firma_solicitante_fecha timestamp;
