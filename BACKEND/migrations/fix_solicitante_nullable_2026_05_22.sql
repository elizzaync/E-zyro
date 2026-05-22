-- ============================================================
-- MIGRACIÓN: fix_solicitante_nullable_2026_05_22.sql
-- Propósito: permite crear borradores de requerimiento cuando
--            el usuario es Administrador sin registro de empleado.
-- Es idempotente: el DO block comprueba antes de alterar.
-- ============================================================

BEGIN;

-- 1. Quitar la restricción NOT NULL de requerimiento.solicitante_id
--    (los administradores no tienen fila en la tabla empleado)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name  = 'requerimiento'
          AND column_name = 'solicitante_id'
          AND is_nullable = 'NO'
    ) THEN
        ALTER TABLE requerimiento
            ALTER COLUMN solicitante_id DROP NOT NULL;
        RAISE NOTICE 'requerimiento.solicitante_id → ahora nullable';
    ELSE
        RAISE NOTICE 'requerimiento.solicitante_id ya era nullable, sin cambios';
    END IF;
END$$;

COMMIT;
