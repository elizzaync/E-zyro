-- ============================================================
-- Fix: Ampliar foto_asistencia.resultado
-- Fecha: 2026-06-11
-- "sin_evidencia_offline" (21 caracteres) excede VARCHAR(20) y
-- causaba StringDataRightTruncation en POST /asistencia/marcar
-- para registros sincronizados offline sin selfie.
-- ============================================================

BEGIN;

ALTER TABLE foto_asistencia
    ALTER COLUMN resultado TYPE VARCHAR(30);

COMMIT;
