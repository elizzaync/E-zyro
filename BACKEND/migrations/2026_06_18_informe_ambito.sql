-- Fase 3 — Equipos Intervenidos: separar informes de cliente vs internos y
-- vincular el informe general con su carta de garantía.
--
-- Tabla viva → ALTER manual (create_all no altera columnas existentes).
-- 'cliente' por defecto preserva el comportamiento actual del portal
-- (los informes pre/final existentes siguen visibles).
--
-- Correr con: railway run -s Postgres-SjrN python <script con SessionLocal>

ALTER TABLE informe_servicio
    ADD COLUMN IF NOT EXISTS ambito varchar(10) NOT NULL DEFAULT 'cliente';

ALTER TABLE informe_servicio
    ADD COLUMN IF NOT EXISTS garantia_id varchar(36);
