ALTER TABLE requerimiento_detalle ADD COLUMN IF NOT EXISTS motivo_rechazo VARCHAR(30);
COMMENT ON COLUMN requerimiento_detalle.motivo_rechazo IS 'sin_tiempo_compra | no_disponible_catalogo | duplicado | otro — solo relevante cuando estado_item=rechazado';
