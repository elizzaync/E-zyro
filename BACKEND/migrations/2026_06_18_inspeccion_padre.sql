-- Fase B — Equipos Intervenidos: vincular una inspección con una anterior del
-- mismo equipo (cadena de trazabilidad "da seguimiento a…").
--
-- Tabla viva → ALTER manual (create_all no altera columnas existentes).
-- Tipo uuid nativo para empatar con la PK uuid de historial_inspeccion.
--
-- Correr con:  railway run -s Postgres-SjrN psql "$DATABASE_PUBLIC_URL" -f migrations/2026_06_18_inspeccion_padre.sql
-- (o vía un script .py con SessionLocal, como el resto del proyecto).

ALTER TABLE historial_inspeccion
    ADD COLUMN IF NOT EXISTS inspeccion_padre_id uuid
    REFERENCES historial_inspeccion(id);

-- Índice para resolver rápido "hijos de" una inspección.
CREATE INDEX IF NOT EXISTS ix_historial_inspeccion_padre
    ON historial_inspeccion (inspeccion_padre_id);
