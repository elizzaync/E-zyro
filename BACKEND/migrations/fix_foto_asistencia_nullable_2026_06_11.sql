-- ============================================================
-- Fix: foto_asistencia.url_cloudinary y public_id_cloudinary
-- Fecha: 2026-06-11
-- Registros offline sin selfie (sin_evidencia_offline) no suben
-- imagen a Cloudinary. La columna debe admitir NULL para estos casos.
-- ============================================================

BEGIN;

ALTER TABLE foto_asistencia
    ALTER COLUMN url_cloudinary       DROP NOT NULL,
    ALTER COLUMN public_id_cloudinary DROP NOT NULL;

COMMIT;
