-- Migración: agrega uuid_cliente a registro_asistencia para idempotencia offline
-- Ejecutar una sola vez en Railway → Data → Query

ALTER TABLE registro_asistencia
    ADD COLUMN IF NOT EXISTS uuid_cliente VARCHAR(36) NULL;

-- Índice único compuesto (multi-tenant seguro)
CREATE UNIQUE INDEX IF NOT EXISTS uq_asistencia_empresa_uuid_cliente
    ON registro_asistencia (empresa_id, uuid_cliente)
    WHERE uuid_cliente IS NOT NULL;
