-- ============================================================
-- MIGRACIÓN COMPLEMENTARIA: fix_solicitante_nullable_2026_05_22.sql
-- Propósito: hace nullable requerimiento.solicitante_id para
--            admins sin registro de empleado.
--
-- ESTADO: OPCIONAL — el backend ya resuelve esto via fallback
--         (jefe_operaciones_id del proyecto). Aplica si quieres
--         limpiar la restricción a nivel de BD.
-- Es idempotente: verifica antes de alterar.
-- ============================================================

BEGIN;

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
