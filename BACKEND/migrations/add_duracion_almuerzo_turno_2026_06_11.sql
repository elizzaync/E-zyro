-- ============================================================
-- Migración: duracion_almuerzo_minutos en turno
-- Fecha: 2026-06-11
-- Necesaria para que el scheduler calcule cuándo avisar al
-- empleado antes de que termine su descanso de almuerzo.
-- ============================================================

BEGIN;

ALTER TABLE turno
    ADD COLUMN IF NOT EXISTS duracion_almuerzo_minutos INTEGER NOT NULL DEFAULT 60;

COMMIT;
