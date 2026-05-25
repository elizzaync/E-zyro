-- ============================================================
-- MIGRACIÓN: add_operaciones_crud_2026_05_25
-- Agrega campos necesarios para el CRUD completo de
-- Proyectos / Servicios / Procedimientos y configuración
-- de equipos técnicos.
-- Es idempotente: usa IF NOT EXISTS en cada paso.
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. procedimiento — fecha_inicio_tarea para Gantt
-- ──────────────────────────────────────────────────────────────
ALTER TABLE procedimiento
    ADD COLUMN IF NOT EXISTS fecha_inicio_tarea DATE;

-- ──────────────────────────────────────────────────────────────
-- 2. proyecto_miembro — aseguramos que la constraintexiste
--    (ya debería existir, pero por si acaso)
-- ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_proyecto_empleado'
    ) THEN
        ALTER TABLE proyecto_miembro
            ADD CONSTRAINT uq_proyecto_empleado
            UNIQUE (proyecto_id, empleado_id);
    END IF;
END$$;

COMMIT;
