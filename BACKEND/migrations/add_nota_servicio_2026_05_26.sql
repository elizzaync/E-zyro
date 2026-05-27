-- ============================================================
-- Migración: Notas a nivel servicio
-- Fecha: 2026-05-26
-- Liga seguimiento_proyecto (notas) a un servicio concreto para
-- poder listar/editar/eliminar notas por servicio. Las notas
-- antiguas quedan con proyecto_servicio_id = NULL (nivel proyecto).
-- ============================================================

BEGIN;

ALTER TABLE seguimiento_proyecto
    ADD COLUMN IF NOT EXISTS proyecto_servicio_id VARCHAR(36)
        REFERENCES proyecto_servicio(id);

CREATE INDEX IF NOT EXISTS idx_seguimiento_ps
    ON seguimiento_proyecto(proyecto_servicio_id);

COMMIT;
