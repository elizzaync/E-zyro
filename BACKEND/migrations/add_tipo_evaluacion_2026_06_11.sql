-- ============================================================
-- Migración: tipo en criterios y evaluaciones
-- Fecha: 2026-06-11
-- Cada criterio y cada evaluación pertenece a uno de 3 tipos:
--   rrhh | jefe_directo | companero
-- Los registros existentes quedan como 'rrhh' por defecto.
-- ============================================================

BEGIN;

ALTER TABLE criterio_evaluacion
    ADD COLUMN IF NOT EXISTS tipo VARCHAR(20) NOT NULL DEFAULT 'rrhh';

ALTER TABLE evaluacion
    ADD COLUMN IF NOT EXISTS tipo VARCHAR(20) NOT NULL DEFAULT 'rrhh';

CREATE INDEX IF NOT EXISTS idx_criterio_eval_tipo
    ON criterio_evaluacion(empresa_id, tipo, activo);

COMMIT;
